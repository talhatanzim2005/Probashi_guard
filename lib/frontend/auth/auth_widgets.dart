import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../l10n/app_strings.dart';
import '../../theme/app_colors.dart';
import '../../widget/language_toggle_switch.dart';

final RegExp _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

bool isValidEmail(String email) => _emailPattern.hasMatch(email);

/// Supabase's default minimum; a shorter password is rejected server-side.
const int minPasswordLength = 6;

/// Length of the codes Supabase emails for sign-up and password reset.
const int authCodeLength = 6;

void showAuthMessage(
  BuildContext context,
  String message, {
  bool isError = true,
}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? AppColors.crimsonRed : AppColors.emeraldGreen,
        behavior: SnackBarBehavior.floating,
      ),
    );
}

/// Turns a Supabase Auth failure into something the person can act on, in
/// their language. Codes are the stable GoTrue `error_code` values; the
/// server's own message is English-only and often technical, so it is never shown.
String authErrorMessage(AppStrings s, Object error) {
  if (error is AuthRetryableFetchException || error is TimeoutException) {
    return s.authNetworkError;
  }
  if (error is AuthException) {
    switch (error.code) {
      case 'invalid_credentials':
        return s.authInvalidCredentials;
      case 'email_not_confirmed':
        return s.authEmailNotConfirmed;
      case 'user_already_exists':
      case 'email_exists':
        return s.authAccountExists;
      case 'weak_password':
        return s.authWeakPassword;
      case 'same_password':
        return s.authSamePassword;
      case 'otp_expired':
        return s.authCodeInvalid;
      case 'email_address_invalid':
        return s.authInvalidEmail;
      case 'over_email_send_rate_limit':
      case 'over_request_rate_limit':
        return s.authTooManyAttempts;
    }
    if (error.statusCode == '429') return s.authTooManyAttempts;
  }
  return s.authGenericError;
}

/// For a rejected 6-digit code. Network trouble and rate limits keep their own
/// message; any other refusal means the code was wrong or stale, whatever
/// error code the server picked.
String authCodeErrorMessage(AppStrings s, Object error) {
  final general = authErrorMessage(s, error);
  if (general == s.authNetworkError || general == s.authTooManyAttempts) {
    return general;
  }
  return error is AuthException ? s.authCodeInvalid : general;
}

/// The royal blue band with the emblem and name that tops every auth screen.
///
/// The language switch sits in its top corner so someone who cannot read the
/// current language can still find it before typing anything.
class AuthHeader extends StatelessWidget {
  /// Shows a back arrow, for screens pushed on top of the login screen.
  final bool showBack;

  /// A shorter band, for forms with more fields.
  final bool compact;

  const AuthHeader({super.key, this.showBack = false, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final topInset = MediaQuery.of(context).padding.top;
    final height = compact
        ? (size.height * 0.30).clamp(210.0, 260.0)
        : (size.height * 0.38).clamp(240.0, 320.0);
    final logoSize = compact ? 72.0 : 86.0;

    return SizedBox(
      height: height,
      width: double.infinity,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Subtle ambient background circles
          Positioned(
            top: -50,
            right: -30,
            child: _circle(220, 0.05),
          ),
          Positioned(
            bottom: 20,
            left: -40,
            child: _circle(160, 0.04),
          ),
          Padding(
            padding: EdgeInsets.only(top: topInset),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: logoSize,
                  height: logoSize,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFFF0EEE9),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.15),
                        blurRadius: 16,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Image.asset(
                      'assets/images/1000021944.png',
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
                SizedBox(height: compact ? 10 : 14),
                Text(
                  'Probashi Guard',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: compact ? 22 : 26,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.4,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'VERIFY  •  PROTECT  •  SEND',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.8),
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 2.0,
                  ),
                ),
                SizedBox(height: compact ? 20 : 28),
              ],
            ),
          ),
          if (showBack)
            Positioned(
              top: topInset + 4,
              left: 4,
              child: IconButton(
                icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                tooltip: MaterialLocalizations.of(context).backButtonTooltip,
                onPressed: () => Navigator.of(context).maybePop(),
              ),
            ),
          Positioned(
            top: topInset + 12,
            right: 16,
            child: const LanguageToggleSwitch(onDarkSurface: true, compact: true),
          ),
        ],
      ),
    );
  }

  Widget _circle(double size, double alpha) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white.withValues(alpha: alpha),
      ),
    );
  }
}

/// [AuthHeader] above a white rounded sheet holding the form.
class AuthScaffold extends StatelessWidget {
  final List<Widget> children;
  final bool showBack;
  final bool compactHeader;

