import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'phone_verifier.dart';

/// The verifier to use when the caller has not supplied one.
///
/// `main()` only initialises Firebase when its config files are present, so an
/// empty [Firebase.apps] means verification is not available and the screen
/// should say so rather than hang waiting for an SMS that cannot be sent.
/// Widget tests land here too, where no plugin is registered.
PhoneVerifier defaultPhoneVerifier() {
  try {
    if (Firebase.apps.isEmpty) return const UnconfiguredPhoneVerifier();
    return FirebasePhoneVerifier();
  } catch (e) {
    debugPrint('[auth] Firebase unavailable, phone verification is off: $e');
    return const UnconfiguredPhoneVerifier();
  }
}

/// Proves a phone number with Firebase, then has `backend_service` bind it.
///
/// Firebase is used ONLY as proof of the number. It is not this app's identity
/// system — Supabase is — so the Firebase session is signed out again as soon
/// as its ID token has been handed over.
///
/// The binding deliberately goes through `POST /api/auth/bind-phone` rather
/// than an RPC from here. Only the backend can check the token's RS256
/// signature against Google's rotating keys, and only the backend holds the
/// service-role key that `bind_verified_phone()` requires. A client that could
/// bind a number directly could bind someone else's and intercept their money.
class FirebasePhoneVerifier implements PhoneVerifier {
  /// Resolved on first use, so the direct route never needs the plugin.
  final FirebaseAuth? _firebaseAuthOverride;
  FirebaseAuth get _firebaseAuth =>
      _firebaseAuthOverride ?? FirebaseAuth.instance;

  final http.Client _httpClient;
  final String baseUrl;

  /// Identifies the outstanding SMS; set by [sendCode], spent by [confirmCode].
  String? _verificationId;

  /// Lets a resend skip Firebase's own re-send throttling.
  int? _resendToken;

  /// See [_sendCodeDirect]. Debug builds only, unless a test says otherwise.
  final bool _direct;

  /// Overrides the Firebase app's API key; tests pass one in.
  final String? _apiKeyOverride;

  /// The direct route's equivalent of [_verificationId].
  String? _directSessionInfo;

  FirebasePhoneVerifier({
    FirebaseAuth? firebaseAuth,
    http.Client? httpClient,
    String? baseUrl,
    bool? directForTestNumbers,
    String? apiKey,
  })  : _firebaseAuthOverride = firebaseAuth,
        _httpClient = httpClient ?? http.Client(),
        baseUrl = baseUrl ?? _defaultBaseUrl,
        _direct = directForTestNumbers ?? kDebugMode,
        _apiKeyOverride = apiKey;

  static String get _defaultBaseUrl {
    if (kIsWeb) return 'http://localhost:3000';
    try {
      // 10.0.2.2 is the host PC as seen from the Android emulator only.
      if (Platform.isAndroid) return 'http://10.0.2.2:3000';
    } catch (_) {}
    return 'http://localhost:3000';
  }

  /// The browser equivalent of [_verificationId]: web has no
  /// `verifyPhoneNumber` (it throws UnimplementedError there) and hands back a
  /// ConfirmationResult from `signInWithPhoneNumber` instead.
  ConfirmationResult? _webConfirmation;

  bool _testSettingsApplied = false;

  /// In debug builds only, skips Firebase's app check (reCAPTCHA on web, Play
  /// Integrity on Android) — which Firebase permits for its *test* phone
  /// numbers alone. That is the whole of the current testing phase, and it
  /// also means a debug build works before the SHA fingerprints are in the
  /// console. A release build never sets it, and a real number would be
  /// refused with it on, so it cannot leak into production by accident.
  Future<void> _applyTestSettings() async {
    if (_testSettingsApplied || !kDebugMode) return;
    _testSettingsApplied = true;
    try {
      await _firebaseAuth.setSettings(appVerificationDisabledForTesting: true);
    } catch (e) {
      debugPrint('[FirebasePhoneVerifier] could not relax test settings: $e');
    }
  }

