import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:probashi_guard/frontend/auth/auth_widgets.dart';
import 'package:probashi_guard/l10n/app_strings.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// TC-AUTH: the pure rules behind the login, sign-up, code and reset screens.
/// (The screens themselves are driven in auth_flow_test.dart.)
void main() {
  group('isValidEmail', () {
    test('accepts ordinary addresses, including the seeded test account', () {
      for (final ok in [
        'sender@example.com',
        'sender@gmail.com',
        'a.b+tag@sub.example.co.uk',
        'x@y.z',
      ]) {
        expect(isValidEmail(ok), isTrue, reason: ok);
      }
    });

    test('refuses what cannot be an address', () {
      for (final bad in [
        '',
        ' ',
        'plain',
        '@example.com',
        'a@',
        'a@b',
        'a b@example.com',
        'a@@example.com',
        'a@example .com',
        'a@exa mple.com',
      ]) {
        expect(isValidEmail(bad), isFalse, reason: '"$bad"');
      }
    });

    test('is applied to trimmed input by the screens, not here', () {
      // The screens call .trim() first; the function itself is strict about spaces.
      expect(isValidEmail(' sender@example.com'), isFalse);
      expect(isValidEmail('sender@example.com '), isFalse);
    });
  });

  test('the length rules match what Supabase enforces', () {
    expect(minPasswordLength, 6, reason: 'Supabase\'s default minimum');
    expect(authCodeLength, 6, reason: 'the emailed code, and the Firebase test code 123456');
    expect('123456'.length, authCodeLength);
  });

  group('BanglaDigitsFormatter', () {
    const formatter = BanglaDigitsFormatter();
    String run(String typed) => formatter
        .formatEditUpdate(TextEditingValue.empty, TextEditingValue(text: typed))
        .text;

    test('turns Bengali digits into ASCII so a Bangla keyboard can enter a code', () {
      expect(run('০১২৩৪৫৬৭৮৯'), '0123456789');
      expect(run('১২৩৪৫৬'), '123456');
    });

    test('leaves ASCII digits, letters and an empty string alone', () {
      expect(run('123456'), '123456');
      expect(run('ab১'), 'ab1');
      expect(run(''), '');
    });
  });

  group('authErrorMessage', () {
    const s = AppStrings('en');
    const bn = AppStrings('bn');

    String msg(Object e) => authErrorMessage(s, e);

    test('each stable GoTrue error code maps to its own message', () {
      final cases = <String, String>{
        'invalid_credentials': s.authInvalidCredentials,
        'email_not_confirmed': s.authEmailNotConfirmed,
        'user_already_exists': s.authAccountExists,
        'email_exists': s.authAccountExists,
        'weak_password': s.authWeakPassword,
        'same_password': s.authSamePassword,
        'otp_expired': s.authCodeInvalid,
        'email_address_invalid': s.authInvalidEmail,
        'over_email_send_rate_limit': s.authTooManyAttempts,
        'over_request_rate_limit': s.authTooManyAttempts,
      };
      cases.forEach((code, expected) {
        expect(msg(AuthException('server words', code: code)), expected, reason: code);
      });
    });

    test('a 429 with no known code is still "too many attempts"', () {
      expect(msg(const AuthException('slow down', statusCode: '429')), s.authTooManyAttempts);
    });

    test('network trouble and timeouts get the network message', () {
      expect(msg(TimeoutException('t')), s.authNetworkError);
      expect(msg(AuthRetryableFetchException(message: 'offline')), s.authNetworkError);
    });

    test('anything unrecognised is generic and never shows the server\'s own words', () {
      for (final e in <Object>[
        const AuthException('JWT expired: eyJhbGciOi...', code: 'something_new'),
        StateError('boom'),
        'a string',
      ]) {
        final shown = msg(e);
        expect(shown, s.authGenericError);
        expect(shown, isNot(contains('JWT')));
      }
    });

    test('every message exists in Bangla too, and differs from the English', () {
      for (final pick in <String Function(AppStrings)>[
        (x) => x.authInvalidCredentials,
        (x) => x.authEmailNotConfirmed,
        (x) => x.authAccountExists,
        (x) => x.authWeakPassword,
        (x) => x.authSamePassword,
        (x) => x.authCodeInvalid,
        (x) => x.authInvalidEmail,
        (x) => x.authTooManyAttempts,
        (x) => x.authNetworkError,
        (x) => x.authGenericError,
      ]) {
        expect(pick(bn).trim(), isNotEmpty);
        expect(pick(bn), isNot(pick(s)));
      }
    });
  });

  group('authCodeErrorMessage (a rejected 6-digit code)', () {
    const s = AppStrings('en');

    test('any server refusal of a code reads "wrong or expired code"', () {
      for (final code in ['otp_expired', 'validation_failed', 'unexpected_failure', 'invalid_credentials']) {
        expect(authCodeErrorMessage(s, AuthException('x', code: code)), s.authCodeInvalid, reason: code);
      }
    });

    test('but rate limits and a dead network keep their own message', () {
      expect(authCodeErrorMessage(s, const AuthException('x', code: 'over_request_rate_limit')), s.authTooManyAttempts);
      expect(authCodeErrorMessage(s, TimeoutException('t')), s.authNetworkError);
    });

    test('a non-auth failure is generic, not "wrong code"', () {
      expect(authCodeErrorMessage(s, StateError('x')), s.authGenericError);
    });
  });
}