  const AuthScaffold({
    super.key,
    required this.children,
    this.showBack = false,
    this.compactHeader = false,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.royalBlue,
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            AuthHeader(showBack: showBack, compact: compactHeader),
            Expanded(
              child: Container(
                width: double.infinity,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(32),
                    topRight: Radius.circular(32),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Color(0x1A000000),
                      blurRadius: 20,
                      offset: Offset(0, -4),
                    ),
                  ],
                ),
                child: SingleChildScrollView(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: children,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The large title and grey subtitle at the top of each form.
class AuthTitle extends StatelessWidget {
  final String title;
  final String subtitle;

  const AuthTitle({super.key, required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w800,
            color: AppColors.ink,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: TextStyle(
            fontSize: 14,
            color: AppColors.ink.withValues(alpha: 0.6),
          ),
        ),
      ],
    );
  }
}

/// A labelled input. With [obscurable] it hides its text and shows an eye
/// button to reveal it.
class AuthTextField extends StatefulWidget {
  final String label;
  final String hint;
  final IconData icon;
  final TextEditingController controller;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final Iterable<String>? autofillHints;
  final bool obscurable;
  final ValueChanged<String>? onSubmitted;
  final List<TextInputFormatter>? inputFormatters;

  const AuthTextField({
    super.key,
    required this.label,
    required this.hint,
    required this.icon,
    required this.controller,
    this.keyboardType,
    this.textInputAction,
    this.autofillHints,
    this.obscurable = false,
    this.onSubmitted,
    this.inputFormatters,
  });

  @override
  State<AuthTextField> createState() => _AuthTextFieldState();
}

class _AuthTextFieldState extends State<AuthTextField> {
  bool _obscured = true;

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final iconColor = AppColors.ink.withValues(alpha: 0.45);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.label,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: AppColors.ink,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: widget.controller,
          keyboardType: widget.keyboardType,
          textInputAction: widget.textInputAction,
          autofillHints: widget.autofillHints,
          obscureText: widget.obscurable && _obscured,
          autocorrect: !widget.obscurable,
          enableSuggestions: !widget.obscurable,
          onSubmitted: widget.onSubmitted,
          inputFormatters: widget.inputFormatters,
          decoration: authInputDecoration(
            hint: widget.hint,
            prefixIcon: Icon(widget.icon, size: 20, color: iconColor),
            suffixIcon: widget.obscurable
                ? IconButton(
                    icon: Icon(
                      _obscured
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                      size: 20,
                      color: iconColor,
                    ),
                    tooltip:
                        _obscured ? s.authShowPassword : s.authHidePassword,
                    onPressed: () => setState(() => _obscured = !_obscured),
                  )
                : null,
          ),
        ),
      ],
    );
  }
}

InputDecoration authInputDecoration({
  String? hint,
  Widget? prefixIcon,
  Widget? suffixIcon,
}) {
  OutlineInputBorder border(Color color, [double width = 1]) =>
      OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: color, width: width),
      );

  return InputDecoration(
    hintText: hint,
    hintStyle: TextStyle(
      fontSize: 14,
      color: AppColors.ink.withValues(alpha: 0.35),
    ),
    prefixIcon: prefixIcon,
    suffixIcon: suffixIcon,
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    filled: true,
    fillColor: const Color(0xFFF9FAFB),
    border: border(const Color(0xFFE5E7EB)),
    enabledBorder: border(const Color(0xFFE5E7EB)),
    focusedBorder: border(AppColors.royalBlue, 1.5),
  );
}

/// The full-width royal blue call to action. Shows a spinner while [loading].
class AuthPrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool loading;

  const AuthPrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.loading = false,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton(
        onPressed: loading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.royalBlue,
          foregroundColor: Colors.white,
          disabledBackgroundColor: AppColors.royalBlue.withValues(alpha: 0.6),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        child: loading
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: Colors.white,
                ),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Bangla labels run longer than English ones, and large
                  // accessibility text longer still: shrink, never overflow.
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        label,
                        maxLines: 1,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Icon(Icons.arrow_forward_rounded, size: 20),
                ],
              ),
      ),
    );
  }
}

/// An outlined "Log in with …" button for a third-party provider.
class AuthProviderButton extends StatelessWidget {
  final Widget icon;
  final String label;
  final VoidCallback? onPressed;

