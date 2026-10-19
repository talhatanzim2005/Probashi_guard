/// Proving that the person actually holds a phone number.
///
/// The screen talks to this, never to a verification SDK directly, so the
/// Firebase wiring can land without touching the UI — and so widget tests can
/// drive the whole flow with a fake.
library;

/// Why an attempt failed, in terms the screen can turn into a sentence.
///
/// A reason rather than a provider error code: Firebase's codes
/// (`invalid-verification-code`, `too-many-requests`, …) stop here and do not
/// leak into the widget layer.
enum PhoneVerificationFailure {
  /// The number is malformed, or the provider rejected its shape.
  invalidNumber,

  /// Wrong or expired code.
  wrongCode,

  /// Another account has already verified this number.
  numberTaken,

  /// The provider is rate-limiting this device or number.
  tooManyRequests,

  /// No verification provider is wired up yet.
  notConfigured,

  /// The provider is set up but will not text this number — real SMS needs
  /// billing on the Firebase project, or the number's region is not allowed.
  smsUnavailable,

  /// Offline, or the backend could not be reached.
  network,

  unknown,
}

class PhoneVerificationException implements Exception {
  final PhoneVerificationFailure reason;

  /// The underlying message, for the log — never shown to the person.
  final String? detail;

  const PhoneVerificationException(this.reason, [this.detail]);

  @override
  String toString() => 'PhoneVerificationException($reason, $detail)';
}

/// Sends a code to a number, then confirms it and binds it to the account.
///
/// Implementations must only report success from [confirmCode] once the number
/// is bound **server-side**. A client that has merely satisfied Firebase has
/// proven nothing to Probashi Guard: the proof is the Firebase ID token, and
/// only `backend_service` can check its RS256 signature against Google's
/// rotating keys and then call `bind_verified_phone()` with the service-role
/// key. Binding must never be a direct RPC from the app, or the whole flow is
/// bypassable by calling that RPC and skipping the SMS.
abstract interface class PhoneVerifier {
  /// Sends a 6-digit code to [phone] (already normalised to digits and +).
  Future<void> sendCode(String phone);

  /// Confirms [code] and binds the number to the signed-in account.
  Future<void> confirmCode(String code);
}

/// The default until Firebase is configured.
///
/// It fails loudly rather than pretending to send, so the screen can offer to
/// continue unverified instead of leaving someone staring at a code box that
/// no message will ever arrive for.
///
/// Replacing it means adding `firebase_core` + `firebase_auth`, then an
/// implementation that:
///   1. calls `FirebaseAuth.verifyPhoneNumber` and keeps the `verificationId`,
///   2. on confirm, builds a `PhoneAuthProvider.credential` and signs in,
///   3. takes the resulting Firebase ID token and POSTs it, together with the
///      Supabase access token, to `POST /api/auth/bind-phone`,
///   4. returns only once that endpoint reports the number bound.
class UnconfiguredPhoneVerifier implements PhoneVerifier {
  const UnconfiguredPhoneVerifier();

  @override
  Future<void> sendCode(String phone) async => throw const
      PhoneVerificationException(PhoneVerificationFailure.notConfigured);

  @override
  Future<void> confirmCode(String code) async => throw const
      PhoneVerificationException(PhoneVerificationFailure.notConfigured);
}
