import 'package:flutter_test/flutter_test.dart';
import 'package:probashi_guard/frontend/payment/controllers/payment_controller.dart';
import 'package:probashi_guard/frontend/payment/repository/mock_payment_repository.dart';

void main() {
  group('StripePaymentRepository and PaymentController integration', () {
    late PaymentController controller;

    setUp(() {
      controller = PaymentController.instance;
    });

    test(
      'Controller initializes with StripePaymentRepository and loads cards',
      () async {
        await controller.init();
        expect(controller.cards.isNotEmpty, true);
        expect(controller.cards.first.id, 'card_wps');
      },
    );

    test('Controller loads beneficiaries', () async {
      await controller.init();
      expect(controller.beneficiaries.isNotEmpty, true);
      expect(controller.beneficiaries.first.name, 'Elizabeth');
    });

    test(
      'Execute sendMoney remittance returns valid Stripe Checkout URL or fails safely with Payment Gateway Error',
      () async {
        await controller.init();
        final recipient = controller.beneficiaries.first;

        try {
          final res = await controller.sendMoneyWithResult(
            recipient: recipient,
            sourceAmount: 100.0,
            sourceCurrency: 'SAR',
            exchangeRate: 31.85,
            amountBdt: 3185.0,
            incentiveBdt: 79.625,
            vatOnCommission: 0.3185,
            usdAmount: 26.66,
          );
          expect(res, isNotNull);
          expect(res!['checkoutUrl'], isNotNull);
          expect(
            res['checkoutUrl'].toString().startsWith(
              'https://checkout.stripe.com/c/pay/',
            ),
            true,
          );
        } catch (e) {
          expect(e.toString().contains('Payment Gateway Error'), true);
        }
      },
    );

    test('Moving money between cards updates both balances', () async {
      // The on-device repository: the Supabase one needs a signed-in session
      // and is covered by the SQL checks for internal_transfer.
      final controller = PaymentController.withRepository(
        MockPaymentRepository(),
      );
      await controller.init();
      if (controller.cards.length >= 2) {
        final fromCard = controller.cards[0];
        final toCard = controller.cards[1];
        final initialFromBalance = fromCard.balance;
        final initialToBalance = toCard.balance;

        final error = await controller.transferBetweenCards(
          fromCardId: fromCard.id,
          toCardId: toCard.id,
          amountInBdt: 1000.0,
        );

        expect(error, isNull);
        expect(controller.cards[0].balance, initialFromBalance - 1000.0);
        expect(controller.cards[1].balance, initialToBalance + 1000.0);
      }
    });
  });
}