  @override
  Future<void> sendCode(String phone) async {
    // Firebase wants E.164. A local Bangladeshi number (01712345678) has to
    // carry its country code or Firebase rejects it outright.
    final e164 = _toE164(phone);

    if (_direct) {
      await _sendCodeDirect(e164);
      return;
    }

    await _applyTestSettings();

    if (kIsWeb) {
      try {
        // No verifier passed: firebase_auth_web attaches an invisible
        // reCAPTCHA itself (skipped entirely for test numbers in debug).
        _webConfirmation = await _firebaseAuth.signInWithPhoneNumber(e164);
        return;
      } on FirebaseAuthException catch (e) {
        throw _translate(e);
      } catch (e) {
        throw PhoneVerificationException(
          PhoneVerificationFailure.unknown,
          e.toString(),
        );
      }
    }

    final completer = Completer<void>();

    try {
      await _firebaseAuth.verifyPhoneNumber(
        phoneNumber: e164,
        forceResendingToken: _resendToken,
        // On Android the SMS can be read automatically, which fires
        // verificationCompleted instead of codeSent. The credential is kept so
        // confirmCode() can use it, but the screen still asks for the digits —
        // auto-filling the boxes from here would race the UI.
        verificationCompleted: (PhoneAuthCredential credential) {
          _autoCredential = credential;
        },
        verificationFailed: (FirebaseAuthException e) {
          if (!completer.isCompleted) {
            completer.completeError(_translate(e));
          }
        },
        codeSent: (String verificationId, int? resendToken) {
          _verificationId = verificationId;
          _resendToken = resendToken;
          if (!completer.isCompleted) completer.complete();
        },
        codeAutoRetrievalTimeout: (String verificationId) {
          // The window for reading the SMS automatically closed; the code
          // itself is still valid and typed by hand.
          _verificationId = verificationId;
          if (!completer.isCompleted) completer.complete();
        },
      );
      await completer.future;
    } on FirebaseAuthException catch (e) {
      throw _translate(e);
    } on PhoneVerificationException {
      rethrow;
    } catch (e) {
      throw PhoneVerificationException(
        PhoneVerificationFailure.unknown,
        e.toString(),
      );
    }
  }

  /// Set when Android reads the SMS by itself before the person types it.
  PhoneAuthCredential? _autoCredential;

  @override
  Future<void> confirmCode(String code) async {
    final sessionInfo = _directSessionInfo;
    if (sessionInfo != null) {
      final idToken = await _confirmCodeDirect(sessionInfo, code);
      await _bindOnServer(idToken);
      _directSessionInfo = null;
      return;
    }

    final verificationId = _verificationId;
    final webConfirmation = _webConfirmation;
    if (verificationId == null &&
        _autoCredential == null &&
        webConfirmation == null) {
      throw const PhoneVerificationException(
        PhoneVerificationFailure.unknown,
        'confirmCode called before sendCode',
      );
    }

    String idToken;
    try {
      // Signing in is what makes Firebase mint a token carrying phone_number.
      final UserCredential result;
      if (webConfirmation != null) {
        result = await webConfirmation.confirm(code);
      } else {
        final credential = _autoCredential ??
            PhoneAuthProvider.credential(
              verificationId: verificationId!,
              smsCode: code,
            );
        result = await _firebaseAuth.signInWithCredential(credential);
      }
      final token = await result.user?.getIdToken();
      if (token == null || token.isEmpty) {
        throw const PhoneVerificationException(PhoneVerificationFailure.unknown,
            'Firebase returned no ID token');
      }
      idToken = token;
    } on FirebaseAuthException catch (e) {
      throw _translate(e);
    } finally {
      // Whatever happened, do not leave a Firebase session lying about: it is
      // not this app's identity and a stale one only causes confusion later.
      unawaited(_firebaseAuth.signOut().catchError((Object e) {
        debugPrint('[FirebasePhoneVerifier] Firebase sign-out failed: $e');
      }));
      _autoCredential = null;
    }

    await _bindOnServer(idToken);

    // Spent: a second confirm must start from a fresh SMS.
    _verificationId = null;
    _resendToken = null;
    _webConfirmation = null;
  }

