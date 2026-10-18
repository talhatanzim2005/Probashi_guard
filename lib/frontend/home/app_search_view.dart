import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../l10n/app_strings.dart';
import '../../l10n/language_controller.dart';
import '../../theme/app_colors.dart';
import 'models/search_action_item.dart';
import 'services/search_service_registry.dart';

/// Dedicated, bKash-styled searchable action directory screen.
class AppSearchView extends StatefulWidget {
  final void Function(int tabIndex)? onNavigateTab;
  final VoidCallback? onOpenMenu;

  const AppSearchView({
    super.key,
    this.onNavigateTab,
    this.onOpenMenu,
  });

  @override
  State<AppSearchView> createState() => _AppSearchViewState();
}

class _AppSearchViewState extends State<AppSearchView> {
  static const String _recentStorageKey = 'probashi_recent_search_ids';
  static const int _maxRecentItems = 5;

  final TextEditingController _searchController = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  String _query = '';
  List<String> _recentIds = [];
  bool _isLoadingRecents = true;

  late final List<SearchActionItem> _allServices =
      SearchServiceRegistry.getServices(
    onNavigateTab: widget.onNavigateTab,
    onOpenMenu: widget.onOpenMenu,
  );

  @override
  void initState() {
    super.initState();
    _loadRecents();
    _searchController.addListener(() {
      final text = _searchController.text;
      if (text != _query) {
        setState(() => _query = text);
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _loadRecents() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getStringList(_recentStorageKey) ?? [];
      if (mounted) {
        setState(() {
          _recentIds = saved;
          _isLoadingRecents = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isLoadingRecents = false);
      }
    }
  }

  Future<void> _addToRecent(String id) async {
    final next = List<String>.from(_recentIds);
    next.remove(id);
    next.insert(0, id);
    if (next.length > _maxRecentItems) {
      next.removeRange(_maxRecentItems, next.length);
    }

    setState(() => _recentIds = next);

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_recentStorageKey, next);
    } catch (_) {}
  }

  Future<void> _removeRecent(String id) async {
    final next = List<String>.from(_recentIds)..remove(id);
    setState(() => _recentIds = next);

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_recentStorageKey, next);
    } catch (_) {}
  }

  Future<void> _clearAllRecents() async {
    setState(() => _recentIds = []);

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_recentStorageKey);
    } catch (_) {}
  }

  void _onItemTapped(SearchActionItem item) {
    _addToRecent(item.id);
    item.action(context);
  }

  String get _currentLangCode =>
      LanguageController.instance.value.languageCode;

  List<SearchActionItem> get _filteredServices {
    if (_query.trim().isEmpty) return _allServices;
    return _allServices.where((item) => item.matches(_query)).toList();
  }

  List<SearchActionItem> get _recentServices {
    final map = {for (final item in _allServices) item.id: item};
    final list = <SearchActionItem>[];
    for (final id in _recentIds) {
      final item = map[id];
      if (item != null) list.add(item);
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final isQueryEmpty = _query.trim().isEmpty;
    final filtered = _filteredServices;
    final recents = _recentServices;

    return Scaffold(
      backgroundColor: AppColors.cloudDancer,
      body: SafeArea(
        child: Column(
          children: [
            _buildSearchHeader(context, s),
            const Divider(height: 1, thickness: 1, color: Color(0x1A000000)),
            Expanded(
              child: isQueryEmpty
                  ? _buildInitialView(s, recents)
                  : _buildFilteredView(s, filtered),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchHeader(BuildContext context, AppStrings s) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 16, 10),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(
              Icons.arrow_back_rounded,
              color: AppColors.royalBlue,
              size: 24,
            ),
            tooltip: MaterialLocalizations.of(context).backButtonTooltip,
            onPressed: () => Navigator.pop(context),
          ),
          Expanded(
            child: Container(
              height: 46,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: AppColors.royalBlue.withValues(alpha: 0.35),
                  width: 1.2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.royalBlue.withValues(alpha: 0.05),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: TextField(
                controller: _searchController,
                focusNode: _focusNode,
                autofocus: true,
                cursorColor: AppColors.royalBlue,
                textInputAction: TextInputAction.search,
                style: const TextStyle(
                  color: AppColors.ink,
                  fontSize: 14.5,
                  fontWeight: FontWeight.w600,
                ),
                textAlignVertical: TextAlignVertical.center,
                decoration: InputDecoration(
                  isDense: true,
                  hintText: s.searchHint,
                  hintStyle: const TextStyle(
                    color: AppColors.inkMuted,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w400,
                  ),
                  prefixIcon: const Icon(
                    Icons.search_rounded,
                    color: AppColors.royalBlue,
                    size: 22,
                  ),
                  prefixIconConstraints: const BoxConstraints(
                    minWidth: 40,
                    minHeight: 40,
                  ),
                  suffixIcon: _query.isNotEmpty
                      ? IconButton(
                          icon: const Icon(
                            Icons.close_rounded,
                            color: AppColors.inkMuted,
                            size: 19,
                          ),
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _query = '');
                          },
                        )
                      : null,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  contentPadding: const EdgeInsets.only(right: 12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInitialView(AppStrings s, List<SearchActionItem> recents) {
    return ListView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      children: [
        if (!_isLoadingRecents && recents.isNotEmpty) ...[
          _buildRecentSection(s, recents),
          const SizedBox(height: 20),
        ],
        _buildExploreSection(s),
      ],
    );
  }

  Widget _buildRecentSection(AppStrings s, List<SearchActionItem> recents) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.history_rounded,
                  size: 18,
                  color: AppColors.royalBlue,
                ),
                const SizedBox(width: 6),
                Text(
                  s.recentSearches,
                  style: const TextStyle(
                    color: AppColors.royalBlue,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            TextButton(
              onPressed: _clearAllRecents,
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
              child: Text(
                s.clearAll,
                style: const TextStyle(
                  color: AppColors.crimsonRed,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: recents.map((item) {
            return InputChip(
              avatar: Icon(
                item.icon,
                size: 16,
                color: AppColors.royalBlue,
              ),
              label: Text(
                item.title(_currentLangCode),
                style: const TextStyle(
                  color: AppColors.ink,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              backgroundColor: Colors.white,
              side: BorderSide(
                color: AppColors.royalBlue.withValues(alpha: 0.18),
                width: 1.1,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              onPressed: () => _onItemTapped(item),
              onDeleted: () => _removeRecent(item.id),
              deleteIcon: const Icon(
                Icons.close_rounded,
                size: 15,
                color: AppColors.inkMuted,
              ),
              visualDensity: VisualDensity.compact,
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildExploreSection(AppStrings s) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(
              Icons.widgets_outlined,
              size: 18,
              color: AppColors.royalBlue,
            ),
            const SizedBox(width: 6),
            Text(
              s.exploreServices,
              style: const TextStyle(
                color: AppColors.royalBlue,
                fontSize: 15,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: _allServices.length,
          separatorBuilder: (_, _) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            final item = _allServices[index];
            return _buildServiceTile(item);
          },
        ),
      ],
    );
  }

  Widget _buildFilteredView(AppStrings s, List<SearchActionItem> filtered) {
    if (filtered.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.search_off_rounded,
                size: 48,
                color: AppColors.royalBlue.withValues(alpha: 0.35),
              ),
              const SizedBox(height: 12),
              Text(
                s.noServicesFound,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.inkMuted,
                  fontSize: 14.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.separated(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      itemCount: filtered.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final item = filtered[index];
        return _buildServiceTile(item, highlightQuery: _query);
      },
    );
  }

  Widget _buildServiceTile(SearchActionItem item, {String? highlightQuery}) {
    final title = item.title(_currentLangCode);
    final subtitle = item.subtitle(_currentLangCode);

    final cleanQuery = highlightQuery?.trim() ?? '';
    final hasHighlight = cleanQuery.isNotEmpty;

    // Check if a keyword matched that isn't directly in title/subtitle
    String? matchedKeyword;
    if (hasHighlight) {
      final q = cleanQuery.toLowerCase();
      final inTitle = title.toLowerCase().contains(q);
      final inSub = subtitle.toLowerCase().contains(q);
      if (!inTitle && !inSub) {
        for (final kw in item.keywords) {
          if (kw.toLowerCase().contains(q)) {
            matchedKeyword = kw;
            break;
          }
        }
      }
    }

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _onItemTapped(item),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: AppColors.royalBlue.withValues(alpha: 0.12),
              width: 1.1,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: AppColors.royalBlue.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  item.icon,
                  color: AppColors.royalBlue,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    RichText(
                      text: TextSpan(
                        children: _highlightSpans(
                          text: title,
                          query: cleanQuery,
                          normalStyle: const TextStyle(
                            color: AppColors.ink,
                            fontSize: 14.5,
                            fontWeight: FontWeight.w700,
                          ),
                          highlightStyle: TextStyle(
                            color: AppColors.royalBlue,
                            backgroundColor:
                                AppColors.royalBlue.withValues(alpha: 0.14),
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    RichText(
                      text: TextSpan(
                        children: _highlightSpans(
                          text: subtitle,
                          query: cleanQuery,
                          normalStyle: const TextStyle(
                            color: AppColors.inkMuted,
                            fontSize: 12,
                            fontWeight: FontWeight.w400,
                          ),
                          highlightStyle: TextStyle(
                            color: AppColors.royalBlue,
                            backgroundColor:
                                AppColors.royalBlue.withValues(alpha: 0.14),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (matchedKeyword != null) ...[
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.royalBlue.withValues(alpha: 0.07),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          'Matched: $matchedKeyword',
                          style: const TextStyle(
                            color: AppColors.royalBlue,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(
                Icons.chevron_right_rounded,
                color: AppColors.inkMuted,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<TextSpan> _highlightSpans({
    required String text,
    required String query,
    required TextStyle normalStyle,
    required TextStyle highlightStyle,
  }) {
    if (query.trim().isEmpty) {
      return [TextSpan(text: text, style: normalStyle)];
    }

    final cleanQuery = query.trim().toLowerCase();
    final lowerText = text.toLowerCase();
    final spans = <TextSpan>[];

    int start = 0;
    while (true) {
      final index = lowerText.indexOf(cleanQuery, start);
      if (index == -1) {
        spans.add(TextSpan(text: text.substring(start), style: normalStyle));
        break;
      }
      if (index > start) {
        spans.add(
          TextSpan(text: text.substring(start, index), style: normalStyle),
        );
      }
      spans.add(
        TextSpan(
          text: text.substring(index, index + cleanQuery.length),
          style: highlightStyle,
        ),
      );
      start = index + cleanQuery.length;
    }

    return spans;
  }
}
