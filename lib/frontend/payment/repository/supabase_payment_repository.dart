import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/beneficiary_model.dart';
import '../models/transaction_model.dart';
import '../models/wallet_card_model.dart';
import 'mock_payment_repository.dart';
import 'payment_repository.dart';

/// SupabasePaymentRepository integrates Supabase database tables (`wallets`,
/// `transactions`, and `beneficiaries`) alongside Stripe Connect and Trigger.dev.
///
/// It gracefully falls back to [MockPaymentRepository] when offline or uninitialized
/// to guarantee seamless offline UI resilience.
class SupabasePaymentRepository implements PaymentRepository {
  final SupabaseClient? client;
  final String _backendBaseUrl;
  final http.Client _httpClient;
  final MockPaymentRepository _fallbackRepository;

  SupabasePaymentRepository({
    this.client,
    String? backendBaseUrl,
    http.Client? httpClient,
  }) : _backendBaseUrl = backendBaseUrl ?? _defaultBaseUrl,
       _httpClient = httpClient ?? http.Client(),
       _fallbackRepository = MockPaymentRepository();

  SupabaseClient? get _supabase {
    if (client != null) return client;
    try {
      return Supabase.instance.client;
    } catch (_) {
      return null;
    }
  }

  /// JSON headers plus the signed-in person's Supabase access token.
  ///
  /// The backend identifies the payer from this token alone, then refuses an
  /// account with no verified phone. Without it every request looks like a
  /// stranger's, so even a verified account was told "Verify your phone number
  /// before sending money".
  Map<String, String> get _authHeaders {
    final headers = {'Content-Type': 'application/json'};
    try {
      final token = _supabase?.auth.currentSession?.accessToken;
      if (token != null) headers['Authorization'] = 'Bearer $token';
    } catch (e) {
      // Supabase never initialised (offline first launch, widget tests).
      debugPrint('[SupabasePaymentRepository] no access token to send: $e');
    }
    return headers;
  }

  static String get _defaultBaseUrl {
    if (kIsWeb) {
      return 'http://localhost:3000';
    }
    try {
      if (Platform.isAndroid) {
        return 'http://10.0.2.2:3000';
      }
    } catch (_) {}
    return 'http://localhost:3000';
  }

  @override
  Future<List<WalletCardModel>> getCards() async {
    final sb = _supabase;
    if (sb != null) {
      try {
        final records = await sb
            .from('wallets')
            .select()
            .timeout(const Duration(seconds: 4));

        if (records.isNotEmpty) {
          // One wallet row per card. Older databases hold a single row with no
          // card_id; that one still stands for the WPS card.
          final balances = <String, double>{};
          for (final row in records) {
            final cardId = row['card_id']?.toString() ?? 'card_wps';
            final raw = row['balance_bdt'];
            final balance = raw is num
                ? raw.toDouble()
                : double.tryParse(raw?.toString() ?? '');
            if (balance != null) balances[cardId] = balance;
          }

          final baseCards = await _fallbackRepository.getCards();
          return baseCards
              .map(
                (card) => balances.containsKey(card.id)
                    ? card.copyWith(balance: balances[card.id])
                    : card,
              )
              .toList();
        }
      } catch (e) {
        debugPrint('[SupabasePaymentRepository] getCards offline fallback: $e');
      }
    }
    return _fallbackRepository.getCards();
  }

