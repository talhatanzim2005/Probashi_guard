import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:probashi_guard/frontend/documents/document_scan_view.dart';
import 'package:probashi_guard/frontend/documents/saved_documents_portal_view.dart';
import 'package:probashi_guard/main.dart';
import 'package:probashi_guard/widget/bottom_navigation_bar.dart';

/// The scanner is reachable from the shell's bottom bar and from the home
/// screen's vault shortcut. These broke once when a redesign replaced the tab,
/// so they are asserted here rather than in the broader home-screen test.
void main() {
  testWidgets('the Scan tab opens the document scanner', (tester) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const ProbashiGuardApp());
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
    // Both document paths are offered: the language choice and the vault.
    expect(find.text('বাংলা'), findsOneWidget);
    expect(find.text('Vault'), findsOneWidget);
  });

  testWidgets('the home screen vault shortcut opens the saved documents portal', (tester) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const ProbashiGuardApp());
    await tester.pumpAndSettle();

    final shortcut = find.text('Saved Documents');
    await tester.scrollUntilVisible(shortcut, 300, scrollable: find.byType(Scrollable).first);
    await tester.tap(shortcut);
    await tester.pumpAndSettle();

    expect(find.byType(SavedDocumentsPortalView), findsOneWidget);
  });
}
