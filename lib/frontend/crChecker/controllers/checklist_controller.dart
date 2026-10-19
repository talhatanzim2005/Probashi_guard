import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The one source of truth for the pre-departure checklist.
///
/// The Home card, the checklist screen and the profile banner all read from
/// here, so a tick made anywhere shows everywhere. Every change is written to
/// [SharedPreferences], so progress survives closing the app.
class ChecklistController extends ChangeNotifier {
  ChecklistController._(this._done);

  static final ChecklistController instance = ChecklistController._(
    List<bool>.of(defaultState),
  );

  /// A fresh, unloaded controller, so tests do not share state.
  @visibleForTesting
  ChecklistController.forTesting() : _done = List<bool>.of(defaultState);

  static const int itemCount = 8;
  static const String _prefsKey = 'predeparture_checklist_v1';

  /// What a new install starts with: nothing done. Progress is only ever what
  /// the person has ticked themselves, so a fresh install reads 0/8 and 0%.
  static const List<bool> defaultState = [
    false, false, false, false, false, false, false, false, //
  ];

  final List<bool> _done;

  /// Bumped to ask the Home screen to scroll its checklist card into view.
  final ValueNotifier<int> focusRequests = ValueNotifier<int>(0);

  int get total => _done.length;

  int get completed => _done.where((d) => d).length;

  double get progress => total == 0 ? 0.0 : completed / total;

  bool get isComplete => total > 0 && completed == total;

  bool isDone(int index) => _done[index];

  /// Index of the first unfinished item, or -1 when everything is done.
  int get nextIndex => _done.indexWhere((d) => !d);

  /// Restores the saved ticks. Call once before `runApp`; a failure is not
  /// fatal, the checklist just opens in its default state.
  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_prefsKey);
      if (saved == null || saved.length != itemCount) return;
      if (saved.codeUnits.any((c) => c != 0x30 && c != 0x31)) return;
      for (var i = 0; i < itemCount; i++) {
        _done[i] = saved[i] == '1';
      }
      notifyListeners();
    } catch (e) {
      debugPrint('[ChecklistController] could not read saved progress: $e');
    }
  }

  void toggle(int index) {
    if (index < 0 || index >= _done.length) return;
    _done[index] = !_done[index];
    notifyListeners();
    _persist();
  }

  void requestFocus() => focusRequests.value++;

  /// Logout: the next person on this phone starts their own checklist.
  Future<void> reset() async {
    _done.setAll(0, defaultState);
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_prefsKey);
    } catch (e) {
      debugPrint('[ChecklistController] could not clear saved progress: $e');
    }
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, _done.map((d) => d ? '1' : '0').join());
    } catch (e) {
      debugPrint('[ChecklistController] could not save progress: $e');
    }
  }
}