  const AuthProviderButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.ink,
          side: const BorderSide(color: Color(0xFFE5E7EB)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          backgroundColor: Colors.white,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(width: 22, height: 22, child: Center(child: icon)),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: AppColors.ink,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Six boxes drawn over one invisible field. The field does the real work —
/// keyboard, paste, and the one-time-code autofill some keyboards offer —
/// and the boxes just show what it holds.
class AuthCodeField extends StatefulWidget {
  final TextEditingController controller;
  final FocusNode focusNode;

  /// Called once all digits are in.
  final ValueChanged<String>? onCompleted;
  final bool autofocus;

  const AuthCodeField({
    super.key,
    required this.controller,
    required this.focusNode,
    this.onCompleted,
    this.autofocus = true,
  });

  @override
  State<AuthCodeField> createState() => _AuthCodeFieldState();
}

class _AuthCodeFieldState extends State<AuthCodeField> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_repaint);
    widget.focusNode.addListener(_repaint);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_repaint);
    widget.focusNode.removeListener(_repaint);
    super.dispose();
  }

  void _repaint() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final code = widget.controller.text;
    final activeIndex = code.length.clamp(0, authCodeLength - 1);

    return Semantics(
      label: AppStrings.of(context).authCodeLabel,
      child: SizedBox(
        height: 58,
        child: Stack(
          children: [
            Positioned.fill(
              child: Opacity(
                opacity: 0,
                child: TextField(
                  controller: widget.controller,
                  focusNode: widget.focusNode,
                  autofocus: widget.autofocus,
                  keyboardType: TextInputType.number,
                  maxLength: authCodeLength,
                  showCursor: false,
                  autofillHints: const [AutofillHints.oneTimeCode],
                  inputFormatters: [
                    const BanglaDigitsFormatter(),
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(authCodeLength),
                  ],
                  decoration: const InputDecoration(
                    counterText: '',
                    border: InputBorder.none,
                  ),
                  onChanged: (value) {
                    if (value.length == authCodeLength) {
                      widget.onCompleted?.call(value);
                    }
                  },
                ),
              ),
            ),
            IgnorePointer(
              child: Row(
                children: [
                  for (var i = 0; i < authCodeLength; i++) ...[
                    if (i > 0) const SizedBox(width: 8),
                    Expanded(
                      child: _box(
                        digit: i < code.length ? code[i] : '',
                        active: widget.focusNode.hasFocus && i == activeIndex,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _box({required String digit, required bool active}) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      height: 58,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: active ? AppColors.royalBlue : const Color(0xFFE5E7EB),
          width: active ? 1.5 : 1,
        ),
      ),
      child: Text(
        digit,
        style: const TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w700,
          color: AppColors.ink,
        ),
      ),
    );
  }
}

/// A Bangla keyboard types ০–৯, but a code and a phone number are both checked
/// as 0–9. Rewrites Bangla digits as they are typed or pasted.
class BanglaDigitsFormatter extends TextInputFormatter {
  const BanglaDigitsFormatter();

  static const int _banglaZero = 0x09E6;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final converted = String.fromCharCodes(
      newValue.text.runes.map(
        (c) => c >= _banglaZero && c <= _banglaZero + 9
            ? c - _banglaZero + 0x30
            : c,
      ),
    );
    return newValue.copyWith(text: converted);
  }
}

/// "Resend code", disabled for a minute after each send — Supabase refuses a
/// second email to the same address sooner than that.
class ResendCodeButton extends StatefulWidget {
  /// Sends a new code; returns whether it went out, which restarts the wait.
  final Future<bool> Function() onResend;

  /// How long to wait before another send is offered. The default matches
  /// Supabase's own once-a-minute limit on email codes; an SMS provider may
  /// want longer.
  final int cooldownSeconds;

  const ResendCodeButton({
    super.key,
    required this.onResend,
    this.cooldownSeconds = 60,
  });

  @override
  State<ResendCodeButton> createState() => _ResendCodeButtonState();
}

class _ResendCodeButtonState extends State<ResendCodeButton> {
  Timer? _timer;
  int _secondsLeft = 0;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    // A code was sent just before this button appeared.
    _startCooldown();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startCooldown() {
    _timer?.cancel();
    _secondsLeft = widget.cooldownSeconds;
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_secondsLeft <= 1) timer.cancel();
      setState(() => _secondsLeft--);
    });
  }

  Future<void> _resend() async {
    setState(() => _sending = true);
    final sent = await widget.onResend();
    if (!mounted) return;
    setState(() {
      _sending = false;
      if (sent) _startCooldown();
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final waiting = _secondsLeft > 0;
    return TextButton(
      onPressed: waiting || _sending ? null : _resend,
      child: Text(
        waiting ? s.authResendIn(_secondsLeft) : s.authResendCode,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: waiting
              ? AppColors.ink.withValues(alpha: 0.45)
              : AppColors.royalBlue,
        ),
      ),
    );
  }
}

/// "Don't have an account? Register" and its mirror on the register screen.
class AuthSwitchPrompt extends StatelessWidget {
  final String prompt;
  final String action;
  final VoidCallback onTap;

  const AuthSwitchPrompt({
    super.key,
    required this.prompt,
    required this.action,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            prompt,
            style: TextStyle(
              fontSize: 13,
              color: AppColors.ink.withValues(alpha: 0.6),
            ),
          ),
          InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(6),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
              child: Text(
                action,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.royalBlue,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
