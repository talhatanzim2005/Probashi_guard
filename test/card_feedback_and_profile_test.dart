import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:probashi_guard/frontend/payment/controllers/payment_controller.dart';
import 'package:probashi_guard/frontend/payment/repository/mock_payment_repository.dart';
import 'package:probashi_guard/frontend/payment/repository/payment_local_store.dart';
import 'package:probashi_guard/frontend/payment/widgets/payment_card_deck.dart';
import 'package:probashi_guard/frontend/profile/controllers/profile_controller.dart';
import 'package:probashi_guard/frontend/profile/profile_view.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    PaymentLocalStore.resetForTesting();
  });

  group('demo wallet balances', () {
    const expected = {
      'card_wps': 50000.0,
      'card_probashi': 25000.0,
      'card_visa': 10000.0,
    };

    test('the offline cards hold 50,000 / 25,000 / 10,000', () async {
      final cards = await MockPaymentRepository().getCards();
      expect({for (final c in cards) c.id: c.balance}, expected);
    });

    test('the cards shown before an account loads hold the same', () {
      final controller = PaymentController.withRepository(
        MockPaymentRepository(),
      );
      expect({for (final c in controller.cards) c.id: c.balance}, expected);
    });
  });

  group('payment cards react to a tap', () {
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

    testWidgets('each card in the deck has a tap effect', (tester) async {
      await pumpDeck(tester);
      final inks = find.descendant(
        of: find.byType(PaymentCardDeck),
        matching: find.byType(InkWell),
      );
      expect(inks, findsNWidgets(3));
      for (final ink in tester.widgetList<InkWell>(inks)) {
        expect(ink.onTap, isNotNull, reason: 'an InkWell without onTap is dead');
      }
    });

    testWidgets('pressing the front card draws a ripple over its colour', (
      tester,
    ) async {
      await pumpDeck(tester);
      final deck = tester.getTopLeft(find.byType(PaymentCardDeck));

      // The empty left margin of the front card: no balance or eye control
      // there to take the tap.
      final press = await tester.startGesture(deck + const Offset(8, 130));
      await tester.pump(const Duration(milliseconds: 150));

      // The ripple is painted on the Material around the front card.
      final materials = find.descendant(
        of: find.byType(PaymentCardDeck),
        matching: find.byType(Material),
      );
      final front = tester.renderObject<RenderBox>(materials.last);
      expect(front, paints..circle());

      await press.up();
      await tester.pumpAndSettle();
    });

    testWidgets('tapping the front card does not change the active card', (
      tester,
    ) async {
      await pumpDeck(tester);
      final start = controller.activeCardIndex;
      final deck = tester.getTopLeft(find.byType(PaymentCardDeck));

      await tester.tapAt(deck + const Offset(8, 130));
      await tester.pumpAndSettle();

      expect(controller.activeCardIndex, start);
    });
  });

  group('profile header leads to Update Phone Number', () {
    Future<List<ProfileAction>> pumpProfile(WidgetTester tester) async {
      final actions = <ProfileAction>[];
      await tester.pumpWidget(
        MaterialApp(
          home: ProfileView(
            controller: ProfileController.instance,
            onAction: actions.add,
          ),
        ),
      );
      return actions;
    }

    testWidgets('the Edit button', (tester) async {
      final actions = await pumpProfile(tester);
      await tester.tap(find.text('Edit'));
      await tester.pump();
      expect(actions, [ProfileAction.updatePhone]);
    });

    testWidgets('the name', (tester) async {
      final actions = await pumpProfile(tester);
      await tester.tap(find.text(ProfileController.instance.userName));
      await tester.pump();
      expect(actions, [ProfileAction.updatePhone]);
    });

    testWidgets('the phone number at the top', (tester) async {
      final actions = await pumpProfile(tester);
      await tester.tap(find.text(ProfileController.instance.phoneNumber).first);
      await tester.pump();
      expect(actions, [ProfileAction.updatePhone]);
    });

    testWidgets('the Update Phone Number row still does the same', (
      tester,
    ) async {
      final actions = await pumpProfile(tester);
      final row = find.text('Update Phone Number');
      await tester.scrollUntilVisible(row, 200);
      await tester.tap(row);
      await tester.pump();
      expect(actions, [ProfileAction.updatePhone]);
    });
  });
}
