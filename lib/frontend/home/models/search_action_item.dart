import 'package:flutter/material.dart';

/// Represents a searchable action or service item within the app directory.
class SearchActionItem {
  final String id;
  final String titleEn;
  final String titleBn;
  final String subtitleEn;
  final String subtitleBn;
  final IconData icon;
  final List<String> keywords;
  final void Function(BuildContext context) action;

  const SearchActionItem({
    required this.id,
    required this.titleEn,
    required this.titleBn,
    required this.subtitleEn,
    required this.subtitleBn,
    required this.icon,
    required this.keywords,
    required this.action,
  });

  /// Returns localized title according to language code.
  String title(String languageCode) =>
      languageCode == 'bn' ? titleBn : titleEn;

  /// Returns localized subtitle according to language code.
  String subtitle(String languageCode) =>
      languageCode == 'bn' ? subtitleBn : subtitleEn;

  /// Returns true if this item matches the search query across English,
  /// Bengali, and transliterated keywords.
  bool matches(String query) {
    final cleanQuery = query.trim().toLowerCase();
    if (cleanQuery.isEmpty) return false;

    if (titleEn.toLowerCase().contains(cleanQuery)) return true;
    if (titleBn.toLowerCase().contains(cleanQuery)) return true;
    if (subtitleEn.toLowerCase().contains(cleanQuery)) return true;
    if (subtitleBn.toLowerCase().contains(cleanQuery)) return true;

    for (final kw in keywords) {
      if (kw.toLowerCase().contains(cleanQuery)) return true;
    }

    return false;
  }
}