  static const _identityToolkit =
      'https://identitytoolkit.googleapis.com/v1/accounts';

  String get _apiKey => _apiKeyOverride ?? Firebase.app().options.apiKey;

  /// The test-number route: Firebase Auth's own REST API, with no SDK, no
  /// reCAPTCHA and no Play Integrity in the way.
  ///
  /// For a number listed under "Phone numbers for testing" in the console,
  /// Firebase skips the app check and sends nothing. It then accepts that
  /// number's fixed code, and nothing else, in [_confirmCodeDirect], and
  /// mints a normal ID token. That token is just as signed as one from a real
  /// SMS, so the backend still verifies it with no special case. Firebase
  /// itself does the matching against the console list, so there is no list
  /// of test numbers in this app to keep in step.
  ///
  /// A real number is refused here (no valid reCAPTCHA token, and real SMS
  /// needs billing), so this route cannot send or skip a real verification.
  /// Debug builds only: release builds go through the SDK.
  Future<void> _sendCodeDirect(String e164) async {
    _directSessionInfo = null;
    final body = await _postIdentityToolkit('sendVerificationCode', {
      'phoneNumber': e164,
      // Required by the API, and only ever accepted for console test numbers.
      'recaptchaToken': 'probashi-guard-test-number',
    });
    final sessionInfo = body['sessionInfo'];
    if (sessionInfo is! String || sessionInfo.isEmpty) {
      throw const PhoneVerificationException(
        PhoneVerificationFailure.unknown,
        'sendVerificationCode returned no sessionInfo',
      );
    }
    _directSessionInfo = sessionInfo;
  }

  Future<String> _confirmCodeDirect(String sessionInfo, String code) async {
    final body = await _postIdentityToolkit('signInWithPhoneNumber', {
      'sessionInfo': sessionInfo,
      'code': code,
    });
    final idToken = body['idToken'];
    if (idToken is! String || idToken.isEmpty) {
      throw const PhoneVerificationException(
        PhoneVerificationFailure.unknown,
        'signInWithPhoneNumber returned no idToken',
      );
    }
    return idToken;
  }

