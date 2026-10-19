import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:probashi_guard/frontend/payment/controllers/payment_controller.dart';
import 'package:probashi_guard/frontend/payment/models/currency_model.dart';
import 'package:probashi_guard/frontend/payment/models/transaction_model.dart';
import 'package:probashi_guard/frontend/payment/repository/mock_payment_repository.dart';
import 'package:probashi_guard/frontend/payment/widgets/payment_card_deck.dart';

void main() {
  group('USD settlement rail', () {
    test('every transfer settles in USD', () {
      expect(CurrencyModel.settlementCurrency, 'USD');
      expect(CurrencyModel.usd.code, 'USD');
    });

    test('a SAR amount converts to the USD the gateway is charged', () {
      final sar = CurrencyModel.supportedCurrencies.firstWhere(
        (c) => c.code == 'SAR',
      );
      // 100 SAR -> 3185 BDT -> 3185 / 119.50 USD
      expect(sar.toUsd(100), closeTo(3185 / 119.50, 1e-9));
    });

    test('USD converts back into the recipient local currency', () {
      final bdt = CurrencyModel.supportedCurrencies.firstWhere(
        (c) => c.code == 'BDT',
      );
      expect(bdt.fromUsd(1), closeTo(119.50, 1e-9));
    });

    test('a round trip through USD preserves the amount', () {
      final aed = CurrencyModel.supportedCurrencies.firstWhere(
        (c) => c.code == 'AED',
      );
      expect(aed.fromUsd(aed.toUsd(250)), closeTo(250, 1e-9));
    });
  });

  group('VAT on commission', () {
    test('is 0.01 percent of the transfer', () {
      expect(CurrencyModel.vatOnCommissionRate, 0.0001);
      expect(CurrencyModel.vatOnCommission(5000), closeTo(0.5, 1e-9));
      expect(CurrencyModel.vatOnCommission(100), closeTo(0.01, 1e-9));
    });

    test('is zero for a zero transfer', () {
      expect(CurrencyModel.vatOnCommission(0), 0);
    });
  });

  group('Transaction history shows both legs', () {
    test('a row carrying both legs reports them separately', () {
      final tx = TransactionModel(
        id: 'tx_1',
        title: 'Tanzim',
        subtitle: 'Remittance',
        amount: 3264.63,
        currency: 'BDT',
        timestamp: DateTime.now(),
        type: TransactionType.send,
        debitedAmount: 100.01,
        debitedCurrency: 'SAR',
        creditedAmount: 3264.63,
        creditedCurrency: 'BDT',
      );

      expect(tx.hasBothLegs, true);
      expect(tx.debitedAmount, 100.01);
      expect(tx.debitedCurrency, 'SAR');
      expect(tx.creditedAmount, 3264.63);
      expect(tx.creditedCurrency, 'BDT');
    });

    test('a stored row falls back to the source and BDT legs', () {
      final tx = TransactionModel.fromMap({
        'id': 'tx_2',
        'title': 'Tanzim',
        'amount': 3264.63,
        'amount_bdt': 3185.0,
        'converted_amount': 100.0,
        'currency': 'SAR',
        'type': 'send',
      });

      expect(tx.hasBothLegs, true);
      expect(tx.debitedAmount, 100.0);
      expect(tx.debitedCurrency, 'SAR');
      expect(tx.creditedAmount, 3185.0);
      expect(tx.creditedCurrency, 'BDT');
    });

    test('a row with only one leg is not treated as cross-border', () {
      final tx = TransactionModel.fromMap({
        'id': 'tx_3',
        'title': 'Netflix',
        'amount': 1500.0,
        'currency': 'BDT',
        'type': 'subscription',
      });

      expect(tx.hasBothLegs, false);
    });
  });

  group('Card deck selects the card that was tapped', () {
    late PaymentController controller;

    setUp(() {
      controller = PaymentController.withRepository(MockPaymentRepository());
    });

    Future<void> pumpDeck(WidgetTester tester) {
      return tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: PaymentCardDeck(controller: controller)),
        ),
      );
    }

    testWidgets('tapping the middle card brings it to the front', (
      tester,
    ) async {
      await pumpDeck(tester);
      final start = controller.activeCardIndex;

      // The middle card peeks between the back card and the front one.
      await tester.tapAt(
        tester.getTopLeft(find.byType(PaymentCardDeck)) + const Offset(100, 34),
      );
      await tester.pump();

      expect(controller.activeCardIndex, (start + 1) % controller.cards.length);
    });

    testWidgets('tapping the back card brings it to the front', (tester) async {
      await pumpDeck(tester);
      final start = controller.activeCardIndex;

      // The back card peeks above the middle one.
      await tester.tapAt(
        tester.getTopLeft(find.byType(PaymentCardDeck)) + const Offset(100, 10),
      );
      await tester.pump();

      expect(controller.activeCardIndex, (start + 2) % controller.cards.length);
    });

    testWidgets('tapping empty space beside the deck changes nothing', (
      tester,
    ) async {
      await pumpDeck(tester);
      final start = controller.activeCardIndex;

      // Below the deck entirely: nothing there should switch cards.
      await tester.tapAt(
        tester.getBottomLeft(find.byType(PaymentCardDeck)) +
            const Offset(100, 40),
      );
      await tester.pump();

      expect(controller.activeCardIndex, start);
    });
  });
}