  @override
  Future<List<BeneficiaryModel>> getBeneficiaries() async {
    final sb = _supabase;
    if (sb != null) {
      try {
        final records = await sb
            .from('beneficiaries')
            .select()
            .order('created_at', ascending: true)
            .timeout(const Duration(seconds: 4));

        if (records.isNotEmpty) {
          return records.map((record) {
            final name = record['name']?.toString() ?? '';
            final countryCode = record['country_code']?.toString() ?? 'BD';
            final countryInfo = _resolveCountryInfo(countryCode);

            return BeneficiaryModel(
              id: record['id']?.toString() ?? '',
              name: name,
              phoneOrAccount:
                  record['phone_number']?.toString() ??
                  record['phone_or_account']?.toString() ??
                  '',
              providerType:
                  record['provider']?.toString() ??
                  record['provider_type']?.toString() ??
                  'bKash',
              avatarUrl: record['avatar_url']?.toString() ?? '',
              initials: name.isNotEmpty
                  ? (name
                        .trim()
                        .split(' ')
                        .map((p) => p.isNotEmpty ? p[0] : '')
                        .take(2)
                        .join('')
                        .toUpperCase())
                  : 'U',
              isRecent: true,
              countryCode: countryCode,
              countryFlag: countryInfo['flag'] ?? '🇧🇩',
              countryName: countryInfo['name'] ?? 'Bangladesh',
              countryDialCode: countryInfo['dialCode'] ?? '+880',
              currency: countryInfo['currency'] ?? 'BDT',
              currencySymbol: countryInfo['symbol'] ?? '৳',
            );
          }).toList();
        }
      } catch (e) {
        debugPrint(
          '[SupabasePaymentRepository] getBeneficiaries offline fallback: $e',
        );
      }
    }
    return _fallbackRepository.getBeneficiaries();
  }

  @override
  Future<List<TransactionModel>> getTransactions({String? cardId}) async {
    final sb = _supabase;
    if (sb != null) {
      try {
        var query = sb.from('transactions').select();
        // This device's transactions, plus records with no sender (made before
        // anonymous sign-in, or written by the backend webhook).
        final userId = sb.auth.currentUser?.id;
        if (userId != null) {
          query = query.or('sender_id.eq.$userId,sender_id.is.null');
        }
        if (cardId != null) {
          query = query.eq('card_id', cardId);
        }
        final records = await query
            .order('created_at', ascending: false)
            .timeout(const Duration(seconds: 4));

        if (records.isNotEmpty) {
          return records.map((record) {
            final rawType = record['type']?.toString().toLowerCase();
            TransactionType type;
            switch (rawType) {
              case 'receive':
                type = TransactionType.receive;
                break;
              case 'subscription':
                type = TransactionType.subscription;
                break;
              case 'transfer':
                type = TransactionType.transfer;
                break;
              default:
                type = TransactionType.send;
            }

            final rawAmountBdt = record['amount_bdt'];
            final double? amountBdt = rawAmountBdt is num
                ? rawAmountBdt.toDouble()
                : double.tryParse(rawAmountBdt?.toString() ?? '');

            final rawConverted = record['converted_amount'];
            final double? convertedAmount = rawConverted is num
                ? rawConverted.toDouble()
                : double.tryParse(rawConverted?.toString() ?? '');

            final rawAmount =
                record['amount'] ??
                record['amount_bdt'] ??
                record['converted_amount'];
            final double amount = rawAmount is num
                ? rawAmount.toDouble()
                : (double.tryParse(rawAmount?.toString() ?? '') ?? 0.0);

            final DateTime timestamp = record['created_at'] != null
                ? (DateTime.tryParse(record['created_at'].toString()) ??
                      DateTime.now())
                : (record['timestamp'] != null
                      ? (DateTime.tryParse(record['timestamp'].toString()) ??
                            DateTime.now())
                      : DateTime.now());

            return TransactionModel(
              id:
                  record['id']?.toString() ??
                  'tx_${timestamp.millisecondsSinceEpoch}',
              title:
                  record['title']?.toString() ??
                  record['receiver_phone']?.toString() ??
                  'Remittance Recipient',
              subtitle:
                  record['subtitle']?.toString() ??
                  'Remittance to ${record['receiver_phone'] ?? 'Verified Account'}',
              amount: amount,
              amountBdt: amountBdt,
              convertedAmount: convertedAmount,
              currency: record['currency']?.toString() ?? 'BDT',
              timestamp: timestamp,
              type: type,
              status: TransactionModel.parseStatus(record['status']),
              cardId: record['card_id']?.toString() ?? 'card_wps',
              avatarUrl: record['avatar_url']?.toString(),
              iconCategory:
                  record['icon_category']?.toString() ??
                  (type == TransactionType.receive ? 'person' : 'send'),
              stripeSessionId: record['stripe_payment_id']?.toString(),
              // Both sides of the transfer: what the sender's bank was debited
              // (source amount and currency) and what the recipient's bank was
              // credited (the BDT amount plus any government incentive).
              debitedAmount: type == TransactionType.send
                  ? convertedAmount
                  : (type == TransactionType.transfer ? amountBdt : null),
              debitedCurrency: record['currency']?.toString() ?? 'BDT',
              creditedAmount: amountBdt == null
                  ? null
                  : (amountBdt +
                            (type == TransactionType.send
                                ? (num.tryParse(
                                        record['incentive_bdt']?.toString() ??
                                            '',
                                      ) ??
                                      0)
                                : 0))
                        .toDouble(),
              creditedCurrency: 'BDT',
            );
          }).toList();
        }
      } catch (e) {
        debugPrint(
          '[SupabasePaymentRepository] getTransactions offline fallback: $e',
        );
      }
    }
    return _fallbackRepository.getTransactions(cardId: cardId);
  }

