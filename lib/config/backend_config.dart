import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';

/// Where backend_service is, in one place.
///
/// Four repositories used to carry their own copy of this guess, and every one
/// hard-wired `localhost` / `10.0.2.2`, which only reach the dev PC from a
/// browser or the Android emulator. A real phone needs the PC's address:
///
///   flutter run --dart-define=BACKEND_URL=http://192.168.0.10:3000
///
/// (or the deployed https URL in a release build). Without the define the old
/// defaults still apply, so `flutter run -d chrome` needs nothing.
class BackendConfig {
  const BackendConfig._();

  static const String _configured = String.fromEnvironment('BACKEND_URL');

  /// No trailing slash, so callers can append `/api/...`.
  static String get baseUrl {
    if (_configured.isNotEmpty) {
      return _configured.endsWith('/')
          ? _configured.substring(0, _configured.length - 1)
          : _configured;
    }
    if (kIsWeb) return 'http://localhost:3000';
    try {
      // 10.0.2.2 is the host PC as seen from the Android emulator only.
      if (Platform.isAndroid) return 'http://10.0.2.2:3000';
    } catch (_) {}
    return 'http://localhost:3000';
  }
}
