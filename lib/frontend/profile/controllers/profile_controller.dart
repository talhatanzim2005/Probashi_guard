import 'package:flutter/foundation.dart';

/// Front-end-only state for the profile and menu.
///
/// Everything here is local placeholder data. When the backend is ready,
/// load the real values in [load] and save changes in the setters; no
/// screen needs to change because they all listen to this controller.
class ProfileController extends ChangeNotifier {
  ProfileController._();
  static final ProfileController instance = ProfileController._();

  // TODO(backend): replace these placeholders with the logged-in user.
  String _userName = 'Guest User';
  String _phoneNumber = '+880 1XXX-XXXXXX';

  // TODO(backend): persist (e.g. SharedPreferences) so it survives restarts.
  String _languageCode = 'en';
  bool _biometricEnabled = false;

  // TODO: feed these from the home checklist once it has a shared state.
  int _checklistCompleted = 3;
  int _checklistTotal = 8;

  String appVersion = '1.0.0';

  String get userName => _userName;
  String get phoneNumber => _phoneNumber;
  String get languageCode => _languageCode;
  bool get isBangla => _languageCode == 'bn';
  bool get biometricEnabled => _biometricEnabled;
  int get checklistCompleted => _checklistCompleted;
  int get checklistTotal => _checklistTotal;

  /// Call after login / app start once the backend exists.
  Future<void> load() async {
    // TODO(backend): fetch profile, then notifyListeners().
  }

  void updateProfile({String? name, String? phone}) {
    if (name != null) _userName = name;
    if (phone != null) _phoneNumber = phone;
    notifyListeners();
  }

  void setLanguage(String code) {
    if (code == _languageCode) return;
    _languageCode = code;
    notifyListeners();
  }

  void setBiometric(bool value) {
    if (value == _biometricEnabled) return;
    _biometricEnabled = value;
    notifyListeners();
  }

  void updateChecklist({required int completed, required int total}) {
    _checklistCompleted = completed;
    _checklistTotal = total;
    notifyListeners();
  }
}
