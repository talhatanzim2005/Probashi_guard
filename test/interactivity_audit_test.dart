import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:probashi_guard/frontend/auth/register_view.dart';
import 'package:probashi_guard/frontend/documents/document_scan_view.dart';
import 'package:probashi_guard/frontend/home/app_search_view.dart';
import 'package:probashi_guard/frontend/home/home_view.dart';
import 'package:probashi_guard/frontend/notice/controllers/notice_controller.dart';
import 'package:probashi_guard/frontend/notice/models/notice_model.dart';
import 'package:probashi_guard/frontend/notice/repository/notice_repository.dart';
import 'package:probashi_guard/frontend/payment/controllers/payment_controller.dart';
import 'package:probashi_guard/frontend/payment/repository/mock_payment_repository.dart';
import 'package:probashi_guard/frontend/payment/repository/payment_local_store.dart';
import 'package:probashi_guard/frontend/payment/widgets/transaction_history_section.dart';
import 'package:probashi_guard/frontend/profile/controllers/profile_controller.dart';
import 'package:probashi_guard/frontend/profile/profile_view.dart';
import 'package:probashi_guard/l10n/app_strings.dart';
import 'package:probashi_guard/widget/app_bar.dart';
import 'package:probashi_guard/widget/coming_soon.dart';
import 'package:probashi_guard/widget/ink_surface.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _NoNotices extends NoticeRepository {
  const _NoNotices();

  @override
  Future<List<NoticeModel>> getNotices({int? limit}) async => const [];
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    PaymentLocalStore.resetForTesting();
  });

  void bigScreen(WidgetTester tester) {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  group('the coming-soon fallback', () {
    Widget host(AppStrings strings, String feature) => MaterialApp(
      home: AppStringsScope(
        strings: strings,
        child: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showComingSoon(context, feature),
              child: const Text('go'),
            ),
          ),
        ),
      ),
    );

    testWidgets('says "[feature] is coming soon"', (tester) async {
      await tester.pumpWidget(host(const AppStrings('en'), 'Change PIN'));
      await tester.tap(find.text('go'));
      await tester.pump();
      expect(find.text('Change PIN is coming soon'), findsOneWidget);
    });

    testWidgets('speaks Bangla when the app does', (tester) async {
      await tester.pumpWidget(host(const AppStrings('bn'), 'পিন পরিবর্তন'));
      await tester.tap(find.text('go'));
      await tester.pump();
      expect(find.text('পিন পরিবর্তন শীঘ্রই আসছে'), findsOneWidget);
    });

    testWidgets('a second tap replaces the message instead of queueing', (
      tester,
    ) async {
      await tester.pumpWidget(host(const AppStrings('en'), 'About'));
      await tester.tap(find.text('go'));
      await tester.pump();
      await tester.tap(find.text('go'));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('About is coming soon'), findsOneWidget);
    });
  });

  group('a coloured card shows its ripple', () {
    testWidgets('InkSurface draws it above the fill', (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        MaterialApp(
          // The circular ripple, which the painting matcher below can see (the
          // default on Android is a shader).
          theme: ThemeData(splashFactory: InkRipple.splashFactory),
          home: Scaffold(
            body: Center(
              child: InkSurface(
                onTap: () => taps++,
                borderRadius: BorderRadius.circular(12),
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text('card'),
              ),
            ),
          ),
        ),
      );

      final press = await tester.startGesture(tester.getCenter(find.text('card')));
      await tester.pump(const Duration(milliseconds: 150));
      final material = find.descendant(
        of: find.byType(InkSurface),
        matching: find.byType(Material),
      );
      expect(tester.renderObject<RenderBox>(material.first), paints..circle());
      await press.up();
      await tester.pumpAndSettle();
      expect(taps, 1);
    });
  });

  group('rows that used to do nothing', () {
    testWidgets('a transaction opens "Transaction Details"', (tester) async {
      bigScreen(tester);
      final controller = PaymentController.withRepository(
        MockPaymentRepository(),
      );
      await tester.runAsync(controller.init);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: TransactionHistorySection(
                controller: controller,
                onSeeAllTap: () {},
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text(controller.transactions.first.title).first);
      await tester.pump();
      expect(find.text('Transaction Details is coming soon'), findsOneWidget);
    });

    testWidgets('the Terms and Privacy Policy link', (tester) async {
      bigScreen(tester);
      await tester.pumpWidget(const MaterialApp(home: RegisterView()));
      await tester.scrollUntilVisible(
        find.byType(Checkbox),
        200,
        scrollable: find.byType(Scrollable).first,
      );

      await tester.tapOnText(
        find.textRange.ofSubstring('Terms and Privacy Policy'),
      );
      await tester.pump();
      expect(
        find.text('Terms and Privacy Policy is coming soon'),
        findsOneWidget,
      );
    });

    testWidgets('home quick features answer without their callbacks', (
      tester,
    ) async {
      bigScreen(tester);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HomeView(
              noticeController: NoticeController.withRepository(
                const _NoNotices(),
              ),
            ),
          ),
        ),
      );
      await tester.scrollUntilVisible(
        find.text('Saved Documents'),
        200,
        scrollable: find.byType(Scrollable).first,
      );

      await tester.tap(find.text('Saved Documents'));
      await tester.pump();
      expect(find.text('Saved Documents is coming soon'), findsOneWidget);

      await tester.tap(find.text('Fraud Checker'));
      await tester.pump();
      expect(find.text('Fraud Checker is coming soon'), findsOneWidget);
    });

    testWidgets('a profile opened without handlers still answers', (
      tester,
    ) async {
      bigScreen(tester);
      await tester.pumpWidget(
        MaterialApp(home: ProfileView(controller: ProfileController.instance)),
      );
      final row = find.text('Change PIN');
      await tester.scrollUntilVisible(row, 200);
      await tester.tap(row);
      await tester.pump();
      expect(find.text('Change PIN is coming soon'), findsOneWidget);
    });

    testWidgets('Touch / Face ID is coming soon, with no switch to flip', (
      tester,
    ) async {
      bigScreen(tester);
      final actions = <ProfileAction>[];
      await tester.pumpWidget(
        MaterialApp(
          home: ProfileView(
            controller: ProfileController.instance,
            onAction: actions.add,
          ),
        ),
      );
      final row = find.text('Touch / Face ID');
      await tester.scrollUntilVisible(row, 200);

      expect(find.byType(Switch), findsNothing);
      await tester.tap(row);
      await tester.pump();

      expect(actions, [ProfileAction.biometric]);
      expect(ProfileController.instance.biometricEnabled, isFalse);
    });

    testWidgets('the app bar buttons answer without their callbacks', (
      tester,
    ) async {
      bigScreen(tester);
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(appBar: CustomAppBar(), body: SizedBox()),
        ),
      );
      await tester.tap(find.byIcon(Icons.person_rounded));
      await tester.pump();
      expect(find.text('Profile is coming soon'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.menu_rounded));
      await tester.pump();
      expect(find.text('Menu is coming soon'), findsOneWidget);
      await tester.pumpAndSettle(const Duration(seconds: 5));
    });
  });

  group('search results lead somewhere', () {
    Future<void> pumpSearch(
      WidgetTester tester, {
      VoidCallback? onOpenProfile,
    }) async {
      bigScreen(tester);
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => AppSearchView(onOpenProfile: onOpenProfile),
                  ),
                ),
                child: const Text('open search'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open search'));
      await tester.pumpAndSettle();
    }

    testWidgets('Profile & Settings opens the shell\'s profile', (tester) async {
      var opened = 0;
      await pumpSearch(tester, onOpenProfile: () => opened++);

      await tester.enterText(find.byType(TextField), 'profile');
      await tester.pump();
      await tester.tap(find.byIcon(Icons.settings_rounded));
      await tester.pumpAndSettle();

      expect(opened, 1);
      expect(find.byType(AppSearchView), findsNothing, reason: 'search closes');
    });

    testWidgets('the scanner entries open the scanner on their own', (
      tester,
    ) async {
      await pumpSearch(tester);

      await tester.enterText(find.byType(TextField), 'passport');
      await tester.pump();
      await tester.tap(find.byIcon(Icons.document_scanner_rounded));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byType(DocumentScanView), findsOneWidget);
    });
  });

  group('no empty callbacks', () {
    // A tap handler that is `() {}` (or a `?? () {}` fallback) is how a dead
    // button gets in. Say "coming soon", or do the work.
    test('lib/ has none', () {
      final empty = RegExp(
        r'(on(Tap|Pressed|LongPress|DoubleTap)\s*:\s*(\(\)|\(_\))\s*\{\s*\})|(\?\?\s*(\(\)|\(_\))\s*\{\s*\})',
      );
      final offenders = <String>[];
      for (final entity in Directory('lib').listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final lines = entity.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          if (empty.hasMatch(lines[i])) {
            offenders.add('${entity.path}:${i + 1}: ${lines[i].trim()}');
          }
        }
      }
      expect(offenders, isEmpty, reason: offenders.join('\n'));
    });
  });
}
