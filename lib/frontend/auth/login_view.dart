import 'dart:async';

import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../l10n/app_strings.dart';
import '../../theme/app_colors.dart';
import 'auth_session.dart';
import 'auth_widgets.dart';
import 'forgot_password_view.dart';
import 'otp_verification_view.dart';
import 'register_view.dart';

class LoginView extends StatefulWidget {
  const LoginView({super.key});

  @override
  State<LoginView> createState() => _LoginViewState();
}

class _LoginViewState extends State<LoginView> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;

  /// Google and GitHub finish in the browser and come back through a deep
  /// link, so the result arrives here rather than from the call that opened it.
  StreamSubscription<AuthState>? _oauthSubscription;

  /// Both the password call and the auth stream can report the same sign-in;
  /// only the first may navigate.
  bool _leaving = false;

  @override
  void dispose() {
    _oauthSubscription?.cancel();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _enterApp() async {
    if (_leaving || !mounted) return;
    _leaving = true;
    await goToApp(context);
  }

  Future<void> _logIn() async {
    final s = AppStrings.of(context);
    final email = _emailController.text.trim();
    final password = _passwordController.text;

    if (!isValidEmail(email)) {
      showAuthMessage(context, s.authInvalidEmail);
      return;
    }
    if (password.isEmpty) {
      showAuthMessage(context, s.authEnterPassword);
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() => _isLoading = true);
    try {
      await prepareSignIn();
      await Supabase.instance.client.auth.signInWithPassword(
        email: email,
        password: password,
      );
      await _enterApp();
    } on AuthException catch (e) {
      if (!mounted) return;
      if (e.code == 'email_not_confirmed') {
        await _resumeVerification(email);
      } else {
        showAuthMessage(context, authErrorMessage(s, e));
      }
    } catch (e) {
      if (mounted) showAuthMessage(context, authErrorMessage(s, e));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Someone who registered but never entered their code gets a fresh one and
  /// goes straight to the code screen, instead of a dead-end error.
  Future<void> _resumeVerification(String email) async {
    final s = AppStrings.of(context);
    try {
      await Supabase.instance.client.auth.resend(
        type: OtpType.signup,
        email: email,
      );
    } catch (e) {
      // Usually the once-a-minute limit; the last code is still valid then.
      debugPrint('[LoginView] could not resend the signup code: $e');
    }
    if (!mounted) return;
    showAuthMessage(context, s.authEmailNotConfirmed, isError: false);
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => OtpVerificationView(email: email)),
    );
  }

  // TODO(auth): placeholder until the Google and GitHub providers are enabled
  // in the Supabase dashboard with their client IDs, and authRedirectUrl is
  // added to its Redirect URLs. Until then the browser shows "provider is not
  // enabled" and the person comes back here unchanged.
  Future<void> _logInWith(OAuthProvider provider, String providerName) async {
    final s = AppStrings.of(context);
    try {
      await prepareSignIn();
      final auth = Supabase.instance.client.auth;
      _oauthSubscription ??= auth.onAuthStateChange.listen(
        (state) {
          final user = state.session?.user;
          // The anonymous device session also reports itself here; only a
          // real account counts as logged in.
          if (state.event == AuthChangeEvent.signedIn &&
              user != null &&
              !user.isAnonymous) {
            _enterApp();
          }
        },
        onError: (Object e) {
          if (mounted) showAuthMessage(context, authErrorMessage(s, e));
        },
      );
      final opened = await auth.signInWithOAuth(
        provider,
        redirectTo: authRedirectUrl,
      );
      if (!opened && mounted) {
        showAuthMessage(context, s.authOAuthFailed(providerName));
      }
    } catch (e) {
      debugPrint('[LoginView] $providerName sign-in failed: $e');
      if (mounted) showAuthMessage(context, s.authOAuthFailed(providerName));
    }
  }

  void _openRegister() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const RegisterView()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);

    return AuthScaffold(
      children: [
        AuthTitle(title: s.authWelcomeBack, subtitle: s.authLoginSubtitle),
        const SizedBox(height: 24),

        AuthTextField(
          label: s.authEmail,
          hint: s.authEmailHint,
          icon: Icons.mail_outline_rounded,
          controller: _emailController,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.next,
          autofillHints: const [AutofillHints.email],
        ),
        const SizedBox(height: 18),

        AuthTextField(
          label: s.authPassword,
          hint: s.authPasswordHint,
          icon: Icons.lock_outline_rounded,
          controller: _passwordController,
          obscurable: true,
          textInputAction: TextInputAction.done,
          autofillHints: const [AutofillHints.password],
          onSubmitted: (_) => _logIn(),
        ),

        // Forgot password
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ForgotPasswordView(
                  initialEmail: _emailController.text.trim(),
                ),
              ),
            ),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 4),
            ),
            child: Text(
              s.authForgotPassword,
              style: const TextStyle(
                color: AppColors.royalBlue,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),

        AuthPrimaryButton(
          label: s.authLogIn,
          loading: _isLoading,
          onPressed: _logIn,
        ),
        const SizedBox(height: 20),

        // "Or" divider
        Row(
          children: [
            const Expanded(
              child: Divider(color: Color(0xFFE5E7EB), thickness: 1),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                s.authOr,
                style: TextStyle(
                  fontSize: 13,
                  color: AppColors.ink.withValues(alpha: 0.5),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            const Expanded(
              child: Divider(color: Color(0xFFE5E7EB), thickness: 1),
            ),
          ],
        ),
        const SizedBox(height: 18),

        AuthProviderButton(
          icon: const FaIcon(
            FontAwesomeIcons.google,
            size: 20,
            color: Color(0xFF4285F4),
          ),
          label: s.authWithGoogle,
          onPressed: _isLoading
              ? null
              : () => _logInWith(OAuthProvider.google, 'Google'),
        ),
        const SizedBox(height: 12),

        AuthProviderButton(
          icon: const FaIcon(
            FontAwesomeIcons.github,
            size: 22,
            color: Color(0xFF181717),
          ),
          label: s.authWithGithub,
          onPressed: _isLoading
              ? null
              : () => _logInWith(OAuthProvider.github, 'GitHub'),
        ),
        const SizedBox(height: 22),

        AuthSwitchPrompt(
          prompt: s.authNoAccount,
          action: s.authRegister,
          onTap: _openRegister,
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}
