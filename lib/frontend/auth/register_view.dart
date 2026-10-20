import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../l10n/app_strings.dart';
import '../../theme/app_colors.dart';
import '../../widget/coming_soon.dart';
import 'auth_session.dart';
import 'auth_widgets.dart';
import 'otp_verification_view.dart';

class RegisterView extends StatefulWidget {
  const RegisterView({super.key});

  @override
  State<RegisterView> createState() => _RegisterViewState();
}

class _RegisterViewState extends State<RegisterView> {
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _agreedToTerms = false;
  bool _isLoading = false;

  /// Taps on the "Terms and Privacy Policy" words. There is no policy page yet,
  /// so the link says so instead of looking clickable and doing nothing.
  late final TapGestureRecognizer _termsTap = TapGestureRecognizer()
    ..onTap = () =>
        showComingSoon(context, AppStrings.of(context).featureTermsPrivacy);

  @override
  void dispose() {
    _termsTap.dispose();
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  /// The first problem with the form, or null when it can be sent.
  String? _validate(AppStrings s) {
    if (_nameController.text.trim().isEmpty) return s.authEnterName;
    if (!isValidEmail(_emailController.text.trim())) return s.authInvalidEmail;
    if (_passwordController.text.length < minPasswordLength) {
      return s.authPasswordTooShort;
    }
    if (_passwordController.text != _confirmController.text) {
      return s.authPasswordsMismatch;
    }
    if (!_agreedToTerms) return s.authAcceptTerms;
    return null;
  }

  Future<void> _register() async {
    final s = AppStrings.of(context);
    final problem = _validate(s);
    if (problem != null) {
      showAuthMessage(context, problem);
      return;
    }

    final email = _emailController.text.trim();
    FocusScope.of(context).unfocus();
    setState(() => _isLoading = true);
    try {
      await prepareSignIn();
      final response = await Supabase.instance.client.auth.signUp(
        email: email,
        password: _passwordController.text,
        data: {'full_name': _nameController.text.trim()},
      );
      if (!mounted) return;

      // For an email that already has a confirmed account, Supabase answers
      // with a stand-in user that has no identities instead of an error, so
      // the endpoint cannot be used to discover who is registered.
      if (response.user?.identities?.isEmpty ?? false) {
        showAuthMessage(context, s.authAccountExists);
        return;
      }
      // A session straight away means "Confirm email" is switched off in the
      // Supabase dashboard: no code is coming, so waiting for one would strand
      // the person.
      if (response.session != null) {
        await goToApp(context);
        return;
      }
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => OtpVerificationView(email: email)),
      );
    } catch (e) {
      if (mounted) showAuthMessage(context, authErrorMessage(s, e));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);

    return AuthScaffold(
      showBack: true,
      compactHeader: true,
      children: [
        AuthTitle(title: s.authCreateAccount, subtitle: s.authRegisterSubtitle),
        const SizedBox(height: 22),

        AuthTextField(
          label: s.authFullName,
          hint: s.authFullNameHint,
          icon: Icons.person_outline_rounded,
          controller: _nameController,
          keyboardType: TextInputType.name,
          textInputAction: TextInputAction.next,
          autofillHints: const [AutofillHints.name],
        ),
        const SizedBox(height: 16),

        AuthTextField(
          label: s.authEmail,
          hint: s.authEmailHint,
          icon: Icons.mail_outline_rounded,
          controller: _emailController,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.next,
          autofillHints: const [AutofillHints.email],
        ),
        const SizedBox(height: 16),

        AuthTextField(
          label: s.authPassword,
          hint: s.authPasswordHint,
          icon: Icons.lock_outline_rounded,
          controller: _passwordController,
          obscurable: true,
          textInputAction: TextInputAction.next,
          autofillHints: const [AutofillHints.newPassword],
        ),
        const SizedBox(height: 16),

        AuthTextField(
          label: s.authConfirmPassword,
          hint: s.authConfirmPasswordHint,
          icon: Icons.lock_outline_rounded,
          controller: _confirmController,
          obscurable: true,
          textInputAction: TextInputAction.done,
          autofillHints: const [AutofillHints.newPassword],
          onSubmitted: (_) => _register(),
        ),
        const SizedBox(height: 10),

        _termsCheckbox(s),
        const SizedBox(height: 14),

        AuthPrimaryButton(
          label: s.authRegister,
          loading: _isLoading,
          onPressed: _register,
        ),
        const SizedBox(height: 18),

        AuthSwitchPrompt(
          prompt: s.authHaveAccount,
          action: s.authLogIn,
          onTap: () => Navigator.pop(context),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  // TODO(auth): point the "Terms and Privacy Policy" link at the real policy
  // page once one exists; until then it says "coming soon".
  Widget _termsCheckbox(AppStrings s) {
    return InkWell(
      onTap: () => setState(() => _agreedToTerms = !_agreedToTerms),
      borderRadius: BorderRadius.circular(8),
      child: Row(
        children: [
          Checkbox(
            value: _agreedToTerms,
            onChanged: (value) =>
                setState(() => _agreedToTerms = value ?? false),
            activeColor: AppColors.royalBlue,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(5),
            ),
            side: const BorderSide(color: Color(0xFFD1D5DB), width: 1.5),
          ),
          Expanded(
            child: Text.rich(
              TextSpan(
                style: TextStyle(
                  fontSize: 13,
                  color: AppColors.ink.withValues(alpha: 0.7),
                ),
                children: [
                  TextSpan(text: s.authAgreePrefix),
                  TextSpan(
                    text: s.authTermsLink,
                    recognizer: _termsTap,
                    style: const TextStyle(
                      color: AppColors.royalBlue,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  TextSpan(text: s.authAgreeSuffix),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
