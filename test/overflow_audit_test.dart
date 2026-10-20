import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:probashi_guard/frontend/auth/forgot_password_view.dart';
import 'package:probashi_guard/frontend/auth/login_view.dart';
import 'package:probashi_guard/frontend/auth/otp_verification_view.dart';
import 'package:probashi_guard/frontend/auth/phone_setup_view.dart';
import 'package:probashi_guard/frontend/auth/phone_verifier.dart';
import 'package:probashi_guard/frontend/auth/register_view.dart';
import 'package:probashi_guard/frontend/documents/document_detail_view.dart';
import 'package:probashi_guard/frontend/documents/document_scan_view.dart';
import 'package:probashi_guard/frontend/documents/models/document_analysis.dart';
import 'package:probashi_guard/frontend/documents/saved_documents_portal_view.dart';
import 'package:probashi_guard/frontend/home/app_search_view.dart';
import 'package:probashi_guard/frontend/menu/app_menu_drawer.dart';
import 'package:probashi_guard/frontend/notice/controllers/notice_controller.dart';
import 'package:probashi_guard/frontend/notice/models/notice_model.dart';
import 'package:probashi_guard/frontend/notice/notice_view.dart';
import 'package:probashi_guard/frontend/notice/repository/notice_repository.dart';
import 'package:probashi_guard/frontend/payment/controllers/payment_controller.dart';
import 'package:probashi_guard/frontend/payment/flows/send_flow_view.dart';
import 'package:probashi_guard/frontend/payment/models/beneficiary_model.dart';
import 'package:probashi_guard/frontend/payment/widgets/awaiting_payment_dialog.dart';
import 'package:probashi_guard/frontend/payment/widgets/receive_bottom_sheet.dart';
import 'package:probashi_guard/frontend/payment/widgets/transfer_dialog.dart';
import 'package:probashi_guard/frontend/profile/controllers/profile_controller.dart';
import 'package:probashi_guard/frontend/profile/profile_view.dart';
import 'package:probashi_guard/frontend/prohori/prohori_chat_view.dart';
import 'package:probashi_guard/l10n/language_controller.dart';
import 'package:probashi_guard/main.dart';
import 'package:probashi_guard/widget/bottom_navigation_bar.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Lays every screen out on the screens people actually have: a small phone,
/// a short landscape one, a phone with the keyboard up, a laptop browser, with
/// large system text and in both languages. Any "RenderFlex overflowed" (the
/// yellow-and-black stripes) fails the test and names the widget and screen.
void main() {
  // The test font draws every letter as a square a full em wide, about twice
  // a real letter, so without real fonts every label "overflows". Roboto is
  // Android's font and ships with the Flutter SDK; Bangla falls back to the
  // machine's Bengali font, as it does on a phone.
  setUpAll(_loadRoboto);
  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(
    () => LanguageController.instance.setLanguageCode(
      LanguageController.englishCode,
    ),
  );

  for (final screen in _screens) {
    testWidgets('${screen.name} lays out without overflow', (tester) async {
      final problems = <String>[];
      for (final config in _configs) {
        if (config.keyboard > 0 && !screen.hasInput) continue;
        for (final lang in const [
          LanguageController.englishCode,
          LanguageController.banglaCode,
        ]) {
          problems.addAll(await _layOut(tester, screen, config, lang));
        }
      }
      expect(problems.toSet().toList(), isEmpty);
    });
  }
}

Future<void> _loadRoboto() async {
  final root = Platform.environment['FLUTTER_ROOT'];
  final dir = Directory('$root/bin/cache/artifacts/material_fonts');
  if (root == null || !dir.existsSync()) {
    fail(
      'Roboto not found under FLUTTER_ROOT ($root); run with `flutter test`.',
    );
  }
  final loader = FontLoader('Roboto');
  for (final weight in const ['regular', 'medium', 'bold', 'black']) {
    final bytes = File('${dir.path}/roboto-$weight.ttf').readAsBytesSync();
    loader.addFont(Future.value(ByteData.sublistView(bytes)));
  }
  await loader.load();
}

