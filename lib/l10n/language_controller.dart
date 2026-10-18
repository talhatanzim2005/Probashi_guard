import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The one source of truth for the app's language.
///
/// A [ValueNotifier] rather than a full controller: the only state is which
/// locale is active, and the root of the app listens to it so a change repaints
/// every screen at once — no restart, no per-screen plumbing.
///
/// The choice is written to [SharedPreferences] so it survives app launches.
class LanguageController extends ValueNotifier<Locale> {
  LanguageController._() : super(const Locale(englishCode));

  static final LanguageController instance = LanguageController._();

  static const String banglaCode = 'bn';
  static const String englishCode = 'en';
  static const String _prefsKey = 'app_language_code';

  static const Locale bangla = Locale(banglaCode);
  static const Locale english = Locale(englishCode);

  static const List<Locale> supportedLocales = [bangla, english];

  /// Material, Cupertino and Widgets translations for the supported locales.
  ///
  /// Required: the stock `DefaultMaterialLocalizations` only covers English, so
  /// without these any Material widget that looks up `MaterialLocalizations`
  /// — `Drawer`, tooltips, date pickers — throws once the locale is Bangla.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates = [
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ];

  String get languageCode => value.languageCode;

  bool get isBangla => value.languageCode == banglaCode;

  /// Reads the saved choice. Call once before `runApp`; a failure here is not
  /// fatal, the app just opens in the default language.
  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_prefsKey);
      if (saved == banglaCode || saved == englishCode) {
        value = Locale(saved!);
      }
    } catch (e) {
      debugPrint('[LanguageController] could not read saved language: $e');
    }
  }

  void setLanguageCode(String code) {
    if (code != banglaCode && code != englishCode) return;
    if (code == value.languageCode) return;
    value = Locale(code);
    _persist(code);
  }

  /// One tap flips between the two languages.
  void toggle() {
    setLanguageCode(isBangla ? englishCode : banglaCode);
  }

  Future<void> _persist(String code) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, code);
    } catch (e) {
      // The language still changed for this session; only the memory is lost.
      debugPrint('[LanguageController] could not save language: $e');
    }
  }
}
