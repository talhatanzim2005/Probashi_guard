import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:probashi_guard/frontend/payment/controllers/payment_controller.dart';
import 'package:probashi_guard/frontend/payment/repository/mock_payment_repository.dart';
import 'package:probashi_guard/frontend/payment/widgets/amount_numpad.dart';
import 'package:probashi_guard/frontend/payment/widgets/transfer_dialog.dart';

void main() {
  group('AmountNumpad', () {
    late TextEditingController controller;
    late int changes;

    setUp(() {
      controller = TextEditingController();
      changes = 0;
    });

    tearDown(() => controller.dispose());

    Future<void> pumpPad(WidgetTester tester, {int maxDigits = 9}) {
      return tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AmountNumpad(
              controller: controller,
              onChanged: () => changes++,
              maxDigits: maxDigits,
            ),
          ),
        ),
      );
    }

    testWidgets('shows every digit from 0 to 9', (tester) async {
      await pumpPad(tester);
      for (var d = 0; d <= 9; d++) {
        expect(find.text('$d'), findsOneWidget, reason: 'digit $d is missing');
      }
    });

    testWidgets('shows a backspace and a clear key', (tester) async {
      await pumpPad(tester);
      expect(find.byIcon(Icons.backspace_outlined), findsOneWidget);
      expect(find.byIcon(Icons.clear_rounded), findsOneWidget);
    });

    testWidgets('tapping digits builds up the amount', (tester) async {
      await pumpPad(tester);
      await tester.tap(find.text('1'));
      await tester.tap(find.text('2'));
      await tester.tap(find.text('5'));
      await tester.pump();

      expect(controller.text, '125');
      expect(changes, 3);
    });

    testWidgets('a leading zero is replaced, not extended', (tester) async {
      await pumpPad(tester);
      await tester.tap(find.text('0'));
      await tester.tap(find.text('5'));
      await tester.pump();

      expect(controller.text, '5');
    });

    testWidgets('backspace removes the last digit', (tester) async {
      await pumpPad(tester);
      await tester.tap(find.text('4'));
      await tester.tap(find.text('7'));
      await tester.tap(find.byIcon(Icons.backspace_outlined));
      await tester.pump();

      expect(controller.text, '4');
    });

    testWidgets('backspace on an empty amount does nothing', (tester) async {
      await pumpPad(tester);
      await tester.tap(find.byIcon(Icons.backspace_outlined));
      await tester.pump();

      expect(controller.text, '');
      expect(changes, 0);
    });

    testWidgets('clear empties the amount', (tester) async {
      await pumpPad(tester);
      await tester.tap(find.text('9'));
      await tester.tap(find.text('9'));
      await tester.tap(find.byIcon(Icons.clear_rounded));
      await tester.pump();

      expect(controller.text, '');
    });

    testWidgets('stops at maxDigits', (tester) async {
      await pumpPad(tester, maxDigits: 3);
      for (var i = 0; i < 5; i++) {
        await tester.tap(find.text('7'));
      }
      await tester.pump();

      expect(controller.text, '777');
    });
  });

  group('Amount fields are driven only by the numpad', () {
    testWidgets('the transfer dialog shows the numpad and blocks the keyboard', (
      tester,
    ) async {
      // No init(): it awaits Future.delayed, which never resolves inside the
      // fake-async zone. The constructor already loads the cards synchronously.
      final controller = PaymentController.withRepository(
        MockPaymentRepository(),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: TransferDialog(controller: controller)),
        ),
      );
      await tester.pump();

      // The keypad is on screen without anyone tapping the field first.
      for (var d = 0; d <= 9; d++) {
        expect(find.text('$d'), findsWidgets, reason: 'digit $d is missing');
      }

      // The amount field cannot open the system keyboard, so the keypad is the
      // only way an amount gets in.
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.readOnly, true);
    });
  });
}
