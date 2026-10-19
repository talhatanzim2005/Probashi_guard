import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:probashi_guard/frontend/documents/document_scan_view.dart';
import 'package:probashi_guard/frontend/documents/saved_documents_portal_view.dart';
import 'package:probashi_guard/frontend/menu/app_menu_drawer.dart';
import 'package:probashi_guard/main.dart';
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
    expect(find.text('Document Scanner'), findsOneWidget);
    // The scanner has no language picker of its own any more: results follow
    // the app language set in Menu or Profile. The vault is still one tap away.
    expect(
      find.descendant(
        of: find.byType(DocumentScanView),
        matching: find.byWidgetPredicate((w) => w is SegmentedButton),
      ),
      findsNothing,
    );
    expect(find.text('Vault'), findsOneWidget);
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
    expect(find.text('Document Scanner'), findsOneWidget);
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