class _Config {
  final String name;
  final Size size;
  final double dpr;
  final double textScale;
  final double keyboard;
  final double statusBar;

  const _Config(
    this.name,
    this.size, {
    this.dpr = 3,
    this.textScale = 1,
    this.keyboard = 0,
    this.statusBar = 24,
  });
}

const _configs = [
  _Config('320x568', Size(320, 568)),
  _Config('360x640', Size(360, 640)),
  _Config('360x640 text x1.3', Size(360, 640), textScale: 1.3),
  _Config('360x640 text x2', Size(360, 640), textScale: 2),
  _Config('landscape 640x360', Size(640, 360)),
  _Config('keyboard 320x568', Size(320, 568), keyboard: 260),
  _Config('keyboard 360x640', Size(360, 640), keyboard: 300),
  _Config(
    'keyboard 360x640 text x1.3',
    Size(360, 640),
    keyboard: 300,
    textScale: 1.3,
  ),
  _Config('browser 1280x720', Size(1280, 720), dpr: 1, statusBar: 0),
];

class _Screen {
  final String name;
  final Widget Function() build;

  /// Has a text field, so the keyboard can be up on it.
  final bool hasInput;

  /// Opens a tab, a dialog or a drawer once the screen is up.
  final Future<void> Function(WidgetTester tester)? then;

  const _Screen(this.name, this.build, {this.hasInput = false, this.then});
}

