import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/app_strings.dart';
import '../../theme/app_colors.dart';
import '../profile/controllers/profile_controller.dart';
import 'auth_session.dart';
import 'auth_widgets.dart';
import 'firebase_phone_verifier.dart';
import 'phone_country.dart';
import 'phone_verifier.dart';

/// Claims — and proves — the phone number this account is addressed by.
///
/// A transfer is sent to a number, not an email: `p2p_transfer` resolves both
/// sender and recipient through `profiles.phone`, and only counts a number
/// that has been verified. An unverified account can neither pay nor be paid,
/// which is why this stands between signing in and the app.
///
/// The number and the code are both on screen at once, typed on the phone's
/// own numeric keyboard. Both fields filter to the digits 0-9 (a Bangla
/// keyboard's ০-৯ are converted), the number is capped at its country's length
/// (11 digits in Bangladesh), and the code submits itself on its last digit.
/// Verifying without having sent a code first sends one and checks it in a
/// single step, which is how a Firebase test number and its fixed code are
/// matched. Test numbers send no SMS, so they cost nothing; see
/// [FirebasePhoneVerifier.allowRealSms] for what it takes to send a real one.
///
/// It is skippable on purpose. Someone with no signal, or a number the SMS
/// provider will not reach, still gets into the vault, the notices and the
/// scanner — they just cannot move money. Blocking the whole app on an SMS
/// that may never arrive would be worse than the limitation.
class PhoneSetupView extends StatefulWidget {
  /// Swapped for a fake in tests. Left null, the screen picks Firebase when it
  /// is configured and the do-nothing verifier when it is not.
  final PhoneVerifier? verifier;

  /// Opened from Profile > Update Phone Number rather than straight after
  /// login: a back arrow instead of Skip / Log Out, and a verified number
  /// returns to the profile instead of rebuilding the whole app.
  final bool openedFromProfile;

  const PhoneSetupView({
    super.key,
    this.verifier,
    this.openedFromProfile = false,
  });

  @override
  State<PhoneSetupView> createState() => _PhoneSetupViewState();
}

class _PhoneSetupViewState extends State<PhoneSetupView> {
  /// SMS is slower to arrive than email, and providers rate-limit sends
  /// harder, so the wait before another send is offered is longer than the
  /// email default.
  static const int _resendCooldownSeconds = 120;

  late final PhoneVerifier _verifier = widget.verifier ?? defaultPhoneVerifier();

  final _phoneController = TextEditingController();
  final _codeController = TextEditingController();

  PhoneCountry _country = PhoneCountry.bangladesh;
  final _phoneFocus = FocusNode();
  final _codeFocus = FocusNode();
  bool _isBusy = false;

  /// The E.164 number the outstanding code was sent to; null before any send.
  String? _sentTo;

  @override
  void dispose() {
    _phoneController.dispose();
    _codeController.dispose();
    _phoneFocus.dispose();
    _codeFocus.dispose();
    super.dispose();
  }

  String? get _e164 => _country.toE164(_phoneController.text);

  /// +8801700000000 as "+880 1700000000", the way the profile shows it.
  String _displayNumber(String e164) {
    final dial = '+${_country.dialCode}';
    return e164.startsWith(dial)
        ? '$dial ${e164.substring(dial.length)}'
        : e164;
  }

  /// True once a code is out for the number currently on screen.
  bool get _codeIsOutForThisNumber => _sentTo != null && _sentTo == _e164;

  String _failureMessage(AppStrings s, Object error) {
    // The person sees a friendly line; the terminal gets the provider's actual
    // reason. Without this, a Firebase SMS region block and a missing config
    // look identical on screen and nothing says which one happened.
    debugPrint('[PhoneSetupView] verification failed: $error');
    if (error is! PhoneVerificationException) return s.authGenericError;
    switch (error.reason) {
      case PhoneVerificationFailure.invalidNumber:
        return s.authPhoneInvalid;
      case PhoneVerificationFailure.wrongCode:
        return s.authPhoneCodeWrong;
      case PhoneVerificationFailure.numberTaken:
        return s.authPhoneTaken;
      case PhoneVerificationFailure.tooManyRequests:
        return s.authPhoneTooManyRequests;
      case PhoneVerificationFailure.notConfigured:
        return s.authPhoneNotConfigured;
      case PhoneVerificationFailure.smsUnavailable:
        return s.authPhoneSmsUnavailable;
      case PhoneVerificationFailure.network:
        return s.authNetworkError;
      case PhoneVerificationFailure.unknown:
        return s.authGenericError;
    }
  }