  @override
  Future<Map<String, dynamic>> executeSendMoney({
    required String cardId,
    required dynamic beneficiary,
    required double sourceAmount,
    required String sourceCurrency,
    required double exchangeRate,
    required double amountBdt,
    required double incentiveBdt,
    required double vatOnCommission,
    required double usdAmount,
    String? connectedAccountId,
  }) async {
    final String beneficiaryName = beneficiary is BeneficiaryModel
        ? beneficiary.name
        : (beneficiary is Map
              ? (beneficiary['name']?.toString() ?? '')
              : beneficiary.toString());
    final String beneficiaryPhone = beneficiary is BeneficiaryModel
        ? beneficiary.phoneOrAccount
        : (beneficiary is Map
              ? (beneficiary['phone'] ??
                        beneficiary['phone_number'] ??
                        beneficiary['phoneOrAccount'] ??
                        '+8801700000000')
                    .toString()
              : '+8801700000000');

    // Make live POST request to backend remittance endpoint
    http.Response response;
    try {
      response = await _httpClient
          .post(
            Uri.parse('$_backendBaseUrl/api/checkout/send-money'),
            headers: _authHeaders,
            body: jsonEncode({
              'cardId': cardId,
              'sourceCardId': cardId,
              'beneficiary': beneficiaryName,
              'recipientName': beneficiaryName,
              'recipientPhone': beneficiaryPhone,
              'sourceAmount': sourceAmount,
              'sourceCurrency': sourceCurrency,
              'exchangeRate': exchangeRate,
              'amountBdt': amountBdt,
              'incentiveBdt': incentiveBdt,
              'vatOnCommission': vatOnCommission,
              'usdAmount': usdAmount,
              'destinationAmount': amountBdt + incentiveBdt,
              'destinationCurrency': 'BDT',
              'connectedAccountId':
                  connectedAccountId ?? 'acct_1URCKREQ1XrhmDDe',
            }),
          )
          .timeout(const Duration(seconds: 10));
    } catch (netErr) {
      debugPrint(
        '[SupabasePaymentRepository] Network error connecting to backend: $netErr',
      );
      throw Exception(
        'Payment Gateway Error: Unable to connect to payment server. Please ensure backend service is running.',
      );
    }

    if (response.statusCode != 200 && response.statusCode != 201) {
      String errorMessage = 'Payment Gateway Error (${response.statusCode})';
      try {
        final decoded = jsonDecode(response.body);
        if (decoded is Map && decoded['error'] != null) {
          errorMessage = 'Payment Gateway Error: ${decoded['error']}';
        }
      } catch (_) {}
      throw Exception(errorMessage);
    }

    Map<String, dynamic> data;
    try {
      data = jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {
      throw Exception(
        'Payment Gateway Error: Invalid response from payment server.',
      );
    }

    final String? checkoutUrl =
        data['checkoutUrl']?.toString() ??
        data['transaction']?['checkout_url']?.toString();

    if (checkoutUrl == null ||
        checkoutUrl.trim().isEmpty ||
        (!checkoutUrl.startsWith('http://') &&
            !checkoutUrl.startsWith('https://'))) {
      throw Exception(
        'Payment Gateway Error: Malformed or missing Checkout URL returned by gateway.',
      );
    }

    final txMap = data['transaction'] as Map<String, dynamic>?;
    final String sessionId =
        data['sessionId']?.toString() ??
        txMap?['stripe_payment_id']?.toString() ??
        txMap?['id']?.toString() ??
        'cs_${DateTime.now().millisecondsSinceEpoch}';

    return {
      'id': sessionId,
      'sessionId': sessionId,
      'transactionId': sessionId,
      'title': beneficiaryName,
      'subtitle': 'Remittance to $beneficiaryPhone',
      'amount_bdt': amountBdt,
      'converted_amount': sourceAmount,
      'currency': sourceCurrency,
      'exchange_rate': exchangeRate,
      'incentive_bdt': incentiveBdt,
      'type': 'send',
      'status': 'pending',
      'card_id': cardId,
      'created_at': DateTime.now().toUtc().toIso8601String(),
      'checkoutUrl': checkoutUrl,
      'checkout_url': checkoutUrl,
    };
  }

  @override
  Future<bool> verifyCheckoutSession(String sessionId) async {
    try {
      final response = await _httpClient
          .get(
            Uri.parse(
              '$_backendBaseUrl/api/checkout/session-status/$sessionId',
            ),
          )
          .timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return data['is_paid'] == true ||
            data['payment_status'] == 'paid' ||
            data['status'] == 'complete';
      }
    } catch (e) {
      debugPrint('[SupabasePaymentRepository] verifyCheckoutSession error: $e');
    }
    return false;
  }

