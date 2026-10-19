import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../main.dart';
import '../crChecker/controllers/checklist_controller.dart';
import '../documents/repository/document_analysis_repository.dart';
import '../payment/controllers/payment_controller.dart';
import '../profile/controllers/profile_controller.dart';
import 'login_view.dart';
import 'phone_setup_view.dart';

/// How long any single auth-related call to Supabase may take.
const Duration _rpcTimeout = Duration(seconds: 8);

/// The deep link a phone returns to after the Google / GitHub browser sign-in.
///
/// The same URL must be registered in three places, or the browser has nowhere
/// to return to: the Supabase dashboard (Authentication → URL Configuration →
/// Redirect URLs), the Android intent filter in `AndroidManifest.xml`, and
/// `CFBundleURLTypes` in the iOS `Info.plist`.
const String mobileAuthRedirectUrl =
    'io.supabase.probashiguard://login-callback/';

/// Where an OAuth sign-in comes back to on this platform.
///
/// In a browser the custom scheme above is a dead end — Chrome cannot open
/// `io.supabase.probashiguard://`, so consent would succeed and then go
/// nowhere. On web the sign-in instead returns to the page that started it;
/// the app reloads there, Supabase reads the session from the URL during
/// `initialize`, and the splash sees a signed-in account and goes straight in.
///
/// That origin (e.g. `http://localhost:5000/**`) must also be in the Supabase
/// Redirect URLs, or Supabase falls back to the project's Site URL.
String get authRedirectUrl =>
    kIsWeb ? '${Uri.base.origin}/' : mobileAuthRedirectUrl;

/// Null when Supabase never initialised (offline first launch, widget tests).
SupabaseClient? get _client {
  try {
    return Supabase.instance.client;
  } catch (_) {
    return null;
  }
}

/// A real account is signed in, so the splash can skip the login screen.
/// The anonymous session older builds created does not count.
bool hasSignedInAccount() {
  final user = _client?.auth.currentUser;
  return user != null && !user.isAnonymous;
}

/// Call before every sign-in, sign-up or code check. On a phone that used the
/// app before login existed, this reserves its anonymous data so [goToApp] can
/// move it into whichever account the person ends up in.
Future<void> prepareSignIn() => _AnonymousDataClaim.prepare();

/// Leaves the auth screens for good: nothing under the main shell, so the
/// back button cannot return to a login or code screen.
///
/// An account with no phone number stops at [PhoneSetupView] instead: a
/// transfer is addressed to a number, so until one is claimed the person can
/// neither be paid nor send anything.
///
/// [fade] cross-fades in, for the splash, instead of the usual slide.
Future<void> goToApp(BuildContext context, {bool fade = false}) async {
  final navigator = Navigator.of(context);
  // Before the main screen loads, so it sees any rows that moved. Also run
  // from the splash, which retries a claim an earlier login left pending.
  await _AnonymousDataClaim.redeem();
  _adoptAccountName();
  final needsPhone = await _profileNeedsPhone();
  unawaited(PaymentController.instance.reloadAfterSignIn());
  navigator.pushAndRemoveUntil(
    _appRoute(
      needsPhone ? const PhoneSetupView() : const MainNavigationShell(),
      fade: fade,
    ),
    (_) => false,
  );
}

/// Replaces everything with the main shell, once the phone number is settled.
void enterAppShell(BuildContext context) {
  Navigator.of(context).pushAndRemoveUntil(
    _appRoute(const MainNavigationShell()),
    (_) => false,
  );
}

Route<void> _appRoute(Widget page, {bool fade = false}) {
  if (!fade) return MaterialPageRoute<void>(builder: (_) => page);
  return PageRouteBuilder<void>(
    pageBuilder: (_, _, _) => page,
    transitionsBuilder: (_, animation, _, child) =>
        FadeTransition(opacity: animation, child: child),
    transitionDuration: const Duration(milliseconds: 400),
  );
}

