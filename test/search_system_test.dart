import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:probashi_guard/frontend/crChecker/cr_checker_view.dart';
import 'package:probashi_guard/frontend/home/app_search_view.dart';
import 'package:probashi_guard/frontend/home/home_view.dart';
import 'package:probashi_guard/frontend/home/models/search_action_item.dart';
import 'package:probashi_guard/frontend/home/services/search_service_registry.dart';
import 'package:probashi_guard/widget/app_bar.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('SearchActionItem tests', () {
    test('Localized title and subtitle selection works', () {
      final item = SearchActionItem(
        id: 'test_item',
        titleEn: 'Scan Passport',
        titleBn: 'পাসপোর্ট স্ক্যান',
        subtitleEn: 'Passport subtitle English',
        subtitleBn: 'পাসপোর্ট সাবটাইটেল বাংলা',
        icon: Icons.document_scanner,
        keywords: ['passport', 'mrz', 'পাসপোর্ট', 'passpot'],
        action: (_) {},
      );

      expect(item.title('en'), 'Scan Passport');
      expect(item.title('bn'), 'পাসপোর্ট স্ক্যান');
      expect(item.subtitle('en'), 'Passport subtitle English');
      expect(item.subtitle('bn'), 'পাসপোর্ট সাবটাইটেল বাংলা');
    });

    test('Query matching across English, Bengali, and transliterations', () {
      final item = SearchActionItem(
        id: 'test_item',
        titleEn: 'Check Contract Fraud',
        titleBn: 'চুক্তি যাচাই',
        subtitleEn: 'AI verification of job offer',
        subtitleBn: 'এআই দিয়ে চাকরির চুক্তি ও ভিসা যাচাই',
        icon: Icons.verified_user_outlined,
        keywords: ['contract', 'fraud', 'visa', 'job', 'চুক্তি', 'ভিসা', 'chukti', 'dalal'],
        action: (_) {},
      );

      // Matches English title
      expect(item.matches('contract'), isTrue);
      expect(item.matches('FRAUD'), isTrue);

      // Matches Bengali title
      expect(item.matches('চুক্তি'), isTrue);
      expect(item.matches('যাচাই'), isTrue);

      // Matches phonetic / transliterated keywords
      expect(item.matches('chukti'), isTrue);
      expect(item.matches('dalal'), isTrue);
      expect(item.matches('visa'), isTrue);

      // Non-matching query
      expect(item.matches('unrelated_query'), isFalse);
      expect(item.matches(''), isFalse);
    });
  });

  group('SearchServiceRegistry tests', () {
    test('Registry contains all 7 primary app services', () {
      final services = SearchServiceRegistry.getServices();
      expect(services.length, 7);

      final ids = services.map((s) => s.id).toSet();
      expect(
        ids,
        containsAll([
          'scan_passport',
          'contract_fraud',
          'send_remittance',
          'saved_documents',
          'official_notices',
          'departure_checklist',
          'profile_settings',
        ]),
      );
    });

    test('All services have complete bilingual titles and keywords', () {
      final services = SearchServiceRegistry.getServices();
      for (final s in services) {
        expect(s.titleEn.isNotEmpty, isTrue);
        expect(s.titleBn.isNotEmpty, isTrue);
        expect(s.subtitleEn.isNotEmpty, isTrue);
        expect(s.subtitleBn.isNotEmpty, isTrue);
        expect(s.keywords.isNotEmpty, isTrue);
        expect(s.icon, isNotNull);
      }
    });
  });

  group('AppSearchView widget tests', () {
    testWidgets('Renders search input, explore services, and filters dynamically',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        const MaterialApp(
          home: AppSearchView(),
        ),
      );
      await tester.pumpAndSettle();

      // Verify search field exists with hint
      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('Explore Services'), findsOneWidget);
      expect(find.textContaining('Scan Passport', findRichText: true), findsOneWidget);
      expect(find.textContaining('Check Contract Fraud', findRichText: true), findsOneWidget);
      expect(find.textContaining('Send Remittance', findRichText: true), findsOneWidget);

      // Type a query: "fraud"
      await tester.enterText(find.byType(TextField), 'fraud');
      await tester.pumpAndSettle();

      // Only fraud checker matches
      expect(find.textContaining('Check Contract Fraud', findRichText: true), findsOneWidget);
      expect(find.textContaining('Scan Passport', findRichText: true), findsNothing);

      // Clear search with X button
      final clearBtn = find.byIcon(Icons.close_rounded);
      expect(clearBtn, findsOneWidget);
      await tester.tap(clearBtn);
      await tester.pumpAndSettle();

      // All services back
      expect(find.textContaining('Scan Passport', findRichText: true), findsOneWidget);
    });

    testWidgets('Tapping service triggers navigation callback and saves to recents',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      int? navigatedTab;

      await tester.pumpWidget(
        MaterialApp(
          home: AppSearchView(
            onNavigateTab: (tab) => navigatedTab = tab,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap "Official Notices" -> should switch tab to 3
      await tester.tap(find.textContaining('Official Notices', findRichText: true));
      await tester.pumpAndSettle();

      expect(navigatedTab, 3);
    });

    testWidgets('Tapping Scan Passport or Contract Fraud switches to Tab 2 (Scan)',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      int? navigatedTab;

      await tester.pumpWidget(
        MaterialApp(
          home: AppSearchView(
            onNavigateTab: (tab) => navigatedTab = tab,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap "Scan Passport" -> switches tab to 2 (DocumentScanView inside MainNavigationShell)
      await tester.tap(find.textContaining('Scan Passport', findRichText: true));
      await tester.pumpAndSettle();

      expect(navigatedTab, 2);
    });

    testWidgets('CrCheckerView renders complete Pre-Departure Checklist card matching expected page',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        const MaterialApp(
          home: CrCheckerView(),
        ),
      );
      await tester.pumpAndSettle();

      // Card Header
      expect(find.text('Pre-Departure Company & Travel Checklist'), findsAtLeast(1));
      expect(find.text('Check your company and documents before you fly'), findsOneWidget);
      expect(find.text('3/8 Done'), findsOneWidget);
      expect(find.text('View Details'), findsOneWidget);

      // Readiness Progress
      expect(find.text('Departure Readiness'), findsOneWidget);
      expect(find.text('37%'), findsOneWidget);

      // Checklist Items
      expect(find.text('NEXT STEP'), findsOneWidget);
      expect(find.text('Verify BMET Smart Clearance Card via QR code scan'), findsOneWidget);
      expect(find.text('Verify Company Commercial Registration (CR/Trade License) is active'), findsOneWidget);

      // Toggle action
      expect(find.text('Show Fewer Items'), findsOneWidget);
    });
  });

  group('HomeView & CustomAppBar Search Trigger tests', () {
    testWidgets('CustomAppBar search field is clickable and triggers onSearchTap',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      var searchTapped = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            appBar: CustomAppBar(
              onSearchTap: () => searchTapped = true,
            ),
            body: const Center(child: Text('Content')),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final searchFinder = find.byType(TextField);
      expect(searchFinder, findsOneWidget);

      // Verify TextField is readOnly
      final textField = tester.widget<TextField>(searchFinder);
      expect(textField.readOnly, isTrue);

      // Tap search bar
      await tester.tap(searchFinder);
      await tester.pumpAndSettle();

      expect(searchTapped, isTrue);
    });

    testWidgets('HomeView with showSearchBar renders clickable trigger',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      var searchTapped = false;

      await tester.pumpWidget(
        MaterialApp(
          home: HomeView(
            showSearchBar: true,
            onSearchTap: () => searchTapped = true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      final searchFinder = find.byType(TextField);
      expect(searchFinder, findsOneWidget);

      final textField = tester.widget<TextField>(searchFinder);
      expect(textField.readOnly, isTrue);

      await tester.tap(searchFinder);
      await tester.pumpAndSettle();

      expect(searchTapped, isTrue);
    });
  });
}
