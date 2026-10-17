import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:probashi_guard/frontend/payment/controllers/payment_controller.dart';
import 'package:probashi_guard/frontend/payment/repository/supabase_payment_repository.dart';

void main() {
  group('SupabasePaymentRepository and PaymentController integration', () {
    late PaymentController controller;
    late SupabasePaymentRepository repository;

    setUp(() {
      repository = SupabasePaymentRepository();
      controller = PaymentController.instance;
    });

    test('Loads card balance 98420.12 directly into WPS Payroll card', () async {
      final cards = await repository.getCards();
      expect(cards.isNotEmpty, true);
      final wpsCard = cards.firstWhere((c) => c.id == 'card_wps');
      expect(wpsCard.balance, 98420.12);
      expect(wpsCard.currency, 'BDT');
    });

    test('Beneficiaries query returns active remittance contacts', () async {
      final beneficiaries = await repository.getBeneficiaries();
      expect(beneficiaries.isNotEmpty, true);
      expect(beneficiaries.any((b) => b.name == 'Elizabeth'), true);
    });

    test('Transactions query returns recent ledger entries', () async {
      final txs = await repository.getTransactions();
      expect(txs.isNotEmpty, true);
    });

    test('executeSendMoney throws Payment Gateway Error when backend returns error', () async {
      final mockClient = MockClient((request) async {
        return http.Response(jsonEncode({'error': 'Stripe card declined'}), 500);
      });
      final repo = SupabasePaymentRepository(httpClient: mockClient);
      expect(
        () => repo.executeSendMoney(
          cardId: 'card_wps',
          beneficiary: 'Elizabeth',
          sourceAmount: 100.0,
          sourceCurrency: 'SAR',
          exchangeRate: 31.85,
          amountBdt: 3185.0,
          incentiveBdt: 79.625,
        ),
        throwsA(predicate((e) => e.toString().contains('Payment Gateway Error'))),
      );
    });

    test('executeSendMoney throws Payment Gateway Error on malformed checkoutUrl', () async {
      final mockClient = MockClient((request) async {
        return http.Response(jsonEncode({'success': true, 'checkoutUrl': ''}), 201);
      });
      final repo = SupabasePaymentRepository(httpClient: mockClient);
      expect(
        () => repo.executeSendMoney(
          cardId: 'card_wps',
          beneficiary: 'Elizabeth',
          sourceAmount: 100.0,
          sourceCurrency: 'SAR',
          exchangeRate: 31.85,
          amountBdt: 3185.0,
          incentiveBdt: 79.625,
        ),
        throwsA(predicate((e) => e.toString().contains('Payment Gateway Error'))),
      );
    });

    test('executeSendMoney succeeds with checkoutUrl and does not fallback to mock', () async {
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'success': true,
            'checkoutUrl': 'https://checkout.stripe.com/c/pay/cs_test_mock',
            'sessionId': 'cs_test_mock',
          }),
          201,
        );
      });
      final repo = SupabasePaymentRepository(httpClient: mockClient);
      final res = await repo.executeSendMoney(
        cardId: 'card_wps',
        beneficiary: 'Elizabeth',
        sourceAmount: 100.0,
        sourceCurrency: 'SAR',
        exchangeRate: 31.85,
        amountBdt: 3185.0,
        incentiveBdt: 79.625,
      );

      expect(res['checkoutUrl'], 'https://checkout.stripe.com/c/pay/cs_test_mock');
      expect(res['title'], 'Elizabeth');
      expect(res['amount_bdt'], 3185.0);
      expect(res['converted_amount'], 100.0);
      expect(res['currency'], 'SAR');
      expect(res['exchange_rate'], 31.85);
    });

    test('PaymentController state flags and card cycling remain intact', () {
      expect(controller.isBalanceVisible, false);
      expect(controller.activeCardIndex, 0);

      controller.cycleCardToFront();
      expect(controller.activeCardIndex, 1);

      controller.setActiveCardIndex(0);
      expect(controller.activeCardIndex, 0);

      controller.toggleBalanceVisibility();
      expect(controller.isBalanceVisible, true);
      controller.toggleBalanceVisibility();
      expect(controller.isBalanceVisible, false);
    });

    test('PaymentController unmasked balance formats correctly', () {
      final unmasked = controller.unmaskedActiveBalance;
      expect(unmasked.contains('৳') || unmasked.contains('98,420.12'), true);
    });

    test('getWalletHolderName returns neutral role title Probashi Expatriate Worker', () async {
      final name = await repository.getWalletHolderName();
      expect(name, 'Probashi Expatriate Worker');
      expect(controller.walletHolderName, 'Probashi Expatriate Worker');
    });
  });
}
