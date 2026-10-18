/// One scraped news article in the notice feed.
///
/// The rows are Open Graph metadata that `backend_service/scripts/seed_notices.ts`
/// read from the publishers and cached in Supabase, so the app never calls the
/// news sites itself.
class NoticeModel {
  final String id;
  final String title;

  /// `og:description`. Publishers sometimes omit it, so it may be null.
  final String? description;

  /// `og:image`. Null when the article had no image worth showing.
  final String? imageUrl;

  /// The article this was scraped from. Opened in the browser from the
  /// Notices page only — never from the home slider.
  final String sourceUrl;

  final DateTime createdAt;

  const NoticeModel({
    required this.id,
    required this.title,
    required this.sourceUrl,
    required this.createdAt,
    this.description,
    this.imageUrl,
  });

  bool get hasImage => (imageUrl ?? '').isNotEmpty;

  /// "www.tbsnews.net/..." -> "tbsnews.net", shown as the source label.
  String get sourceName {
    final host = Uri.tryParse(sourceUrl)?.host ?? '';
    return host.startsWith('www.') ? host.substring(4) : host;
  }

  factory NoticeModel.fromMap(Map<String, dynamic> map) {
    String? text(Object? v) {
      final s = v?.toString().trim();
      return (s == null || s.isEmpty) ? null : s;
    }

    return NoticeModel(
      id: map['id']?.toString() ?? '',
      title: text(map['title']) ?? '',
      description: text(map['description']),
      imageUrl: text(map['image_url']),
      sourceUrl: text(map['source_url']) ?? '',
      createdAt: DateTime.tryParse(map['created_at']?.toString() ?? '') ??
          DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'title': title,
        'description': description,
        'image_url': imageUrl,
        'source_url': sourceUrl,
        'created_at': createdAt.toIso8601String(),
      };
}
