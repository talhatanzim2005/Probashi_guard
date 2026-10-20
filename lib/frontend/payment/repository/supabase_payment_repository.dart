import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../config/backend_config.dart';
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

  static String get _defaultBaseUrl => BackendConfig.baseUrl;

  /// One ledger wallet per card. The server owns the balances; this only reads
  /// them (RLS lets a signed-in person select their own rows), and lays them over
  /// the card artwork and titles, which are display metadata.
  @override
  Future<List<WalletCardModel>> getCards() async {
    final sb = _supabase;
    if (sb != null && sb.auth.currentUser != null) {
      try {
        var records = await sb
            .from('wallets')
            .select('card_id, balance')
            .timeout(const Duration(seconds: 4));

        // An account from before the card wallets existed: open them, once.
        if (records.length < 3) {
          await sb.rpc('ensure_my_wallet').timeout(const Duration(seconds: 4));
          records = await sb
              .from('wallets')
              .select('card_id, balance')
              .timeout(const Duration(seconds: 4));
        }

        if (records.isNotEmpty) {
          final balances = <String, double>{};
          for (final row in records) {
            final raw = row['balance'];
            final balance = raw is num
                ? raw.toDouble()
                : double.tryParse(raw?.toString() ?? '');
            if (balance != null) balances[row['card_id'].toString()] = balance;
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

  /// The person's own ledger legs, newest first. RLS limits the select to
  /// their rows, so no user filter is needed (or trusted) here.
  @override
  Future<List<TransactionModel>> getTransactions({String? cardId}) async {
    final sb = _supabase;
    if (sb != null && sb.auth.currentUser != null) {
      try {
        var query = sb.from('transactions').select();
        if (cardId != null) {
          query = query.eq('card_id', cardId);
        }
        final records = await query
            .order('created_at', ascending: false)
            .limit(100)
            .timeout(const Duration(seconds: 4));

        if (records.isNotEmpty) {
          return records.map(_transactionFromLedger).toList();
        }
      } catch (e) {
        debugPrint(
          '[SupabasePaymentRepository] getTransactions offline fallback: $e',
        );
      }
    }
    return _fallbackRepository.getTransactions(cardId: cardId);
  }

  /// One ledger leg as a history row.
  ///
  ///   deposit      a card payment arriving          -> received money
  ///   withdrawal   money leaving to a recipient     -> sent money
  ///   transfer     between two of your own cards    -> a transfer (no counterparty)
  ///                to or from another person        -> by direction
  static TransactionModel _transactionFromLedger(Map<String, dynamic> row) {
    final direction = row['direction']?.toString();
    final purpose = row['purpose']?.toString();
    final hasCounterparty =
        row['counterparty_id'] != null ||
        (row['counterparty_phone']?.toString().isNotEmpty ?? false);

    final TransactionType type;
    if (purpose == 'deposit') {
      type = TransactionType.receive;
    } else if (purpose == 'withdrawal') {
      type = TransactionType.send;
    } else if (!hasCounterparty) {
      type = TransactionType.transfer;
    } else {
      type = direction == 'credit'
          ? TransactionType.receive
          : TransactionType.send;
    }

    final raw = row['amount'];
    final amount = raw is num
        ? raw.toDouble()
        : (double.tryParse(raw?.toString() ?? '') ?? 0.0);
    final createdAt =
        DateTime.tryParse(row['created_at']?.toString() ?? '') ??
        DateTime.now();
    final description = row['description']?.toString() ?? '';
    final counterparty = row['counterparty_name']?.toString() ?? '';

    return TransactionModel(
      id: row['id']?.toString() ?? 'tx_${createdAt.millisecondsSinceEpoch}',
      title: counterparty.isNotEmpty
          ? counterparty
          : (description.isNotEmpty ? description : 'Transaction'),
      subtitle: description,
      amount: amount,
      amountBdt: amount,
      currency: row['currency']?.toString() ?? 'BDT',
      timestamp: createdAt,
      type: type,
      status: TransactionModel.parseStatus(row['status']),
      cardId: row['card_id']?.toString() ?? 'card_wps',
      iconCategory: switch (type) {
        TransactionType.receive => 'person',
        TransactionType.transfer => 'transfer',
        _ => 'send',
      },
      transferGroup: row['reference']?.toString(),
    );
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
            headers: _authHeaders,
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

  /// The server books a paid remittance, not the app. The Stripe webhook calls
  /// settle_remittance(), which writes both ledger legs for the session exactly
  /// once; the client has no write access to wallets or transactions. So there is
  /// nothing to record here; the history simply appears once the webhook lands.
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
    debugPrint(
      '[SupabasePaymentRepository] $stripeSessionId is booked by the webhook; '
      'nothing to write from the app',
    );
  }

  /// Moves money between two of the person's own cards through the
  /// internal_transfer RPC: one atomic server-side move, no gateway and no fee.
  /// A fresh idempotency key per attempt means a retried request cannot move the
  /// money twice.
  @override
  Future<bool> executeInterCardTransfer({
    required String fromCardId,
    required String toCardId,
    required double amount,
  }) async {
    final sb = _supabase;
    if (sb == null || sb.auth.currentUser == null) {
      throw Exception('Sign in to move money between your cards.');
    }
    try {
      await sb
          .rpc(
            'internal_transfer',
            params: {
              'p_from_card': fromCardId,
              'p_to_card': toCardId,
              'p_amount': amount,
              'p_idempotency_key':
                  'swap-${DateTime.now().microsecondsSinceEpoch}',
            },
          )
          .timeout(const Duration(seconds: 8));
      return true;
    } on PostgrestException catch (e) {
      // The function's own messages ("That card does not have enough balance")
      // are written to be shown as they are.
      throw Exception(e.message);
    } on TimeoutException {
      throw Exception('The server took too long to answer. Please try again.');
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

      // 2. Fetch the saved full name from the person's profile
      try {
        final records = await sb
            .from('profiles')
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