Future<List<String>> _layOut(
  WidgetTester tester,
  _Screen screen,
  _Config config,
  String lang,
) async {
  final where = '${screen.name} @ ${config.name} [$lang]';
  final problems = <String>[];
  final original = FlutterError.onError;
  FlutterError.onError = (details) {
    final text = details.toString();
    // Only layout overflow matters here.
    if (!text.contains('overflowed')) return;
    final headline =
        RegExp(
          r'A Render\w+ overflowed by [\d.]+ pixels on the \w+',
        ).firstMatch(text)?.group(0) ??
        text.split('\n').first;
    final source =
        RegExp(r'file:///\S+?/(lib/\S+:\d+:\d+)').firstMatch(text)?.group(1) ??
        'unknown source';
    problems.add('$where: $headline — $source');
  };
  try {
    tester.view.physicalSize = config.size * config.dpr;
    tester.view.devicePixelRatio = config.dpr;
    tester.view.padding = FakeViewPadding(top: config.statusBar * config.dpr);
    tester.view.viewInsets = FakeViewPadding(
      bottom: config.keyboard * config.dpr,
    );
    tester.platformDispatcher.textScaleFactorTestValue = config.textScale;
    LanguageController.instance.setLanguageCode(lang);

    await tester.pumpWidget(ProbashiGuardApp(home: screen.build()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    if (screen.then != null) {
      try {
        await screen.then!(tester);
      } catch (e) {
        problems.add('$where: could not open it: $e');
      }
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    }
    await _scrollThrough(tester);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  } finally {
    FlutterError.onError = original;
    tester.view.reset();
    tester.platformDispatcher.clearTextScaleFactorTestValue();
  }
  return problems;
}

/// Lists only lay out what is on screen, so walk every scrollable to its end,
/// a screenful at a time, to lay out each row at least once.
Future<void> _scrollThrough(WidgetTester tester) async {
  final scrollables = tester.stateList<ScrollableState>(
    find.byType(Scrollable),
  );
  for (final state in scrollables.toList()) {
    if (!state.mounted) continue;
    final position = state.position;
    // An endless carousel never reaches its end.
    for (var step = 0; step < 40; step++) {
      if (!position.hasContentDimensions ||
          !position.maxScrollExtent.isFinite ||
          position.pixels >= position.maxScrollExtent) {
        break;
      }
      position.jumpTo(
        (position.pixels + position.viewportDimension).clamp(
          0.0,
          position.maxScrollExtent,
        ),
      );
      await tester.pump();
    }
  }
}

/// Scrolls the page down until [finder] is built and on screen, then taps it.
Future<void> _tapVisible(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    200,
    scrollable: find
        .byWidgetPredicate(
          (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
        )
        .first,
  );
  await tester.pump();
  await tester.tap(finder);
}

Future<void> _shellTab(WidgetTester tester, int index) async {
  tester
      .widget<CustomBottomNavigationBar>(find.byType(CustomBottomNavigationBar))
      .onTap(index);
}

/// Shows [open] over a blank page once it is up, the way the app opens sheets.
Widget _host(void Function(BuildContext context) open) => Builder(
  builder: (context) {
    WidgetsBinding.instance.addPostFrameCallback((_) => open(context));
    return const Scaffold(body: SizedBox.expand());
  },
);

class _FakeVerifier implements PhoneVerifier {
  @override
  Future<void> sendCode(String phone) async {}

  @override
  Future<void> confirmCode(String code) async {}
}

class _FakeNotices extends NoticeRepository {
  const _FakeNotices();

  @override
  Future<List<NoticeModel>> getNotices({int? limit}) async => [
    for (var i = 0; i < 4; i++)
      NoticeModel(
        id: '$i',
        title:
            'Saudi Arabia extends the work permit renewal deadline for expatriate workers',
        description:
            'Expatriate workers will be allowed to complete their renewal at any labour office before the new deadline.',
        imageUrl: null,
        sourceUrl: 'https://www.tbsnews.net/bangladesh/migration/$i',
        createdAt: DateTime(2026, 10, 18, 12 - i),
      ),
  ];
}

const _recipient = BeneficiaryModel(
  id: 'r1',
  name: 'Mohammad Rahim Uddin Chowdhury',
  phoneOrAccount: '01712345678',
  providerType: 'bKash',
  avatarUrl: '',
  initials: 'MR',
);

DocumentAnalysis _analysis() => DocumentAnalysis.fromMap({
  'document_type': 'Employment contract for a domestic worker',
  'is_legible': true,
  'salary': {
    'amount': 800,
    'currency': 'SAR',
    'period': 'monthly',
    'monthly_amount': 800,
    'monthly_sar_equivalent': 800,
    'risk': 'high',
    'explanation': 'Below the SAR 1,000 minimum agreed for Bangladeshi workers',
  },
  'fees': {
    'items': [
      {
        'name': 'Recruitment and visa processing fee',
        'amount': 4500,
        'currency': 'SAR',
      },
    ],
    'risk': 'high',
    'explanation': 'The worker should not pay recruitment fees',
  },
  'duration': {'text': '2 years', 'months': 24},
  'cancellation': {
    'text': 'Employer may cancel without notice',
    'risk': 'high',
    'explanation': 'No notice period protects the worker',
  },
  'tip_shoi_detected': true,
  'tip_shoi_findings': [
    {
      'type': 'blank_space_before_signature',
      'location': 'Page bottom, above the thumbprint box',
      'explanation':
          'Blank lines above the thumbprint box can be filled in later',
    },
  ],
  'verdict': 'DO_NOT_SIGN',
  'summary_3_lines': [
    'The salary is below the agreed minimum.',
    'The worker is asked to pay recruitment fees.',
    'There is blank space above the signature.',
  ],
  'translation_segments': [
    {
      'original': 'Monthly salary: SAR 800',
      'translated': 'মাসিক বেতন: ৮০০ রিয়াল',
    },
    {'original': '[BLANK]', 'translated': 'খালি জায়গা'},
  ],
  'full_translation': 'মাসিক বেতন: ৮০০ রিয়াল',
});

final _screens = <_Screen>[
  _Screen('Login', () => const LoginView(), hasInput: true),
  _Screen('Register', () => const RegisterView(), hasInput: true),
  _Screen('Forgot password', () => const ForgotPasswordView(), hasInput: true),
  _Screen(
    'Email code',
    () => const OtpVerificationView(email: 'worker.name@example.com'),
    hasInput: true,
  ),
  _Screen(
    'Phone setup',
    () => PhoneSetupView(verifier: _FakeVerifier()),
    hasInput: true,
  ),
  _Screen(
    'Phone setup from Profile',
    () => PhoneSetupView(verifier: _FakeVerifier(), openedFromProfile: true),
    hasInput: true,
  ),
  _Screen('Home', () => const MainNavigationShell()),
  _Screen(
    'Payment tab',
    () => const MainNavigationShell(),
    then: (tester) => _shellTab(tester, 1),
  ),
  _Screen(
    'Scan tab',
    () => const MainNavigationShell(),
    then: (tester) => _shellTab(tester, 2),
  ),
  _Screen(
    'Notice tab',
    () => const MainNavigationShell(),
    then: (tester) => _shellTab(tester, 3),
  ),
  _Screen(
    'Menu drawer',
    () => const MainNavigationShell(),
    then: (tester) async => tester.tap(find.byIcon(Icons.menu_rounded)),
  ),
  _Screen('Scanner', () => const DocumentScanView()),
  _Screen(
    'Notices',
    () => NoticeView(
      controller: NoticeController.withRepository(const _FakeNotices()),
    ),
  ),
  _Screen(
    'Profile',
    () => ProfileView(controller: ProfileController.instance, onAction: (_) {}),
  ),
  _Screen('Saved documents', () => const SavedDocumentsPortalView()),
  _Screen('Prohori chat', () => const ProhoriChatView(), hasInput: true),
  _Screen('Search', () => const AppSearchView(), hasInput: true),
  _Screen(
    'Send: contact',
    () => SendFlowView(controller: PaymentController.instance),
    hasInput: true,
  ),
  _Screen(
    'Send: amount',
    () => SendFlowView(
      controller: PaymentController.instance,
      initialRecipient: _recipient,
    ),
  ),
  _Screen(
    'Scan result',
    () => DocumentDetailView(
      analysis: _analysis(),
      language: DocumentLanguage.english,
    ),
  ),
  _Screen(
    'Scan result, unsaved',
    () => DocumentDetailView(
      analysis: _analysis(),
      language: DocumentLanguage.bangla,
      saved: false,
      pages: 3,
      onSave: () async => true,
    ),
  ),
  _Screen(
    'Transfer dialog',
    () => _host(
      (context) => TransferDialog.show(context, PaymentController.instance),
    ),
    hasInput: true,
  ),
  _Screen(
    'Discard dialog',
    () => DocumentDetailView(
      analysis: _analysis(),
      language: DocumentLanguage.english,
      saved: false,
      onSave: () async => true,
    ),
    then: (tester) => _tapVisible(tester, find.byType(OutlinedButton).last),
  ),
  _Screen('Logout dialog', () => _host(confirmLogout)),
  _Screen(
    'Payment wait dialog',
    () => _host(
      (context) => showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => AwaitingPaymentDialog(
          controller: PaymentController.instance,
          sessionId: 'cs_test_layout',
          checkoutUrl: 'https://checkout.stripe.com/c/pay/cs_test_layout',
          recipientName: _recipient.name,
        ),
      ),
    ),
  ),
  _Screen(
    'Add recipient sheet',
    () => const MainNavigationShell(),
    hasInput: true,
    then: (tester) async {
      await _shellTab(tester, 1);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await _tapVisible(tester, find.byIcon(Icons.add));
    },
  ),
  _Screen(
    'Language sheet',
    () => ProfileView(controller: ProfileController.instance, onAction: (_) {}),
    then: (tester) => _tapVisible(tester, find.byIcon(Icons.translate_rounded)),
  ),
  _Screen(
    'Receive sheet',
    () => _host(
      (context) => ReceiveBottomSheet.show(context, PaymentController.instance),
    ),
  ),
];
