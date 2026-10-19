import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:probashi_guard/frontend/auth/auth_session.dart';
import 'package:probashi_guard/frontend/auth/forgot_password_view.dart';
import 'package:probashi_guard/frontend/auth/login_view.dart';
import 'package:probashi_guard/frontend/auth/otp_verification_view.dart';
import 'package:probashi_guard/frontend/auth/phone_country.dart';
import 'package:probashi_guard/frontend/auth/phone_setup_view.dart';
import 'package:probashi_guard/frontend/auth/phone_verifier.dart';
import 'package:probashi_guard/frontend/auth/register_view.dart';
import 'package:probashi_guard/frontend/crChecker/controllers/checklist_controller.dart';
import 'package:probashi_guard/frontend/payment/widgets/amount_numpad.dart';
import 'package:probashi_guard/frontend/profile/controllers/profile_controller.dart';
import 'package:probashi_guard/l10n/language_controller.dart';
import 'package:probashi_guard/main.dart';
import 'package:probashi_guard/widget/language_toggle_switch.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Every case here stops at client-side validation, so none of them reach
// Supabase (which is not initialised in widget tests).
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    LanguageController.instance.setLanguageCode(LanguageController.englishCode);
  });

  Future<void> pumpApp(WidgetTester tester, Widget home) async {
    // A typical phone, so the whole form lays out as it would on a device.
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProbashiGuardApp(home: home));
    await tester.pumpAndSettle();
  }

  Future<void> tapText(WidgetTester tester, String text) async {
    await tester.ensureVisible(find.text(text));
    await tester.tap(find.text(text));
    await tester.pumpAndSettle();
  }

  testWidgets('login offers Google and GitHub and switches to Bangla',
      (tester) async {
    await pumpApp(tester, const LoginView());

    expect(find.text('Welcome back'), findsOneWidget);
    expect(find.text('Log in with Google'), findsOneWidget);
    expect(find.text('Log in with GitHub'), findsOneWidget);

    await tester.tap(find.byType(LanguageToggleSwitch));
    await tester.pumpAndSettle();

    expect(find.text('আবার স্বাগতম'), findsOneWidget);
    expect(find.text('GitHub দিয়ে লগ ইন করুন'), findsOneWidget);
    expect(find.text('Log in with GitHub'), findsNothing);
  });

  testWidgets('login rejects an invalid email before calling Supabase',
      (tester) async {
    await pumpApp(tester, const LoginView());

    await tester.enterText(find.byType(TextField).first, 'not-an-email');
    await tapText(tester, 'Log in');

    expect(find.text('Enter a valid email address'), findsOneWidget);
    expect(find.byType(LoginView), findsOneWidget);
  });

  testWidgets('Register opens the sign-up form and Log in returns',
      (tester) async {
    await pumpApp(tester, const LoginView());

    await tapText(tester, 'Register');
    expect(find.byType(RegisterView), findsOneWidget);
    expect(find.text('Create account'), findsOneWidget);

    await tapText(tester, 'Log in');
    expect(find.byType(RegisterView), findsNothing);
    expect(find.byType(LoginView), findsOneWidget);
  });

  testWidgets('register reports mismatched passwords, in either language',
      (tester) async {
    await pumpApp(tester, const RegisterView());

    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), 'Rahim Uddin');
    await tester.enterText(fields.at(1), 'rahim@example.com');
    await tester.enterText(fields.at(2), 'secret123');
    await tester.enterText(fields.at(3), 'secret124');
    await tapText(tester, 'Register');

    expect(find.text('Passwords do not match'), findsOneWidget);
    expect(find.byType(OtpVerificationView), findsNothing);

    await tester.tap(find.byType(LanguageToggleSwitch));
    await tester.pumpAndSettle();
    await tapText(tester, 'রেজিস্টার করুন');

    expect(find.text('দুটি পাসওয়ার্ড মিলছে না'), findsOneWidget);
  });

  testWidgets('register requires agreeing to the terms', (tester) async {
    await pumpApp(tester, const RegisterView());

    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), 'Rahim Uddin');
    await tester.enterText(fields.at(1), 'rahim@example.com');
    await tester.enterText(fields.at(2), 'secret123');
    await tester.enterText(fields.at(3), 'secret123');
    await tapText(tester, 'Register');

    expect(
      find.text('Please agree to the Terms and Privacy Policy'),
      findsOneWidget,
    );
  });

  testWidgets('code screen names the email and wants all six digits',
      (tester) async {
    await pumpApp(tester, const OtpVerificationView(email: 'rahim@example.com'));

    expect(find.text('Verify your email'), findsOneWidget);
    expect(
      find.text('We sent a 6-digit code to rahim@example.com'),
      findsOneWidget,
    );
    expect(find.text('Resend code in 60s'), findsOneWidget);

    // Bangla keyboard digits are read as 0-9; letters are dropped.
    await tester.enterText(find.byType(TextField), '১২a৩');
    await tester.pump();
    expect(find.text('1'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);

    await tapText(tester, 'Verify');
    expect(find.text('Enter all 6 digits of the code'), findsOneWidget);

    // Unmount so the resend countdown is cancelled before the test ends.
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Forgot password opens the reset screen with the email filled in',
      (tester) async {
    await pumpApp(tester, const LoginView());

    await tester.enterText(find.byType(TextField).first, 'rahim@example.com');
    await tapText(tester, 'Forgot password?');

    expect(find.byType(ForgotPasswordView), findsOneWidget);
    expect(find.text('Reset password'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'rahim@example.com',
    );
  });

  testWidgets('reset screen checks the email first, in Bangla too',
      (tester) async {
    await pumpApp(tester, const ForgotPasswordView());

    await tapText(tester, 'Send code');
    expect(find.text('Enter a valid email address'), findsOneWidget);

    await tester.tap(find.byType(LanguageToggleSwitch));
    await tester.pumpAndSettle();
    expect(find.text('পাসওয়ার্ড রিসেট করুন'), findsOneWidget);
    await tapText(tester, 'কোড পাঠান');
    expect(find.text('সঠিক ইমেইল ঠিকানা লিখুন'), findsOneWidget);
  });

  testWidgets('log out wipes the account from the phone and shows login',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'profile_user_name': 'Rahim Uddin',
      'predeparture_checklist_v1': '11111111',
      'payment_transactions_v1': '[]',
      'saved_documents_cache_v1': '[]',
      'app_language_code': 'bn',
    });
    await ProfileController.instance.load();
    await ChecklistController.instance.load();
    expect(ProfileController.instance.userName, 'Rahim Uddin');

    await pumpApp(
      tester,
      Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => signOut(context),
            child: const Text('sign out'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('sign out'));
    // The wallet reload behind the reset has simulated latency.
    await tester.pumpAndSettle(const Duration(seconds: 3));

    expect(find.byType(LoginView), findsOneWidget);
    expect(ProfileController.instance.userName, 'Guest User');
    expect(
      ChecklistController.instance.completed,
      ChecklistController.defaultState.where((d) => d).length,
    );
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getKeys(), {'app_language_code'});
  });

  /// Types [digits] on the phone screen's keypad, one key at a time.
  Future<void> tapKeys(WidgetTester tester, String digits) async {
    for (final digit in digits.split('')) {
      final key = find.descendant(
        of: find.byType(AmountNumpad),
        matching: find.text(digit),
      );
      await tester.ensureVisible(key);
      await tester.tap(key);
      await tester.pump();
    }
    await tester.pumpAndSettle();
  }

  /// The number field is the first read-only field, the code the second.
  String fieldText(WidgetTester tester, int index) =>
      tester.widget<TextField>(find.byType(TextField).at(index)).controller!.text;

  testWidgets('the phone screen rejects a short number before sending a code',
      (tester) async {
    final verifier = _FakePhoneVerifier();
    await pumpApp(tester, PhoneSetupView(verifier: verifier));

    expect(find.text('Add your phone number'), findsOneWidget);

    await tapKeys(tester, '12345');
    await tapText(tester, 'Send code');

    expect(
      find.text('Enter a number with 11 digits, like 01712345678'),
      findsOneWidget,
    );
    // The malformed number never reached the provider.
    expect(verifier.sentTo, isEmpty);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the number is typed on the keypad only and capped at 11 digits',
      (tester) async {
    await pumpApp(tester, PhoneSetupView(verifier: _FakePhoneVerifier()));

    // Read-only and keyboard-less: the keypad is the only way in, so nothing
    // but 0-9 can ever reach the field.
    final numberField = tester.widget<TextField>(find.byType(TextField).at(0));
    expect(numberField.readOnly, isTrue);
    expect(numberField.keyboardType, TextInputType.none);
    expect(find.byType(AmountNumpad), findsOneWidget);

    // Twelve keys on a Bangladeshi number: the twelfth is refused. (No leading
    // 0, so the number is not valid and the keypad stays on this field.)
    await tapKeys(tester, '111111111111');
    expect(fieldText(tester, 0), '11111111111');
    expect(find.text('11 / 11 digits'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a leading 0 survives on the keypad', (tester) async {
    await pumpApp(tester, PhoneSetupView(verifier: _FakePhoneVerifier()));

    await tapKeys(tester, '017');
    expect(fieldText(tester, 0), '017');

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('another country changes the cap', (tester) async {
    await pumpApp(tester, PhoneSetupView(verifier: _FakePhoneVerifier()));

    await tester.tap(find.byType(DropdownButtonFormField<PhoneCountry>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('🇶🇦  Qatar  (+974)').last);
    await tester.pumpAndSettle();

    expect(find.text('+974'), findsOneWidget);
    // Qatari mobiles are 8 digits with no trunk 0, so the eighth digit
    // completes the number and the keypad moves on to the code.
    await tapKeys(tester, '33123456');
    expect(fieldText(tester, 0), '33123456');
    expect(find.text('8 / 8 digits'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('sending a code sends E.164 and starts the resend wait',
      (tester) async {
    final verifier = _FakePhoneVerifier();
    await pumpApp(tester, PhoneSetupView(verifier: verifier));

    await tapKeys(tester, '01712345678');
    await tapText(tester, 'Send code');

    // Typed the local way, sent the way Firebase needs it.
    expect(verifier.sentTo, ['+8801712345678']);
    expect(find.text('Code sent'), findsWidgets);
    expect(find.text('Verify number'), findsOneWidget);
    // The 2-minute wait starts straight away, so a second send is not offered.
    expect(find.text('Resend code in 120s'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a wrong code is reported and the code field is cleared',
      (tester) async {
    final verifier = _FakePhoneVerifier(
      failConfirmWith: PhoneVerificationFailure.wrongCode,
    );
    await pumpApp(tester, PhoneSetupView(verifier: verifier));

    await tapKeys(tester, '01712345678');
    await tapText(tester, 'Send code');

    // The sixth digit submits the code by itself.
    await tapKeys(tester, '000000');

    expect(find.text('That code is wrong or has expired'), findsOneWidget);
    expect(verifier.confirmed, ['000000']);
    expect(fieldText(tester, 1), isEmpty);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a number and its code typed together are checked in one step',
      (tester) async {
    // How a Firebase test number is used: no separate "Send code" first.
    final verifier = _FakePhoneVerifier(
      // Fails, so the test stays on this screen instead of entering the app,
      // which would need a live Supabase.
      failConfirmWith: PhoneVerificationFailure.wrongCode,
    );
    await pumpApp(tester, PhoneSetupView(verifier: verifier));

    // The eleventh digit moves the keypad on to the code field by itself.
    await tapKeys(tester, '01700000000');
    await tapKeys(tester, '123456');

    expect(verifier.sentTo, ['+8801700000000']);
    expect(verifier.confirmed, ['123456']);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('an unconfigured provider still lets the person carry on',
      (tester) async {
    // The real default until Firebase is wired up.
    await pumpApp(tester, const PhoneSetupView());

    await tapKeys(tester, '01712345678');
    await tapText(tester, 'Send code');

    expect(
      find.textContaining('Phone verification is not set up yet'),
      findsOneWidget,
    );
    // Still on the number step, with a way out of the dead end.
    expect(find.text('Skip for now'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the phone screen offers a way back to login', (tester) async {
    // A saved session skips login at launch and lands here, so without this
    // there would be no route to the login or sign-up screens.
    await pumpApp(tester, PhoneSetupView(verifier: _FakePhoneVerifier()));

    await tester.ensureVisible(find.text('Log Out'));
    expect(find.text('Log Out'), findsOneWidget);
    expect(find.text('Skip for now'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('opened from the profile, it is a page with a back arrow',
      (tester) async {
    await pumpApp(
      tester,
      PhoneSetupView(verifier: _FakePhoneVerifier(), openedFromProfile: true),
    );

    expect(find.text('Add your phone number'), findsOneWidget);
    expect(find.byType(AmountNumpad), findsOneWidget);
    expect(find.byIcon(Icons.arrow_back_rounded), findsWidgets);
    // The profile has its own log out, and there is nothing to skip to.
    expect(find.text('Skip for now'), findsNothing);
    expect(find.text('Log Out'), findsNothing);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the phone screen in Bangla', (tester) async {
    LanguageController.instance.setLanguageCode(LanguageController.banglaCode);
    await pumpApp(tester, PhoneSetupView(verifier: _FakePhoneVerifier()));

    expect(find.text('আপনার মোবাইল নম্বর দিন'), findsOneWidget);
    expect(find.text('কোড পাঠান'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('code screen in Bangla', (tester) async {
    LanguageController.instance.setLanguageCode(LanguageController.banglaCode);
    await pumpApp(tester, const OtpVerificationView(email: 'rahim@example.com'));

    expect(find.text('আপনার ইমেইল যাচাই করুন'), findsOneWidget);
    expect(
      find.text('আমরা rahim@example.com-এ একটি ৬-সংখ্যার কোড পাঠিয়েছি'),
      findsOneWidget,
    );
    expect(find.text('যাচাই করুন'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });
}

/// Stands in for Firebase: records what it was asked to do, and can be told to
/// fail the way a real provider would.
class _FakePhoneVerifier implements PhoneVerifier {
  final PhoneVerificationFailure? failConfirmWith;

  final List<String> sentTo = [];
  final List<String> confirmed = [];

  _FakePhoneVerifier({this.failConfirmWith});

  @override
  Future<void> sendCode(String phone) async => sentTo.add(phone);

  @override
  Future<void> confirmCode(String code) async {
    confirmed.add(code);
    if (failConfirmWith != null) {
      throw PhoneVerificationException(failConfirmWith!);
    }
  }
}
