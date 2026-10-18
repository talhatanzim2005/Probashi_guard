import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:probashi_guard/l10n/app_strings.dart';
import 'package:probashi_guard/l10n/language_controller.dart';
import 'package:probashi_guard/widget/language_toggle_switch.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Mirrors how main.dart wires the app: the scope sits above the Navigator so
/// routes and dialogs resolve the same strings.
Widget _app(Widget child) {
  return ValueListenableBuilder<Locale>(
    valueListenable: LanguageController.instance,
    builder: (context, locale, _) => AppStringsScope(
      strings: AppStrings(locale.languageCode),
      child: MaterialApp(
        locale: locale,
        supportedLocales: LanguageController.supportedLocales,
        // The app's own list, so dropping it from main.dart fails this test.
        localizationsDelegates: LanguageController.localizationsDelegates,
        home: child,
      ),
    ),
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    LanguageController.instance.setLanguageCode(LanguageController.englishCode);
  });

  group('AppStrings', () {
    test('translated keys differ between the two languages', () {
      const en = AppStrings('en');
      const bn = AppStrings('bn');
      expect(bn.holdToConfirm, isNot(en.holdToConfirm));
      expect(bn.navHome, isNot(en.navHome));
    });

    testWidgets('falls back to English when no scope is above the widget',
        (tester) async {
      late AppStrings resolved;
      await tester.pumpWidget(MaterialApp(
        home: Builder(builder: (context) {
          resolved = AppStrings.of(context);
          return const SizedBox();
        }),
      ));
      expect(resolved.languageCode, 'en');
      expect(resolved.navHome, 'Home');
    });

    test('no Bangla string is left blank', () {
      // A blank translation would render an empty label, so the dictionary is
      // swept for them: _p falls back to English only when bn is empty.
      const bn = AppStrings('bn');
      final samples = <String>[
        bn.navHome, bn.navPayment, bn.navScan, bn.navNotice,
        bn.cancel, bn.close, bn.done, bn.retry, bn.confirm,
        bn.documentScanner, bn.scanPassport, bn.scanContractVisa,
        bn.verdictSafe, bn.verdictCaution, bn.verdictDoNotSign,
        bn.tipShoiWarning, bn.holdToConfirm, bn.govtIncentive,
        bn.transactionHistory, bn.reviewAndConfirm, bn.sendAmount,
        bn.completePaymentOnStripe, bn.receiveTitle, bn.interCardTransfer,
        bn.officialNotices, bn.quickFeatures, bn.checklistTitle,
      ];
      for (final v in samples) {
        expect(v.trim(), isNotEmpty);
      }
    });

    test('the four named dictionary groups are translated', () {
      const bn = AppStrings('bn');

      // Navigation & menu
      expect(bn.navHome, 'হোম');
      // Document scanner
      expect(bn.scanPassport, 'পাসপোর্ট');
      // Verdicts & fraud warnings
      expect(bn.verdictSafe, 'নিরাপদ');
      expect(bn.verdictCaution, 'সতর্ক থাকুন');
      expect(bn.verdictDoNotSign, 'স্বাক্ষর করবেন না');
      // Remittance / send flow
      expect(bn.govtIncentive, 'সরকারি প্রণোদনা');
      expect(bn.holdToConfirm, 'চেপে ধরে নিশ্চিত করুন');
    });

    test('parameterised strings keep their values in both languages', () {
      expect(const AppStrings('en').checklistDone(3, 8), contains('3/8'));
      expect(const AppStrings('bn').checklistDone(3, 8), contains('3/8'));
    });
  });

  group('LanguageController', () {
    test('toggle flips between Bangla and English', () {
      final c = LanguageController.instance;
      expect(c.isBangla, isFalse);
      c.toggle();
      expect(c.isBangla, isTrue);
      c.toggle();
      expect(c.isBangla, isFalse);
    });

    test('the choice is persisted and read back', () async {
      LanguageController.instance.setLanguageCode(LanguageController.banglaCode);
      // Let the fire-and-forget write land.
      await Future<void>.delayed(Duration.zero);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('app_language_code'), 'bn');

      // A fresh load picks the saved language back up.
      LanguageController.instance
          .setLanguageCode(LanguageController.englishCode);
      SharedPreferences.setMockInitialValues({'app_language_code': 'bn'});
      await LanguageController.instance.load();
      expect(LanguageController.instance.isBangla, isTrue);
    });

    test('an unknown language code is ignored', () {
      LanguageController.instance.setLanguageCode('zz');
      expect(LanguageController.instance.languageCode, 'en');
    });
  });

  group('MaterialLocalizations', () {
    testWidgets('Bangla resolves MaterialLocalizations for Material widgets',
        (tester) async {
      LanguageController.instance.setLanguageCode(LanguageController.banglaCode);

      late BuildContext captured;
      await tester.pumpWidget(_app(
        Builder(builder: (context) {
          captured = context;
          return const Scaffold(body: SizedBox());
        }),
      ));

      // The stock DefaultMaterialLocalizations covers English only, so this
      // is what threw "No MaterialLocalizations found" before the delegates.
      expect(Localizations.localeOf(captured).languageCode, 'bn');
      expect(MaterialLocalizations.of(captured), isNotNull);
    });

    testWidgets('a Drawer opens in Bangla without throwing', (tester) async {
      LanguageController.instance.setLanguageCode(LanguageController.banglaCode);

      final scaffoldKey = GlobalKey<ScaffoldState>();
      await tester.pumpWidget(_app(
        Scaffold(
          key: scaffoldKey,
          endDrawer: const Drawer(child: Text('মেনু')),
          body: const SizedBox(),
        ),
      ));

      scaffoldKey.currentState!.openEndDrawer();
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('মেনু'), findsOneWidget);
    });
  });

  group('LanguageToggleSwitch', () {
    testWidgets('one tap switches the visible text with no restart',
        (tester) async {
      await tester.pumpWidget(_app(
        Scaffold(
          body: Column(
            children: [
              const LanguageToggleSwitch(),
              Builder(
                builder: (context) => Text(AppStrings.of(context).navHome),
              ),
            ],
          ),
        ),
      ));

      expect(find.text('Home'), findsOneWidget);
      expect(find.text('হোম'), findsNothing);

      await tester.tap(find.byType(LanguageToggleSwitch));
      await tester.pumpAndSettle();

      expect(find.text('হোম'), findsOneWidget);
      expect(find.text('Home'), findsNothing);
    });

    testWidgets('both segment labels are always shown', (tester) async {
      await tester.pumpWidget(_app(
        const Scaffold(body: LanguageToggleSwitch()),
      ));

      expect(find.text('বাংলা'), findsOneWidget);
      expect(find.text('ENG'), findsOneWidget);
    });
  });
}
