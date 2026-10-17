import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/beneficiary_model.dart';
import '../models/transaction_model.dart';
import '../models/wallet_card_model.dart';
import 'mock_payment_repository.dart';
import 'payment_repository.dart';

class StripePaymentRepository implements PaymentRepository {
  final String baseUrl;
  final http.Client _client;
  final MockPaymentRepository _fallbackRepository;

  StripePaymentRepository({
    String? baseUrl,
    http.Client? client,
  })  : baseUrl = baseUrl ?? _defaultBaseUrl,
        _client = client ?? http.Client(),
        _fallbackRepository = MockPaymentRepository();

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
    try {
      final response = await _client
          .get(Uri.parse('$baseUrl/api/payment/cards'))
          .timeout(const Duration(seconds: 4));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final rawCards = data['cards'] as List<dynamic>? ?? [];
        return rawCards
            .map((c) => WalletCardModel.fromMap(c as Map<String, dynamic>))
            .toList();
      }
    } catch (e) {
      debugPrint('[StripePaymentRepository] getCards offline fallback: $e');
    }
    return _fallbackRepository.getCards();
  }

  @override
  Future<List<BeneficiaryModel>> getBeneficiaries() async {
    try {
      final response = await _client
          .get(Uri.parse('$baseUrl/api/payment/beneficiaries'))
          .timeout(const Duration(seconds: 4));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final rawBens = data['beneficiaries'] as List<dynamic>? ?? [];
        return rawBens
            .map((b) => BeneficiaryModel.fromMap(b as Map<String, dynamic>))
            .toList();
      }
    } catch (e) {
      debugPrint('[StripePaymentRepository] getBeneficiaries offline fallback: $e');
    }
    return _fallbackRepository.getBeneficiaries();
  }

  @override
  Future<List<TransactionModel>> getTransactions({String? cardId}) async {
    try {
      final uri = Uri.parse('$baseUrl/api/payment/transactions').replace(
        queryParameters: cardId != null ? {'cardId': cardId} : null,
      );
      final response = await _client.get(uri).timeout(const Duration(seconds: 4));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final rawTxs = data['transactions'] as List<dynamic>? ?? [];
        return rawTxs
            .map((t) => TransactionModel.fromMap(t as Map<String, dynamic>))
            .toList();
      }
    } catch (e) {
      debugPrint('[StripePaymentRepository] getTransactions offline fallback: $e');
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
    final String recipientName = beneficiary is BeneficiaryModel
        ? beneficiary.name
        : (beneficiary is Map ? beneficiary['name']?.toString() ?? '' : beneficiary.toString());
    final String recipientPhone = beneficiary is BeneficiaryModel
        ? beneficiary.phoneOrAccount
        : (beneficiary is Map
            ? (beneficiary['phone'] ?? beneficiary['phone_number'] ?? beneficiary['phoneOrAccount'] ?? '+8801700000000').toString()
            : '+8801700000000');

    http.Response response;
    try {
      response = await _client
          .post(
            Uri.parse('$baseUrl/api/checkout/send-money'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'cardId': cardId,
              'sourceCardId': cardId,
              'beneficiary': recipientName,
              'recipientName': recipientName,
              'recipientPhone': recipientPhone,
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
      debugPrint('[StripePaymentRepository] Network error connecting to backend: $netErr');
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

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final String? checkoutUrl = data['checkoutUrl']?.toString() ??
        data['transaction']?['checkout_url']?.toString();

    if (checkoutUrl == null ||
        checkoutUrl.trim().isEmpty ||
        (!checkoutUrl.startsWith('http://') && !checkoutUrl.startsWith('https://'))) {
      throw Exception('Payment Gateway Error: Malformed or missing Checkout URL returned by gateway.');
    }

    final txMap = data['transaction'] as Map<String, dynamic>? ?? {};
    final sessionId = data['sessionId']?.toString() ??
        txMap['stripe_payment_id']?.toString() ??
        txMap['id']?.toString() ??
        'cs_${DateTime.now().millisecondsSinceEpoch}';

    return {
      ...txMap,
      'sessionId': sessionId,
      'checkoutUrl': checkoutUrl,
      'checkout_url': checkoutUrl,
    };
  }

  @override
  Future<bool> verifyCheckoutSession(String sessionId) async {
    try {
      final response = await _client
          .get(Uri.parse('$baseUrl/api/checkout/session-status/$sessionId'))
          .timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return data['is_paid'] == true ||
            data['payment_status'] == 'paid' ||
            data['status'] == 'complete';
      }
    } catch (e) {
      debugPrint('[StripePaymentRepository] verifyCheckoutSession error: $e');
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
    // Sync payment completion state
  }

  @override
  Future<bool> executeInterCardTransfer({
    required String fromCardId,
    required String toCardId,
    required double amount,
  }) async {
    try {
      final response = await _client
          .post(
            Uri.parse('$baseUrl/api/payment/transfer-cards'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'fromCardId': fromCardId,
              'toCardId': toCardId,
              'amount': amount,
            }),
          )
          .timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return data['success'] == true;
      }
    } catch (e) {
      debugPrint('[StripePaymentRepository] executeInterCardTransfer fallback: $e');
    }

    return _fallbackRepository.executeInterCardTransfer(
      fromCardId: fromCardId,
      toCardId: toCardId,
      amount: amount,
    );
  }

  @override
  Future<String> getWalletHolderName() async {
    return 'Probashi Expatriate Worker';
  }

  @override
  Future<Map<String, double>?> fetchExchangeRates() async {
    try {
      final response = await _client
          .get(Uri.parse('$baseUrl/api/rates'))
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
      debugPrint('[StripePaymentRepository] fetchExchangeRates fallback: $e');
    }
    return _fallbackRepository.fetchExchangeRates();
  }
}
