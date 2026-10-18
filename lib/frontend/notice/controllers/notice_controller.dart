import 'package:flutter/foundation.dart';

import '../models/notice_model.dart';
import '../repository/notice_repository.dart';

/// Holds the notice feed for both screens that show it.
///
/// One instance shared by the home slider and the Notices tab, so opening the
/// tab from the slider does not refetch what is already on screen.
class NoticeController extends ChangeNotifier {
  NoticeController._() : _repository = const NoticeRepository();

  static final NoticeController instance = NoticeController._();

  /// For tests and for pointing the feed at a different source.
  @visibleForTesting
  NoticeController.withRepository(NoticeRepository repository)
      : _repository = repository;

  final NoticeRepository _repository;

  List<NoticeModel> _notices = [];
  List<NoticeModel> get notices => _notices;

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  /// Set when the feed could not be read at all. Null on an ordinary empty feed.
  String? _error;
  String? get error => _error;

  bool _hasLoaded = false;

  /// How many slides the home Notice Board shows.
  static const int homeSlideCount = 3;

  /// The newest few, for the home slider.
  List<NoticeModel> get latest =>
      _notices.take(homeSlideCount).toList(growable: false);

  bool get isEmpty => !_isLoading && _error == null && _notices.isEmpty;

  /// Loads once per app run. Pull-to-refresh calls [refresh] instead.
  Future<void> loadOnce() async {
    if (_hasLoaded || _isLoading) return;
    await refresh();
  }

  Future<void> refresh() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      _notices = await _repository.getNotices();
      _error = null;
    } on NoticeFeedException catch (e) {
      _error = e.message;
      _notices = const [];
    } catch (e) {
      debugPrint('[NoticeController] unexpected feed error: $e');
      _error = 'Could not load notices.';
      _notices = const [];
    } finally {
      _hasLoaded = true;
      _isLoading = false;
      notifyListeners();
    }
  }
}
