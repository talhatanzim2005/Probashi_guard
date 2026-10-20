import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:probashi_guard/frontend/payment/controllers/payment_controller.dart';
import 'package:probashi_guard/frontend/payment/flows/send_amount_step.dart';
import 'package:probashi_guard/frontend/payment/models/beneficiary_model.dart';
import 'package:probashi_guard/frontend/payment/models/wallet_card_model.dart';
import 'package:probashi_guard/frontend/payment/repository/mock_payment_repository.dart';
import 'package:probashi_guard/frontend/payment/widgets/amount_numpad.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// TC-SEND-AMOUNT: the second step of the send flow — what the figures are,
/// and when "Review Transfer Details" refuses to go on.
const _bangladesh = BeneficiaryModel(
  id: 'bd',
  name: 'Rahim',
  phoneOrAccount: '+8801900000114',
  providerType: 'bKash',
  avatarUrl: '',
  initials: 'RA',
);
const _saudi = BeneficiaryModel(
  id: 'sa',
  name: 'William',
  phoneOrAccount: '+966551234567',
  providerType: 'STC Pay',
  avatarUrl: '',
  initials: 'WI',
  countryCode: 'SA',
  countryName: 'Saudi Arabia',
  countryDialCode: '+966',
  currency: 'SAR',
  currencySymbol: '﷼',
);

class _Proceeded {
  WalletCardModel? card;
  double? sourceAmount;
  String? sourceCurrency;
  double? destinationAmount;
  double? amountBdt;
  double? incentiveBdt;
  double? vat;
  double? usd;
  int count = 0;
}

PaymentController _controllerWithBalance(double wps) {
  final c = PaymentController.withRepository(MockPaymentRepository());
  // The deck's first card is the one a send is charged to.
  c.cards[0] = c.cards[0].copyWith(balance: wps);
  return c;
}

Future<_Proceeded> _pump(
  WidgetTester tester, {
  required PaymentController controller,
  BeneficiaryModel recipient = _bangladesh,
}) async {
  final out = _Proceeded();
  await tester.binding.setSurfaceSize(const Size(420, 1600));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SendAmountStep(
          recipient: recipient,
          controller: controller,
          onProceed: ({
            required sourceCard,
            required sourceAmount,
            required sourceCurrency,
            required destinationAmount,
            required destinationCurrency,
            required exchangeRate,
            required amountBdt,
            required incentiveBdt,
            required vatOnCommission,
            required usdAmount,
          }) {
            out
              ..count += 1
              ..card = sourceCard
              ..sourceAmount = sourceAmount
              ..sourceCurrency = sourceCurrency
              ..destinationAmount = destinationAmount
              ..amountBdt = amountBdt
              ..incentiveBdt = incentiveBdt
              ..vat = vatOnCommission
              ..usd = usdAmount;
          },
        ),
      ),
    ),
  );
  await tester.pump();
  return out;
}

Future<void> _review(WidgetTester tester) async {
  final button = find.text('Review Transfer Details');
  await tester.ensureVisible(button);
  await tester.tap(button);
  await tester.pump();
}

Future<void> _typeAmount(WidgetTester tester, String digits) async {
  // Scoped to the keypad: the amount shown above it contains the same digits.
  Finder key(String d) => find.descendant(of: find.byType(AmountNumpad), matching: find.text(d));
  await tester.tap(find.byIcon(Icons.clear_rounded));
  for (final d in digits.split('')) {
    await tester.tap(key(d));
  }
  await tester.pump();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('a Bangladeshi recipient gets the 2.5% incentive on top; VAT and the USD charge follow', (tester) async {
    final out = await _pump(tester, controller: _controllerWithBalance(50000));
    await _typeAmount(tester, '1000');
    await _review(tester);

    expect(out.count, 1);
    expect(out.sourceCurrency, 'BDT');
    expect(out.sourceAmount, 1000);
    expect(out.amountBdt, 1000);
    expect(out.incentiveBdt, closeTo(25, 1e-9));
    expect(out.destinationAmount, closeTo(1025, 1e-9));
    expect(out.vat, closeTo(0.1, 1e-9));
    expect(out.usd, closeTo(1000.1 / 119.5, 1e-9));
    expect(out.card!.id, 'card_wps');
  });

  testWidgets('a recipient outside Bangladesh gets no incentive, and is paid in their own currency', (tester) async {
    final out = await _pump(tester, controller: _controllerWithBalance(50000), recipient: _saudi);
    await _typeAmount(tester, '3185');
    await _review(tester);

    expect(out.incentiveBdt, 0);
    expect(out.destinationAmount, closeTo(3185 / 31.85, 1e-9), reason: '100 SAR');
  });

  testWidgets('the quick-add chips add to what is typed', (tester) async {
    final out = await _pump(tester, controller: _controllerWithBalance(50000));
    await _typeAmount(tester, '100');
    await tester.tap(find.text('+৳500'));
    await tester.pump();
    await _review(tester);
    expect(out.sourceAmount, 600);
  });

  testWidgets('a zero amount is refused with a message, and nothing proceeds', (tester) async {
    final out = await _pump(tester, controller: _controllerWithBalance(50000));
    await _typeAmount(tester, '0');
    await _review(tester);
    expect(out.count, 0);
    expect(find.text('Please enter an amount greater than 0'), findsOneWidget);
  });

  testWidgets('an amount over the card balance is refused', (tester) async {
    final out = await _pump(tester, controller: _controllerWithBalance(500));
    await _typeAmount(tester, '501');
    await _review(tester);
    expect(out.count, 0);
    expect(find.text('Entered amount exceeds your available card balance'), findsOneWidget);
  });

  // 100 + 0.01% VAT = 100.01 leaves the card.
  testWidgets('the VAT counts: sending exactly the balance is refused', (tester) async {
    final out = await _pump(tester, controller: _controllerWithBalance(100));
    await _typeAmount(tester, '100');
    await _review(tester);
    expect(out.count, 0, reason: '100.00 cannot cover 100.01');
  });

  testWidgets('the VAT counts: a balance that covers amount + VAT is accepted', (tester) async {
    final out = await _pump(tester, controller: _controllerWithBalance(100.01));
    await _typeAmount(tester, '100');
    await _review(tester);
    expect(out.count, 1);
  });

  testWidgets('SEC-29 (pinned): a brand-new account with 0.00 on every card cannot start a send', (tester) async {
    // Stripe would charge the person's own bank card on its hosted page, and the
    // wallet is never debited by a remittance (settle_remittance leaves the
    // balance unchanged) - yet the form insists the WALLET covers the amount.
    final out = await _pump(tester, controller: _controllerWithBalance(0));
    await _typeAmount(tester, '100');
    await _review(tester);
    expect(out.count, 0);
    expect(find.text('Entered amount exceeds your available card balance'), findsOneWidget);
  });
}
