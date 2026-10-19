import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../l10n/app_strings.dart';
import 'auth_session.dart';
import 'auth_widgets.dart';

/// Confirms a new account with the 6-digit code Supabase emails on sign-up.
///
/// The code only arrives if the Supabase "Confirm signup" email template
/// includes `{{ .Token }}`; the stock template sends a link instead.
class OtpVerificationView extends StatefulWidget {
  final String email;

  const OtpVerificationView({super.key, required this.email});

  @override
  State<OtpVerificationView> createState() => _OtpVerificationViewState();
}

class _OtpVerificationViewState extends State<OtpVerificationView> {
  final _codeController = TextEditingController();
  final _codeFocus = FocusNode();
  bool _isVerifying = false;

  @override
  void dispose() {
    _codeController.dispose();
    _codeFocus.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    if (_isVerifying) return;
    final s = AppStrings.of(context);
    final code = _codeController.text;
    if (code.length != authCodeLength) {
      showAuthMessage(context, s.authCodeIncomplete);
      return;
    }

    setState(() => _isVerifying = true);
    try {
      await prepareSignIn();
      await Supabase.instance.client.auth.verifyOTP(
        type: OtpType.signup,
        email: widget.email,
        token: code,
      );
      if (mounted) await goToApp(context);
    } catch (e) {
      if (!mounted) return;
      _codeController.clear();
      _codeFocus.requestFocus();
      showAuthMessage(context, authCodeErrorMessage(s, e));
    } finally {
      if (mounted) setState(() => _isVerifying = false);
    }
  }

  Future<bool> _resend() async {
    final s = AppStrings.of(context);
    try {
      await Supabase.instance.client.auth.resend(
        type: OtpType.signup,
        email: widget.email,
      );
      if (!mounted) return true;
      _codeController.clear();
      showAuthMessage(context, s.authCodeResent, isError: false);
      return true;
    } catch (e) {
      if (mounted) showAuthMessage(context, authErrorMessage(s, e));
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);

    return AuthScaffold(
      showBack: true,
      children: [
        AuthTitle(
          title: s.authVerifyTitle,
          subtitle: s.authCodeSentTo(widget.email),
        ),
        const SizedBox(height: 28),
        AuthCodeField(
          controller: _codeController,
          focusNode: _codeFocus,
          onCompleted: (_) => _verify(),
        ),
        const SizedBox(height: 28),
        AuthPrimaryButton(
          label: s.authVerify,
          loading: _isVerifying,
          onPressed: _verify,
        ),
        const SizedBox(height: 14),
        Center(child: ResendCodeButton(onResend: _resend)),
      ],
    );
  }
}