  Future<Map<String, dynamic>> _postIdentityToolkit(
    String method,
    Map<String, String> payload,
  ) async {
    http.Response response;
    try {
      response = await _httpClient
          .post(
            Uri.parse('$_identityToolkit:$method?key=$_apiKey'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 15));
    } on TimeoutException {
      throw const PhoneVerificationException(PhoneVerificationFailure.network);
    } catch (e) {
      throw PhoneVerificationException(
        PhoneVerificationFailure.network,
        e.toString(),
      );
    }

    Map<String, dynamic> body;
    try {
      body = jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {
      body = const {};
    }

    if (response.statusCode != 200) {
      final error = body['error'];
      final message =
          error is Map ? (error['message']?.toString() ?? '') : response.body;
      throw _translateRest(message);
    }
    return body;
  }

  /// Firebase's REST errors are "CODE" or "CODE : explanation".
  PhoneVerificationException _translateRest(String message) {
    final code = message.split(RegExp(r'[ :]')).first;
    switch (code) {
      case 'INVALID_CODE':
      case 'SESSION_EXPIRED':
      case 'INVALID_SESSION_INFO':
      case 'MISSING_CODE':
        return PhoneVerificationException(
          PhoneVerificationFailure.wrongCode,
          message,
        );
      case 'INVALID_PHONE_NUMBER':
      case 'MISSING_PHONE_NUMBER':
        return PhoneVerificationException(
          PhoneVerificationFailure.invalidNumber,
          message,
        );
      case 'TOO_MANY_ATTEMPTS_TRY_LATER':
      case 'QUOTA_EXCEEDED':
        return PhoneVerificationException(
          PhoneVerificationFailure.tooManyRequests,
          message,
        );
      // A real (non-test) number: no SMS without billing, and no reCAPTCHA
      // on this route. Or the number's region is not in the allow-list.
      case 'BILLING_NOT_ENABLED':
      case 'INVALID_RECAPTCHA_TOKEN':
      case 'CAPTCHA_CHECK_FAILED':
      case 'OPERATION_NOT_ALLOWED':
        return PhoneVerificationException(
          PhoneVerificationFailure.smsUnavailable,
          message,
        );
      default:
        return PhoneVerificationException(
          PhoneVerificationFailure.unknown,
          message,
        );
    }
  }

  /// Hands the proof to the backend, which verifies it and writes the binding.
  Future<void> _bindOnServer(String firebaseIdToken) async {
    final supabaseToken =
        Supabase.instance.client.auth.currentSession?.accessToken;
    if (supabaseToken == null) {
      throw const PhoneVerificationException(
        PhoneVerificationFailure.unknown,
        'not signed in to Supabase',
      );
    }

    http.Response response;
    try {
      response = await _httpClient
          .post(
            Uri.parse('$baseUrl/api/auth/bind-phone'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $supabaseToken',
            },
            body: jsonEncode({'firebaseIdToken': firebaseIdToken}),
          )
          .timeout(const Duration(seconds: 15));
    } on TimeoutException {
      throw const PhoneVerificationException(PhoneVerificationFailure.network);
    } catch (e) {
      throw PhoneVerificationException(
        PhoneVerificationFailure.network,
        e.toString(),
      );
    }

    if (response.statusCode == 409) {
      throw const PhoneVerificationException(
        PhoneVerificationFailure.numberTaken,
      );
    }
    if (response.statusCode != 200) {
      throw PhoneVerificationException(
        PhoneVerificationFailure.unknown,
        'bind-phone returned ${response.statusCode}: ${response.body}',
      );
    }
  }

  /// Bangladeshi numbers are typed locally (01712345678) far more often than
  /// in full. Anything already carrying a + is left alone.
  String _toE164(String phone) {
    final digits = phone.replaceAll(RegExp(r'[^0-9+]'), '');
    if (digits.startsWith('+')) return digits;
    if (digits.startsWith('01') && digits.length == 11) {
      return '+880${digits.substring(1)}';
    }
    if (digits.startsWith('880')) return '+$digits';
    return '+$digits';
  }

  PhoneVerificationException _translate(FirebaseAuthException e) {
    switch (e.code) {
      case 'invalid-phone-number':
        return const PhoneVerificationException(
          PhoneVerificationFailure.invalidNumber,
        );
      case 'invalid-verification-code':
      case 'session-expired':
        return const PhoneVerificationException(
          PhoneVerificationFailure.wrongCode,
        );
      case 'too-many-requests':
      case 'quota-exceeded':
        return const PhoneVerificationException(
          PhoneVerificationFailure.tooManyRequests,
        );
      case 'network-request-failed':
        return const PhoneVerificationException(
          PhoneVerificationFailure.network,
        );
      case 'credential-already-in-use':
      case 'account-exists-with-different-credential':
        return const PhoneVerificationException(
          PhoneVerificationFailure.numberTaken,
        );
      case 'billing-not-enabled':
        return PhoneVerificationException(
          PhoneVerificationFailure.smsUnavailable,
          e.message,
        );
      // Also what Firebase says when the number's country is outside the SMS
      // region policy, which is not a configuration gap in this app.
      case 'operation-not-allowed'
          when (e.message ?? '').toLowerCase().contains('region'):
        return PhoneVerificationException(
          PhoneVerificationFailure.smsUnavailable,
          e.message,
        );
      // Thrown when the app was never registered, or google-services.json is
      // absent, which is the state until Firebase is configured.
      case 'app-not-authorized':
      case 'operation-not-allowed':
      case 'unknown':
        return PhoneVerificationException(
          PhoneVerificationFailure.notConfigured,
          e.message,
        );
      default:
        return PhoneVerificationException(
          PhoneVerificationFailure.unknown,
          '${e.code}: ${e.message}',
        );
    }
  }
}