/// Whether the signed-in account still has no phone number.
///
/// `ensure_my_wallet()` runs first, so an account created before the P2P
/// migration gets its profile and empty wallet rows before they are read.
///
/// A failure here never blocks a sign-in — the person reaches the app and is
/// asked again next time — so a dropped connection cannot lock anyone out.
Future<bool> _profileNeedsPhone() async {
  final client = _client;
  final user = client?.auth.currentUser;
  if (client == null || user == null || user.isAnonymous) return false;
  try {
    await client.rpc('ensure_my_wallet').timeout(_rpcTimeout);
    final row = await client
        .from('profiles')
        .select('phone')
        .eq('user_id', user.id)
        .maybeSingle()
        .timeout(_rpcTimeout);
    final phone = row?['phone'] as String?;
    return phone == null || phone.trim().isEmpty;
  } catch (e) {
    debugPrint('[auth] could not check the profile phone number: $e');
    return false;
  }
}

/// Ends the session and wipes what the account left on the phone — profile,
/// checklist, wallet mirror and the cached document vault — so the next
/// person to log in on it starts clean. The language choice stays.
Future<void> signOut(BuildContext context) async {
  final navigator = Navigator.of(context);
  try {
    // The session is dropped locally before the server is told, so being
    // offline still logs the person out.
    await _client?.auth.signOut().timeout(const Duration(seconds: 5));
  } catch (e) {
    debugPrint('[auth] server sign-out did not complete: $e');
  }
  await Future.wait([
    ProfileController.instance.reset(),
    ChecklistController.instance.reset(),
    PaymentController.instance.resetForSignOut(),
    DocumentAnalysisRepository.clearDeviceCache(),
    _AnonymousDataClaim.forget(),
  ]);
  navigator.pushAndRemoveUntil(
    MaterialPageRoute(builder: (_) => const LoginView()),
    (_) => false,
  );
}

/// The greeting and menu say "Guest User" until told otherwise. Registration
/// stores `full_name`; Google and GitHub supply `full_name` or `name`.
void _adoptAccountName() {
  final metadata = _client?.auth.currentUser?.userMetadata;
  final name = (metadata?['full_name'] ?? metadata?['name'])?.toString();
  if (name != null && name.trim().isNotEmpty) {
    ProfileController.instance.updateProfile(name: name.trim());
  }
}

/// Client half of `supabase/migrations/20261019120000_claim_anonymous_data.sql`.
///
/// Never blocks a sign-in: if the migration is missing or the network fails,
/// the person still gets in, just without the old anonymous data.
abstract final class _AnonymousDataClaim {
  static const String _tokenKey = 'auth_anonymous_claim_token';
  static const Duration _timeout = Duration(seconds: 5);

  static Future<void> prepare() async {
    final client = _client;
    final user = client?.auth.currentUser;
    if (client == null || user == null || !user.isAnonymous) return;
    try {
      final token = await client.rpc('issue_anonymous_claim').timeout(_timeout);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_tokenKey, token.toString());
    } catch (e) {
      debugPrint('[auth] could not reserve anonymous data: $e');
    }
  }

  static Future<void> redeem() async {
    final client = _client;
    final user = client?.auth.currentUser;
    if (client == null || user == null || user.isAnonymous) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString(_tokenKey);
      if (token == null) return;
      final moved = await client
          .rpc('claim_anonymous_data', params: {'claim_token': token})
          .timeout(_timeout);
      await forget();
      debugPrint('[auth] moved $moved rows from the anonymous session');
    } on PostgrestException catch (e) {
      // The server refused the token; it will not accept it later either.
      debugPrint('[auth] anonymous data claim refused: ${e.message}');
      await forget();
    } catch (e) {
      // Network trouble: keep the token and try again at the next sign-in.
      debugPrint('[auth] anonymous data claim failed: $e');
    }
  }

  static Future<void> forget() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_tokenKey);
    } catch (e) {
      debugPrint('[auth] could not clear the anonymous data claim: $e');
    }
  }
}
