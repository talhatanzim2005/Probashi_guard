import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:probashi_guard/frontend/documents/document_scan_view.dart';
import 'package:probashi_guard/frontend/documents/saved_documents_portal_view.dart';
import 'package:probashi_guard/frontend/menu/app_menu_drawer.dart';
import 'package:probashi_guard/main.dart';
import 'package:probashi_guard/widget/app_bar.dart';
import 'package:probashi_guard/widget/bottom_navigation_bar.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The scanner is reachable from the shell's bottom bar and from the home
/// screen's vault shortcut. These broke once when a redesign replaced the tab,
/// so they are asserted here rather than in the broader home-screen test.
void main() {
  // The vault reads its offline copy from SharedPreferences. With no mock the
  // read never completes in a test, so the vault's spinner never stops.
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('the Scan tab opens the document scanner', (tester) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const ProbashiGuardApp(home: MainNavigationShell()));
    await tester.pumpAndSettle();

    expect(find.byType(CustomBottomNavigationBar), findsOneWidget);
    expect(find.text('Scan'), findsOneWidget);
    expect(find.byType(DocumentScanView), findsNothing);

    // Not pumpAndSettle: the camera preview shows a progress indicator while it
    // starts up, which never settles.
    await tester.tap(find.text('Scan'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byType(DocumentScanView), findsOneWidget);
    expect(find.text('Scan Document'), findsOneWidget);
    // The scanner has no language picker of its own any more: results follow
    // the app language set in Menu or Profile. The dock holds just Photos and
    // the shutter: no PDF picker, and the vault is reached from Home instead.
    expect(
      find.descendant(
        of: find.byType(DocumentScanView),
        matching: find.byWidgetPredicate((w) => w is SegmentedButton),
      ),
      findsNothing,
    );
    expect(find.text('Photos'), findsOneWidget);
    expect(find.text('Vault'), findsNothing);
    expect(find.text('PDF'), findsNothing);
  });

  testWidgets('the scanner is full-screen, and its back arrow returns Home',
      (tester) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const ProbashiGuardApp(home: MainNavigationShell()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Scan'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // The camera fills the screen: the shell's bars step aside.
    expect(find.byType(DocumentScanView), findsOneWidget);
    expect(find.byType(CustomAppBar), findsNothing);
    expect(find.byType(CustomBottomNavigationBar), findsNothing);

    await tester.tap(find.byIcon(Icons.arrow_back_ios_new_rounded));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Back on Home, with the scanner (and its camera) gone from the tree.
    expect(find.byType(DocumentScanView), findsNothing);
    expect(find.byType(CustomAppBar), findsOneWidget);
    expect(find.byType(CustomBottomNavigationBar), findsOneWidget);
  });

  testWidgets('the floating controls fit a small phone and a wide browser',
      (tester) async {
    // A 360dp phone, then a landscape laptop browser (the web dev setup).
    for (final size in const [Size(360, 640), Size(1280, 720)]) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      await tester.pumpWidget(const ProbashiGuardApp(home: DocumentScanView()));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // An overflow would have been thrown as a test failure above.
      expect(find.text('Scan Document'), findsOneWidget, reason: '$size');
      expect(find.text('Vault'), findsNothing, reason: '$size');
      expect(find.text('PDF'), findsNothing, reason: '$size');
      expect(find.text('Photos'), findsOneWidget, reason: '$size');
      expect(
        find.byIcon(Icons.arrow_back_ios_new_rounded),
        findsOneWidget,
        reason: '$size',
      );
    }
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  testWidgets("Android's back gesture leaves the scanner for Home, not the app",
      (tester) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const ProbashiGuardApp(home: MainNavigationShell()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Scan'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(DocumentScanView), findsOneWidget);

    // What the system back button sends.
    final handled = await tester.binding.handlePopRoute();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(handled, isTrue, reason: 'the scanner consumes the back press');
    expect(find.byType(DocumentScanView), findsNothing);
    expect(find.byType(CustomBottomNavigationBar), findsOneWidget);
  });

  testWidgets('the home screen Fraud Checker shortcut opens the scanner', (tester) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const ProbashiGuardApp(home: MainNavigationShell()));
    await tester.pumpAndSettle();

    final shortcut = find.text('Fraud Checker');
    await tester.scrollUntilVisible(shortcut, 300, scrollable: find.byType(Scrollable).first);
    // Not pumpAndSettle: the camera preview's progress indicator never settles.
    await tester.tap(shortcut);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byType(DocumentScanView), findsOneWidget);
    expect(find.text('Scan Document'), findsOneWidget);
  });

  testWidgets('the menu Fraud Checker entry opens the scanner', (tester) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const ProbashiGuardApp(home: MainNavigationShell()));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.menu_rounded));
    await tester.pumpAndSettle();
    // The home screen behind the drawer has a card by the same name.
    await tester.tap(find.descendant(
      of: find.byType(AppMenuDrawer),
      matching: find.text('Fraud Checker'),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byType(DocumentScanView), findsOneWidget);
  });

  testWidgets('the home screen vault shortcut opens the saved documents portal', (tester) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const ProbashiGuardApp(home: MainNavigationShell()));
    await tester.pumpAndSettle();

    final shortcut = find.text('Saved Documents');
    await tester.scrollUntilVisible(shortcut, 300, scrollable: find.byType(Scrollable).first);
    await tester.tap(shortcut);
    await tester.pumpAndSettle();

    expect(find.byType(SavedDocumentsPortalView), findsOneWidget);
  });
}
