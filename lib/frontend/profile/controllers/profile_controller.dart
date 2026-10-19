import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../l10n/language_controller.dart';
import '../../crChecker/controllers/checklist_controller.dart';

/// State for the profile and menu.
///
/// The name, phone number and biometric switch are saved on the device so they
/// survive closing the app. Protection progress is not stored here: it reads
/// straight through to [ChecklistController], so the profile banner can never
/// disagree with the checklist.
class ProfileController extends ChangeNotifier {
  ProfileController._() {
    // The banner shows checklist progress, so repaint when it changes.
    ChecklistController.instance.addListener(notifyListeners);
  }
  static final ProfileController instance = ProfileController._();

  static const String _nameKey = 'profile_user_name';
  static const String _phoneKey = 'profile_phone_number';
  static const String _biometricKey = 'profile_biometric_enabled';

  static const String _defaultName = 'Guest User';
  static const String _defaultPhone = '+880 1XXX-XXXXXX';

  // TODO(backend): replace these defaults with the logged-in user.
  String _userName = _defaultName;
  String _phoneNumber = _defaultPhone;

  bool _biometricEnabled = false;

  String appVersion = '1.0.0';

  String get userName => _userName;
  String get phoneNumber => _phoneNumber;

  /// Language lives in [LanguageController] — it is app-wide and persisted —
  /// so these just read through to it and there is only one source of truth.
  String get languageCode => LanguageController.instance.languageCode;
  bool get isBangla => LanguageController.instance.isBangla;
  bool get biometricEnabled => _biometricEnabled;
  int get checklistCompleted => ChecklistController.instance.completed;
  int get checklistTotal => ChecklistController.instance.total;

  /// Restores the saved profile. Call once before `runApp`; a failure is not
  /// fatal, the profile just opens with its defaults.
  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _userName = prefs.getString(_nameKey) ?? _userName;
      _phoneNumber = prefs.getString(_phoneKey) ?? _phoneNumber;
      _biometricEnabled = prefs.getBool(_biometricKey) ?? _biometricEnabled;
      notifyListeners();
    } catch (e) {
      debugPrint('[ProfileController] could not read saved profile: $e');
    }
  }

  void updateProfile({String? name, String? phone}) {
    if (name != null) _userName = name;
    if (phone != null) _phoneNumber = phone;
    notifyListeners();
    _persist();
  }

  /// Logout: back to what a new install shows. The language is a choice about
  /// the phone, not the account, so it stays.
  Future<void> reset() async {
    _userName = _defaultName;
    _phoneNumber = _defaultPhone;
    _biometricEnabled = false;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await Future.wait([
        prefs.remove(_nameKey),
        prefs.remove(_phoneKey),
        prefs.remove(_biometricKey),
      ]);
    } catch (e) {
      debugPrint('[ProfileController] could not clear saved profile: $e');
    }
  }

  void setLanguage(String code) {
    if (code == languageCode) return;
    LanguageController.instance.setLanguageCode(code);
    notifyListeners();
  }

  void setBiometric(bool value) {
    if (value == _biometricEnabled) return;
    _biometricEnabled = value;
    notifyListeners();
    _persist();
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_nameKey, _userName);
      await prefs.setString(_phoneKey, _phoneNumber);
      await prefs.setBool(_biometricKey, _biometricEnabled);
    } catch (e) {
      debugPrint('[ProfileController] could not save profile: $e');
    }
  }
}