  @override
  Future<void> completePaymentRecord({
    required String cardId,
    required String beneficiaryName,
    required String beneficiaryPhone,
    required double sourceAmount,
    required String sourceCurrency,
    required double exchangeRate,
    required double amountBdt,
    required double incentiveBdt,
    required String stripeSessionId,
  }) async {
    final sb = _supabase;
    if (sb != null) {
      try {
        // The backend webhook records the same session when it is running, so
        // skip the insert and the wallet deduction if it already did.
        if (stripeSessionId.isNotEmpty) {
          final existing = await sb
              .from('transactions')
              .select('id')
              .eq('stripe_payment_id', stripeSessionId)
              .limit(1)
              .timeout(const Duration(seconds: 4));
          if (existing.isNotEmpty) {
            debugPrint(
              '[SupabasePaymentRepository] $stripeSessionId already recorded',
            );
            return;
          }
        }

        final currentUserId = sb.auth.currentUser?.id;
        final wallet = await _walletRowFor(sb, cardId);
        final senderPhone = wallet?['phone']?.toString() ?? '+8801700000000';
        final createdAtIso = DateTime.now().toUtc().toIso8601String();
        final shared = <String, dynamic>{
          'sender_id': currentUserId,
          'receiver_id': null,
          'sender_phone': senderPhone,
          'receiver_phone': beneficiaryPhone,
          'exchange_rate': exchangeRate,
          'amount_bdt': amountBdt,
          'status': 'completed',
          'stripe_payment_id': stripeSessionId,
          'transfer_group': stripeSessionId,
          'icon_category': 'person',
          'created_at': createdAtIso,
        };

        // Double entry: what left the sender's card, and what the recipient was
        // credited. History then shows both sides of the same transfer.
        await sb.from('transactions').insert([
          {
            ...shared,
            'direction': 'debit',
            'type': 'send',
            'title': beneficiaryName,
            'subtitle': 'Sent to $beneficiaryPhone',
            'amount': sourceAmount,
            'converted_amount': sourceAmount,
            'currency': sourceCurrency,
            'incentive_bdt': 0,
            'card_id': cardId,
          },
          {
            ...shared,
            'direction': 'credit',
            'type': 'receive',
            'title': beneficiaryName,
            'subtitle': 'Received from your $sourceCurrency card',
            'amount': amountBdt + incentiveBdt,
            'converted_amount': sourceAmount,
            'currency': 'BDT',
            'incentive_bdt': incentiveBdt,
            'card_id': null,
          },
        ]);

        // Deduct the card that actually paid, not whichever row came back first.
        await _adjustWalletBalance(sb, wallet, -amountBdt);
      } catch (e) {
        debugPrint(
          '[SupabasePaymentRepository] completePaymentRecord error: $e',
        );
      }
    }
  }