  /// The number in E.164, or null after telling the person what is wrong.
  String? _validatedNumber(AppStrings s) {
    final e164 = _e164;
    if (e164 == null) {
      _phoneFocus.requestFocus();
      showAuthMessage(
        context,
        s.authPhoneInvalidLength(_country.lengthLabel, _country.example),
      );
    }
    return e164;
  }

  /// Runs on every change to the number.
  void _onNumberChanged(String _) {
    setState(() {});
    if (_phoneController.text.length == _country.maxDigits && _e164 != null) {
      // A complete number hands the keyboard on to the code.
      _codeFocus.requestFocus();
    }
  }

  void _selectCountry(PhoneCountry country) {
    final digits = _phoneController.text;
    setState(() {
      _country = country;
      // Keep what was typed, but never more than the new country allows.
      if (digits.length > country.maxDigits) {
        _phoneController.text = digits.substring(0, country.maxDigits);
      }
    });
    _phoneFocus.requestFocus();
  }

  Future<void> _sendCode() async {
    if (_isBusy) return;
    final s = AppStrings.of(context);
    final e164 = _validatedNumber(s);
    if (e164 == null) return;

    setState(() => _isBusy = true);
    try {
      await _verifier.sendCode(e164);
      if (!mounted) return;
      setState(() {
        _sentTo = e164;
        _codeController.clear();
      });
      _codeFocus.requestFocus();
      showAuthMessage(context, s.authPhoneCodeSent, isError: false);
    } catch (e) {
      if (mounted) showAuthMessage(context, _failureMessage(s, e));
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<bool> _resend() async {
    final s = AppStrings.of(context);
    final sentTo = _sentTo;
    if (sentTo == null) return false;
    try {
      await _verifier.sendCode(sentTo);
      if (!mounted) return true;
      setState(_codeController.clear);
      showAuthMessage(context, s.authCodeResent, isError: false);
      return true;
    } catch (e) {
      if (mounted) showAuthMessage(context, _failureMessage(s, e));
      return false;
    }
  }

  Future<void> _verify() async {
    if (_isBusy) return;
    final s = AppStrings.of(context);
    final e164 = _validatedNumber(s);
    if (e164 == null) return;

    final code = _codeController.text;
    if (code.length != authCodeLength) {
      _codeFocus.requestFocus();
      showAuthMessage(context, s.authCodeIncomplete);
      return;
    }

    setState(() => _isBusy = true);
    try {
      // Number and code typed together with no send in between: send now,
      // then check the code. For a test number Firebase sends nothing and
      // simply compares the code with the one in the console.
      if (!_codeIsOutForThisNumber) {
        await _verifier.sendCode(e164);
        if (!mounted) return;
        setState(() => _sentTo = e164);
      }
      await _verifier.confirmCode(code);
      if (!mounted) return;
      // The profile header shows this number; it said +880 1XXX-XXXXXX until
      // one was verified.
      ProfileController.instance.updateProfile(phone: _displayNumber(e164));
      showAuthMessage(context, s.authPhoneVerified, isError: false);
      if (widget.openedFromProfile) {
        Navigator.of(context).pop(true);
      } else {
        enterAppShell(context);
      }
    } catch (e) {
      if (!mounted) return;
      setState(_codeController.clear);
      _codeFocus.requestFocus();
      showAuthMessage(context, _failureMessage(s, e));
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);

    return AuthScaffold(
      compactHeader: true,
      showBack: widget.openedFromProfile,
      children: [
        AuthTitle(title: s.authPhoneTitle, subtitle: s.authPhoneSubtitle),
        const SizedBox(height: 20),
        _countryPicker(s),
        const SizedBox(height: 16),
        _numberField(s),
        const SizedBox(height: 12),
        _sendControl(s),
        const SizedBox(height: 16),
        _label(s.authPhoneCodeLabel),
        const SizedBox(height: 8),
        // Six boxes over one invisible field: the phone's numeric keyboard,
        // digits only, the SMS code offered by the keyboard, and onCompleted
        // fires on the sixth digit.
        IgnorePointer(
          ignoring: _isBusy,
          child: AuthCodeField(
            controller: _codeController,
            focusNode: _codeFocus,
            autofocus: false,
            onCompleted: (_) => _verify(),
          ),
        ),
        const SizedBox(height: 24),
        AuthPrimaryButton(
          label: s.authPhoneVerify,
          loading: _isBusy,
          onPressed: _verify,
        ),
        if (!FirebasePhoneVerifier.allowRealSms) ...[
          const SizedBox(height: 10),
          Text(
            s.authPhoneTestModeNote,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 11,
              height: 1.4,
              color: AppColors.royalBlue.withValues(alpha: 0.8),
            ),
          ),
        ],
        // From the profile the back arrow is the way out, and the profile
        // has its own log out.
        if (!widget.openedFromProfile) ...[
          const SizedBox(height: 10),
          _skipButton(s),
        ],
      ],
    );
  }

  Widget _countryPicker(AppStrings s) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label(s.authPhoneCountryLabel),
        const SizedBox(height: 8),
        DropdownButtonFormField<PhoneCountry>(
          initialValue: _country,
          isExpanded: true,
          decoration: authInputDecoration(),
          items: [
            for (final country in PhoneCountry.all)
              DropdownMenuItem(
                value: country,
                child: Text(
                  '${country.flag}  ${s.phoneCountryName(country.iso)}'
                  '  (+${country.dialCode})',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: _isBusy
              ? null
              : (country) {
                  if (country != null) _selectCountry(country);
                },
        ),
      ],
    );
  }

  Widget _phonePrefix() {
    return Padding(
      padding: const EdgeInsets.only(left: 12, right: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.phone_outlined,
            size: 20,
            color: AppColors.ink.withValues(alpha: 0.45),
          ),
          const SizedBox(width: 8),
          Text(
            '+${_country.dialCode}',
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppColors.ink,
            ),
          ),
        ],
      ),
    );
  }

  /// The phone number, on the numeric keyboard. Only 0-9 get in, capped at the
  /// country's length; it opens focused so the keyboard is already up.
  Widget _numberField(AppStrings s) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label(s.authPhoneLabel),
        const SizedBox(height: 8),
        TextField(
          controller: _phoneController,
          focusNode: _phoneFocus,
          autofocus: true,
          readOnly: _isBusy,
          keyboardType: TextInputType.number,
          textInputAction: TextInputAction.next,
          autofillHints: const [AutofillHints.telephoneNumberNational],
          inputFormatters: [
            const BanglaDigitsFormatter(),
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(_country.maxDigits),
          ],
          onChanged: _onNumberChanged,
          onSubmitted: (_) => _codeFocus.requestFocus(),
          style: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.2,
            fontFeatures: [FontFeature.tabularFigures()],
          ),
          decoration: authInputDecoration(
            hint: _country.example,
            prefixIcon: _phonePrefix(),
          ).copyWith(
            helperText: s.authPhoneDigitCount(
              _phoneController.text.length,
              _country.lengthLabel,
            ),
          ),
        ),
      ],
    );
  }

  Widget _sendControl(AppStrings s) {
    if (_codeIsOutForThisNumber) {
      return Row(
        children: [
          const Icon(
            Icons.check_circle_outline,
            size: 18,
            color: AppColors.emeraldGreen,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              s.authPhoneCodeSent,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.emeraldGreen,
              ),
            ),
          ),
          ResendCodeButton(
            onResend: _resend,
            cooldownSeconds: _resendCooldownSeconds,
          ),
        ],
      );
    }
    return SizedBox(
      width: double.infinity,
      height: 46,
      child: OutlinedButton.icon(
        onPressed: _isBusy ? null : _sendCode,
        icon: const Icon(Icons.sms_outlined, size: 18),
        label: Text(
          s.authPhoneSendCode,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.royalBlue,
          side: BorderSide(color: AppColors.royalBlue.withValues(alpha: 0.4)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }

  Widget _label(String text) => Text(
        text,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: AppColors.ink,
        ),
      );

  Widget _skipButton(AppStrings s) => Column(
        children: [
          Center(
            child: TextButton(
              onPressed: _isBusy ? null : () => enterAppShell(context),
              child: Text(
                s.authPhoneSkip,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.ink.withValues(alpha: 0.6),
                ),
              ),
            ),
          ),
          Text(
            s.authPhoneSkipNote,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 11,
              height: 1.4,
              color: AppColors.ink.withValues(alpha: 0.45),
            ),
          ),
          // A saved session skips the login screen at launch and lands here,
          // so this is the way back to login (and from there, sign-up) for
          // someone who wants a different account.
          Center(
            child: TextButton.icon(
              onPressed: _isBusy ? null : () => signOut(context),
              icon: const Icon(Icons.logout_rounded, size: 16),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.crimsonRed,
              ),
              label: Text(
                s.logOut,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      );
}
