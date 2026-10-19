import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../l10n/app_strings.dart';
import 'auth_session.dart';
import 'auth_widgets.dart';

/// Resets a forgotten password with an emailed 6-digit code, in two steps on
/// one screen: the email, then the code and the new password.
///
/// A code rather than the usual reset link, so nothing depends on the link
/// opening the app. It only arrives if the Supabase "Reset Password" email
/// template includes `{{ .Token }}`.
class ForgotPasswordView extends StatefulWidget {
  /// Whatever was already typed on the login screen.
  final String initialEmail;

  const ForgotPasswordView({super.key, this.initialEmail = ''});

  @override
  State<ForgotPasswordView> createState() => _ForgotPasswordViewState();
}

class _ForgotPasswordViewState extends State<ForgotPasswordView> {
  late final _emailController = TextEditingController(text: widget.initialEmail);
  final _codeController = TextEditingController();
  final _codeFocus = FocusNode();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();

  /// The email the code went to; null until one is sent.
  String? _sentTo;

  /// The code was accepted. That already signs the person in, so if only the
  /// password update fails, a retry must not spend the code a second time.
  bool _codeAccepted = false;
  bool _isLoading = false;

  @override
  void dispose() {
    _emailController.dispose();
    _codeController.dispose();
    _codeFocus.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _sendCode() async {
    final s = AppStrings.of(context);
    final email = _emailController.text.trim();
    if (!isValidEmail(email)) {
      showAuthMessage(context, s.authInvalidEmail);
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() => _isLoading = true);
    try {
      // Succeeds whether or not the email has an account, so the screen
      // cannot be used to find out who is registered.
      await Supabase.instance.client.auth.resetPasswordForEmail(email);
      if (mounted) setState(() => _sentTo = email);
    } catch (e) {
      if (mounted) showAuthMessage(context, authErrorMessage(s, e));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<bool> _resend() async {
    final s = AppStrings.of(context);
    try {
      await Supabase.instance.client.auth.resetPasswordForEmail(_sentTo!);
      if (!mounted) return true;
      _codeController.clear();
      showAuthMessage(context, s.authCodeResent, isError: false);
      return true;
    } catch (e) {
      if (mounted) showAuthMessage(context, authErrorMessage(s, e));
      return false;
    }
  }

  String? _validateNewPassword(AppStrings s) {
    if (!_codeAccepted && _codeController.text.length != authCodeLength) {
      return s.authCodeIncomplete;
    }
    if (_passwordController.text.length < minPasswordLength) {
      return s.authPasswordTooShort;
    }
    if (_passwordController.text != _confirmController.text) {
      return s.authPasswordsMismatch;
    }
    return null;
  }

  Future<void> _savePassword() async {
    final s = AppStrings.of(context);
    final problem = _validateNewPassword(s);
    if (problem != null) {
      showAuthMessage(context, problem);
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() => _isLoading = true);
    final auth = Supabase.instance.client.auth;
    try {
      if (!_codeAccepted) {
        await prepareSignIn();
        await auth.verifyOTP(
          type: OtpType.recovery,
          email: _sentTo!,
          token: _codeController.text,
        );
        _codeAccepted = true;
      }
      await auth.updateUser(UserAttributes(password: _passwordController.text));
      if (!mounted) return;
      showAuthMessage(context, s.authPasswordChanged, isError: false);
      await goToApp(context);
    } catch (e) {
      if (!mounted) return;
      if (_codeAccepted) {
        showAuthMessage(context, authErrorMessage(s, e));
      } else {
        _codeController.clear();
        showAuthMessage(context, authCodeErrorMessage(s, e));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final sentTo = _sentTo;

    return AuthScaffold(
      showBack: true,
      children: sentTo == null ? _emailStep(s) : _newPasswordStep(s, sentTo),
    );
  }

  List<Widget> _emailStep(AppStrings s) => [
        AuthTitle(title: s.authResetTitle, subtitle: s.authResetSubtitle),
        const SizedBox(height: 24),
        AuthTextField(
          label: s.authEmail,
          hint: s.authEmailHint,
          icon: Icons.mail_outline_rounded,
          controller: _emailController,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.done,
          autofillHints: const [AutofillHints.email],
          onSubmitted: (_) => _sendCode(),
        ),
        const SizedBox(height: 24),
        AuthPrimaryButton(
          label: s.authSendCode,
          loading: _isLoading,
          onPressed: _sendCode,
        ),
      ];

  List<Widget> _newPasswordStep(AppStrings s, String sentTo) => [
        AuthTitle(title: s.authResetTitle, subtitle: s.authCodeSentTo(sentTo)),
        const SizedBox(height: 24),
        if (!_codeAccepted) ...[
          AuthCodeField(
            controller: _codeController,
            focusNode: _codeFocus,
            // The password fields come next, so a full code moves on to them.
            onCompleted: (_) => FocusScope.of(context).nextFocus(),
          ),
          const SizedBox(height: 22),
        ],
        AuthTextField(
          label: s.authNewPassword,
          hint: s.authNewPasswordHint,
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
          onSubmitted: (_) => _savePassword(),
        ),
        const SizedBox(height: 24),
        AuthPrimaryButton(
          label: s.authSavePassword,
          loading: _isLoading,
          onPressed: _savePassword,
        ),
        if (!_codeAccepted) ...[
          const SizedBox(height: 14),
          Center(child: ResendCodeButton(onResend: _resend)),
        ],
      ];
}