  @override
  Future<Map<String, dynamic>> executeCardTransfer({
    required String fromCardId,
    required String toCardId,
    required double amountBdt,
    required double vatOnCommission,
    required double usdAmount,
  }) async {
    http.Response response;
    try {
      response = await _httpClient
          .post(
            Uri.parse('$_backendBaseUrl/api/checkout/card-transfer'),
            headers: _authHeaders,
            body: jsonEncode({
              'fromCardId': fromCardId,
              'toCardId': toCardId,
              'amountBdt': amountBdt,
              'vatOnCommission': vatOnCommission,
              'usdAmount': usdAmount,
            }),
          )
          .timeout(const Duration(seconds: 10));
    } catch (netErr) {
      debugPrint(
        '[SupabasePaymentRepository] card transfer network error: $netErr',
      );
      throw Exception(
        'Payment Gateway Error: Unable to connect to payment server. Please ensure backend service is running.',
      );
    }

    if (response.statusCode != 200 && response.statusCode != 201) {
      String errorMessage = 'Payment Gateway Error (${response.statusCode})';
      try {
        final decoded = jsonDecode(response.body);
        if (decoded is Map && decoded['error'] != null) {
          errorMessage = 'Payment Gateway Error: ${decoded['error']}';
        }
      } catch (_) {}
      throw Exception(errorMessage);
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final checkoutUrl = data['checkoutUrl']?.toString() ?? '';
    if (checkoutUrl.isEmpty ||
        (!checkoutUrl.startsWith('http://') &&
            !checkoutUrl.startsWith('https://'))) {
      throw Exception(
        'Payment Gateway Error: Malformed or missing Checkout URL returned by gateway.',
      );
    }
    return data;
  }

  @override
  Future<bool> executeInterCardTransfer({
    required String fromCardId,
    required String toCardId,
    required double amount,
  }) async {
    final sb = _supabase;
    if (sb != null) {
      try {
        final from = await _walletRowFor(sb, fromCardId);
        final to = await _walletRowFor(sb, toCardId);

        // Both sides move. Previously only the WPS row was touched, so a
        // transfer between the other two cards changed the wrong balance.
        await _adjustWalletBalance(sb, from, -amount);
        await _adjustWalletBalance(sb, to, amount);

        final userId = sb.auth.currentUser?.id;
        final createdAtIso = DateTime.now().toUtc().toIso8601String();
        final stamp = DateTime.now().millisecondsSinceEpoch;
        final group = '${fromCardId}_${toCardId}_$stamp';
        final fromTitle = from?['title']?.toString() ?? fromCardId;
        final toTitle = to?['title']?.toString() ?? toCardId;
        final shared = <String, dynamic>{
          'sender_id': userId,
          'sender_phone': from?['phone']?.toString() ?? '+8801700000000',
          'receiver_phone': to?['phone']?.toString() ?? '+8801700000000',
          'amount_bdt': amount,
          'converted_amount': amount,
          'currency': 'BDT',
          'status': 'completed',
          'icon_category': 'transfer',
          'transfer_group': group,
          'created_at': createdAtIso,
        };

        await sb.from('transactions').insert([
          {
            ...shared,
            'direction': 'debit',
            'type': 'transfer',
            'title': toTitle,
            'subtitle': 'Transfer to $toTitle',
            'amount': amount,
            'card_id': fromCardId,
          },
          {
            ...shared,
            'direction': 'credit',
            'type': 'receive',
            'title': fromTitle,
            'subtitle': 'Transfer from $fromTitle',
            'amount': amount,
            'card_id': toCardId,
          },
        ]);
      } catch (e) {
        debugPrint(
          '[SupabasePaymentRepository] executeInterCardTransfer error fallback: $e',
        );
      }
    }

    return _fallbackRepository.executeInterCardTransfer(
      fromCardId: fromCardId,
      toCardId: toCardId,
      amount: amount,
    );
  }

  /// The wallet row backing [cardId]. Falls back to the single legacy row for
  /// databases created before wallets had one row per card.
  Future<Map<String, dynamic>?> _walletRowFor(
    SupabaseClient sb,
    String cardId,
  ) async {
    try {
      final rows = await sb
          .from('wallets')
          .select()
          .timeout(const Duration(seconds: 4));
      if (rows.isEmpty) return null;
      for (final row in rows) {
        if (row['card_id']?.toString() == cardId) return row;
      }
      final hasCardIds = rows.any((r) => r['card_id'] != null);
      return hasCardIds ? null : rows.first;
    } catch (e) {
      debugPrint('[SupabasePaymentRepository] wallet lookup failed: $e');
      return null;
    }
  }

  /// Adds [delta] to that wallet row's balance, never below zero.
  Future<void> _adjustWalletBalance(
    SupabaseClient sb,
    Map<String, dynamic>? wallet,
    double delta,
  ) async {
    if (wallet == null) return;
    final raw = wallet['balance_bdt'];
    final current = raw is num
        ? raw.toDouble()
        : (double.tryParse(raw?.toString() ?? '') ?? 0.0);
    final updated = (current + delta).clamp(0.0, double.infinity);
    try {
      await sb
          .from('wallets')
          .update({'balance_bdt': updated})
          .eq('id', wallet['id'])
          .timeout(const Duration(seconds: 4));
    } catch (e) {
      debugPrint('[SupabasePaymentRepository] balance update failed: $e');
    }
  }

  static Map<String, String> _resolveCountryInfo(String code) {
    switch (code.toUpperCase()) {
      case 'SA':
        return {
          'flag': '🇸🇦',
          'name': 'Saudi Arabia',
          'dialCode': '+966',
          'currency': 'SAR',
          'symbol': '﷼',
        };
      case 'AE':
        return {
          'flag': '🇦🇪',
          'name': 'United Arab Emirates',
          'dialCode': '+971',
          'currency': 'AED',
          'symbol': 'د.إ',
        };
      case 'QA':
        return {
          'flag': '🇶🇦',
          'name': 'Qatar',
          'dialCode': '+974',
          'currency': 'QAR',
          'symbol': 'ر.ق',
        };
      case 'MY':
        return {
          'flag': '🇲🇾',
          'name': 'Malaysia',
          'dialCode': '+60',
          'currency': 'MYR',
          'symbol': 'RM',
        };
      case 'US':
        return {
          'flag': '🇺🇸',
          'name': 'United States',
          'dialCode': '+1',
          'currency': 'USD',
          'symbol': '\$',
        };
      case 'BD':
      default:
        return {
          'flag': '🇧🇩',
          'name': 'Bangladesh',
          'dialCode': '+880',
          'currency': 'BDT',
          'symbol': '৳',
        };
    }
  }

  @override
  Future<String> getWalletHolderName() async {
    final sb = _supabase;
    // 1. Once Google Sign-In or Mobile OTP Auth is connected later, bind full_name dynamically
    if (sb != null) {
      try {
        final currentUser = sb.auth.currentUser;
        if (currentUser != null) {
          final metadata = currentUser.userMetadata;
          final dynamic authFullName =
              metadata?['full_name'] ?? metadata?['name'];
          if (authFullName != null &&
              authFullName.toString().trim().isNotEmpty) {
            return authFullName.toString().trim();
          }
        }
      } catch (e) {
        debugPrint(
          '[SupabasePaymentRepository] getWalletHolderName auth notice: $e',
        );
      }

      // 2. Fetch live full_name from Supabase wallets record
      try {
        final records = await sb
            .from('wallets')
            .select('full_name')
            .timeout(const Duration(seconds: 4));

        if (records.isNotEmpty) {
          final dbName = records.first['full_name']?.toString().trim();
          if (dbName != null && dbName.isNotEmpty && dbName != 'Talha Tanzim') {
            return dbName;
          }
        }
      } catch (e) {
        debugPrint(
          '[SupabasePaymentRepository] getWalletHolderName db notice: $e',
        );
      }
    }

    // 3. Default neutral role title fallback when unauthenticated
    return 'Probashi Expatriate Worker';
  }

  @override
  Future<Map<String, double>?> fetchExchangeRates() async {
    try {
      final response = await _httpClient
          .get(Uri.parse('$_backendBaseUrl/api/rates'))
          .timeout(const Duration(seconds: 4));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final ratesMap = data['rates'] as Map<String, dynamic>?;
        if (ratesMap != null) {
          return ratesMap.map(
            (key, value) =>
                MapEntry(key.toUpperCase(), (value as num).toDouble()),
          );
        }
      }
    } catch (e) {
      debugPrint('[SupabasePaymentRepository] fetchExchangeRates fallback: $e');
    }
    return _fallbackRepository.fetchExchangeRates();
  }
}
