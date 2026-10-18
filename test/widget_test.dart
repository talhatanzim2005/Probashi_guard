import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:probashi_guard/main.dart';

void main() {
  testWidgets('App renders custom appbar, interactive checklist, notice slider, and quick features', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const ProbashiGuardApp());

    // Verify AppBar components
    expect(find.byIcon(Icons.person_rounded), findsOneWidget);
    expect(find.byIcon(Icons.search_rounded), findsOneWidget);
    expect(find.text('Tap to see balance'), findsOneWidget);
    expect(find.byIcon(Icons.menu_rounded), findsOneWidget);

    // Verify User Greeting Header
    expect(find.text('Hi, Guest User'), findsOneWidget);

    // Verify Hero Card components
    expect(find.text('Pre-Departure Company & Travel Checklist'), findsOneWidget);
    expect(find.text('3/8 Done'), findsOneWidget);

    // Toggle a checklist item to verify interactive state
    final fourthItem = find.text('Verify BMET Smart Clearance Card via QR code scan');
    // Expand checklist to see all items
    await tester.tap(find.text('Show All 8 Checklist Items'));
    await tester.pumpAndSettle();

    expect(fourthItem, findsOneWidget);
    await tester.tap(fourthItem);
    await tester.pumpAndSettle();
    // Verification count should increase from 3 to 4
    expect(find.text('4/8 Done'), findsOneWidget);

    // Verify Auto-Sliding Notice Slider
    expect(find.text('Notice Board'), findsOneWidget);
    expect(find.text('FRAUD ALERT'), findsOneWidget);

    // Verify Quick Features Grid
    expect(find.text('Quick Features'), findsOneWidget);
    expect(find.text('Saved Documents'), findsOneWidget);
    expect(find.text('Fraud Checker'), findsOneWidget);

    // Verify Bottom Navigation Items
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Payment'), findsOneWidget);
    expect(find.text('Scan'), findsOneWidget);
    expect(find.text('Notice'), findsOneWidget);

    // Tap Notice Board slide and verify it navigates to the Notice tab
    await tester.tap(find.text('FRAUD ALERT'));
    await tester.pumpAndSettle();
    expect(find.text('Official Notices'), findsOneWidget);
  });
}
