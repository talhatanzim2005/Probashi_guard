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
  })  : _backendBaseUrl = backendBaseUrl ?? _defaultBaseUrl,
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
          final firstRecord = records.first;
          final dynamic rawBalance = firstRecord['balance_bdt'];
          final double liveBalance = rawBalance is num
              ? rawBalance.toDouble()
              : (double.tryParse(rawBalance?.toString() ?? '') ?? 98420.12);

          final baseCards = await _fallbackRepository.getCards();
          return baseCards.map((card) {
            if (card.id == 'card_wps') {
              return card.copyWith(balance: liveBalance);
            }
            return card;
          }).toList();
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
              phoneOrAccount: record['phone_number']?.toString() ??
                  record['phone_or_account']?.toString() ??
                  '',
              providerType: record['provider']?.toString() ??
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
        debugPrint('[SupabasePaymentRepository] getBeneficiaries offline fallback: $e');
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

            final rawAmount = record['amount'] ?? record['amount_bdt'] ?? record['converted_amount'];
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
              id: record['id']?.toString() ??
                  'tx_${timestamp.millisecondsSinceEpoch}',
              title: record['title']?.toString() ??
                  record['receiver_phone']?.toString() ??
                  'Remittance Recipient',
              subtitle: record['subtitle']?.toString() ??
                  'Remittance to ${record['receiver_phone'] ?? 'Verified Account'}',
              amount: amount,
              amountBdt: amountBdt,
              convertedAmount: convertedAmount,
              currency: record['currency']?.toString() ?? 'BDT',
              timestamp: timestamp,
              type: type,
              cardId: record['card_id']?.toString() ?? 'card_wps',
              avatarUrl: record['avatar_url']?.toString(),
              iconCategory: record['icon_category']?.toString() ??
                  (type == TransactionType.receive ? 'person' : 'send'),
            );
          }).toList();
        }
      } catch (e) {
        debugPrint('[SupabasePaymentRepository] getTransactions offline fallback: $e');
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
    String? connectedAccountId,
  }) async {
    final String beneficiaryName = beneficiary is BeneficiaryModel
        ? beneficiary.name
        : (beneficiary is Map ? (beneficiary['name']?.toString() ?? '') : beneficiary.toString());
    final String beneficiaryPhone = beneficiary is BeneficiaryModel
        ? beneficiary.phoneOrAccount
        : (beneficiary is Map
            ? (beneficiary['phone'] ?? beneficiary['phone_number'] ?? beneficiary['phoneOrAccount'] ?? '+8801700000000').toString()
            : '+8801700000000');

    // Make live POST request to backend remittance endpoint
    http.Response response;
    try {
      response = await _httpClient
          .post(
            Uri.parse('$_backendBaseUrl/api/checkout/send-money'),
            headers: {'Content-Type': 'application/json'},
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
              'destinationAmount': amountBdt + incentiveBdt,
              'destinationCurrency': 'BDT',
              'connectedAccountId': connectedAccountId ?? 'acct_1URCKREQ1XrhmDDe',
            }),
          )
          .timeout(const Duration(seconds: 10));
    } catch (netErr) {
      debugPrint('[SupabasePaymentRepository] Network error connecting to backend: $netErr');
      throw Exception('Payment Gateway Error: Unable to connect to payment server. Please ensure backend service is running.');
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
      throw Exception('Payment Gateway Error: Invalid response from payment server.');
    }

    final String? checkoutUrl = data['checkoutUrl']?.toString() ??
        data['transaction']?['checkout_url']?.toString();

    if (checkoutUrl == null ||
        checkoutUrl.trim().isEmpty ||
        (!checkoutUrl.startsWith('http://') && !checkoutUrl.startsWith('https://'))) {
      throw Exception('Payment Gateway Error: Malformed or missing Checkout URL returned by gateway.');
    }

    final txMap = data['transaction'] as Map<String, dynamic>?;
    final String sessionId = data['sessionId']?.toString() ??
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
          .get(Uri.parse('$_backendBaseUrl/api/checkout/session-status/$sessionId'))
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
            debugPrint('[SupabasePaymentRepository] $stripeSessionId already recorded');
            return;
          }
        }

        final currentUserId = sb.auth.currentUser?.id;
        String? currentWalletPhone;
        double currentBalance = 98420.12;
        dynamic walletRowId;

        final walletRecords = await sb
            .from('wallets')
            .select()
            .timeout(const Duration(seconds: 4));

        if (walletRecords.isNotEmpty) {
          final firstWallet = walletRecords.first;
          walletRowId = firstWallet['id'];
          currentWalletPhone = firstWallet['phone']?.toString();
          final rawBalance = firstWallet['balance_bdt'];
          currentBalance = rawBalance is num
              ? rawBalance.toDouble()
              : (double.tryParse(rawBalance?.toString() ?? '') ?? 98420.12);
        }

        final senderPhone = currentWalletPhone ?? '+8801700000000';
        final createdAtIso = DateTime.now().toUtc().toIso8601String();

        final transactionData = {
          'sender_id': currentUserId,
          'receiver_id': null,
          'sender_phone': senderPhone,
          'receiver_phone': beneficiaryPhone,
          'title': beneficiaryName,
          'subtitle': 'Remittance to $beneficiaryPhone',
          'amount_bdt': amountBdt,
          'converted_amount': sourceAmount,
          'currency': sourceCurrency,
          'exchange_rate': exchangeRate,
          'incentive_bdt': incentiveBdt,
          'type': 'send',
          'status': 'completed',
          'card_id': cardId,
          'icon_category': 'person',
          'stripe_payment_id': stripeSessionId,
          'created_at': createdAtIso,
        };

        await sb.from('transactions').insert(transactionData);

        final newBalance = (currentBalance - amountBdt).clamp(0.0, double.infinity);
        if (currentWalletPhone != null) {
          await sb
              .from('wallets')
              .update({'balance_bdt': newBalance})
              .eq('phone', currentWalletPhone);
        } else if (walletRowId != null) {
          await sb
              .from('wallets')
              .update({'balance_bdt': newBalance})
              .eq('id', walletRowId);
        }
      } catch (e) {
        debugPrint('[SupabasePaymentRepository] completePaymentRecord error: $e');
      }
    }
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
        final walletRecords = await sb
            .from('wallets')
            .select()
            .timeout(const Duration(seconds: 4));

        if (walletRecords.isNotEmpty) {
          final firstWallet = walletRecords.first;
          final currentBalance = (firstWallet['balance_bdt'] as num?)?.toDouble() ??
              double.tryParse(firstWallet['balance_bdt']?.toString() ?? '') ??
              98420.12;

          if (fromCardId == 'card_wps') {
            final updated = (currentBalance - amount).clamp(0.0, double.infinity);
            await sb
                .from('wallets')
                .update({'balance_bdt': updated})
                .eq('id', firstWallet['id'])
                .timeout(const Duration(seconds: 4));
          } else if (toCardId == 'card_wps') {
            final updated = currentBalance + amount;
            await sb
                .from('wallets')
                .update({'balance_bdt': updated})
                .eq('id', firstWallet['id'])
                .timeout(const Duration(seconds: 4));
          }

          await sb.from('transactions').insert({
            'sender_phone': '+8801700000000',
            'receiver_phone': '+8801700000000',
            'title': 'Inter-Card Swap',
            'subtitle': '$fromCardId → $toCardId',
            'amount_bdt': amount,
            'converted_amount': amount,
            'currency': 'BDT',
            'type': 'transfer',
            'status': 'completed',
            'card_id': fromCardId,
            'icon_category': 'transfer',
          }).timeout(const Duration(seconds: 4));
        }
      } catch (e) {
        debugPrint('[SupabasePaymentRepository] executeInterCardTransfer error fallback: $e');
      }
    }

    return _fallbackRepository.executeInterCardTransfer(
      fromCardId: fromCardId,
      toCardId: toCardId,
      amount: amount,
    );
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
        debugPrint('[SupabasePaymentRepository] getWalletHolderName auth notice: $e');
      }

      // 2. Fetch live full_name from Supabase wallets record
      try {
        final records = await sb
            .from('wallets')
            .select('full_name')
            .timeout(const Duration(seconds: 4));

        if (records.isNotEmpty) {
          final dbName = records.first['full_name']?.toString().trim();
          if (dbName != null &&
              dbName.isNotEmpty &&
              dbName != 'Talha Tanzim') {
            return dbName;
          }
        }
      } catch (e) {
        debugPrint('[SupabasePaymentRepository] getWalletHolderName db notice: $e');
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
          return ratesMap.map((key, value) =>
              MapEntry(key.toUpperCase(), (value as num).toDouble()));
        }
      }
    } catch (e) {
      debugPrint('[SupabasePaymentRepository] fetchExchangeRates fallback: $e');
    }
    return _fallbackRepository.fetchExchangeRates();
  }
}
