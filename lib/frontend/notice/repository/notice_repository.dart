import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/notice_model.dart';

/// Reads the notice feed from Supabase.
///
/// The table is read-only for clients: rows are written by
/// `backend_service/scripts/seed_notices.ts` with the service role key.
class NoticeRepository {
  final SupabaseClient? client;

  const NoticeRepository({this.client});

  SupabaseClient? get _supabase {
    if (client != null) return client;
    try {
      return Supabase.instance.client;
    } catch (_) {
      // Supabase never initialised (offline launch, or a test).
      return null;
    }
  }

  /// Newest first. [limit] caps the rows, for the three-item home slider.
  ///
  /// Returns an empty list rather than throwing when the feed cannot be read,
  /// so a missing table or a dead connection leaves the screen empty instead of
  /// breaking it. [NoticeFeedException] is thrown only for errors worth showing.
  Future<List<NoticeModel>> getNotices({int? limit}) async {
    final sb = _supabase;
    if (sb == null) {
      throw const NoticeFeedException('Supabase is not available on this device.');
    }

    try {
      final query = sb
          .from('notices')
          .select()
          .order('created_at', ascending: false);

      final records = await (limit == null ? query : query.limit(limit))
          .timeout(const Duration(seconds: 6));

      return records
          .map(NoticeModel.fromMap)
          .where((n) => n.title.isNotEmpty)
          .toList();
    } on PostgrestException catch (e) {
      debugPrint('[NoticeRepository] feed unavailable: ${e.code} ${e.message}');
      // PGRST205: the table is not in the schema cache, i.e. the migration has
      // not been applied yet. Worth saying plainly rather than showing nothing.
      if (e.code == 'PGRST205') {
        throw const NoticeFeedException(
          'The notices table has not been created yet. '
          'Run the migration in supabase/migrations, then seed it.',
        );
      }
      throw NoticeFeedException(e.message);
    } catch (e) {
      debugPrint('[NoticeRepository] could not load notices: $e');
      throw const NoticeFeedException('Could not load notices.');
    }
  }
}

/// A feed failure the UI should surface, as opposed to an empty feed.
class NoticeFeedException implements Exception {
  final String message;

  const NoticeFeedException(this.message);

  @override
  String toString() => message;
}
