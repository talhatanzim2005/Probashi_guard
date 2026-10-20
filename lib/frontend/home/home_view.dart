import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../l10n/app_strings.dart';
import '../../theme/app_colors.dart';
import '../../widget/coming_soon.dart';
import '../../widget/ink_surface.dart';
import '../crChecker/controllers/checklist_controller.dart';
import '../notice/controllers/notice_controller.dart';
import 'app_search_view.dart';

class HomeView extends StatefulWidget {
  final VoidCallback? onNavigateToNotice;

  /// Opens the document scanner: checking a paper for fraud starts with a scan.
  final VoidCallback? onNavigateToFraudChecker;

  /// Opens the vault of documents already scanned on this device.
  final VoidCallback? onOpenSavedDocuments;

  /// Callback when the search bar is tapped.
  final VoidCallback? onSearchTap;

  /// Whether to render the dedicated search bar inside the home scroll view.
  final bool showSearchBar;

  /// Shown in the greeting. Falls back to "Welcome" when null.
  final String? userName;

  /// Optional NoticeController for testing or overriding feed source.
  final NoticeController? noticeController;

  const HomeView({
    super.key,
    this.onNavigateToNotice,
    this.onNavigateToFraudChecker,
    this.onOpenSavedDocuments,
    this.onSearchTap,
    this.showSearchBar = false,
    this.userName,
    this.noticeController,
  });

  @override
  State<HomeView> createState() => _HomeViewState();
}

class _NoticeItem {
  final IconData icon;
  final Color accentColor;
  final Color backgroundColor;

  const _NoticeItem({
    required this.icon,
    required this.accentColor,
    required this.backgroundColor,
  });
}

class _HomeViewState extends State<HomeView> {
  // 1. Checklist State
  bool _isChecklistExpanded = false;

  /// Shared with the other checklist views and saved across launches.
  final ChecklistController _checklistController = ChecklistController.instance;
  final GlobalKey _checklistCardKey = GlobalKey();

  // 2. Auto-Sliding Notice Slider State
  late final PageController _noticePageController;
  Timer? _noticeSliderTimer;
  int _currentNoticePage = 0;

  /// Auto-slide on/off. The person can switch it with the pause/play button.
  bool _noticeAutoPlay = true;

  /// True only while the auto-slide timer itself is changing the page, so we
  /// can tell timer-made changes apart from the person's own swipes/taps.
  bool _autoSlideInFlight = false;

  /// Styling only, in the same order as [AppStrings.noticeSlides].
  final List<_NoticeItem> _notices = const [
    _NoticeItem(
      icon: Icons.warning_amber_rounded,
      accentColor: AppColors.crimsonRed,
      backgroundColor: AppColors.cloudDancer,
    ),
    _NoticeItem(
      icon: Icons.verified_user_outlined,
      accentColor: AppColors.royalBlue,
      backgroundColor: AppColors.cloudDancer,
    ),
    _NoticeItem(
      icon: Icons.campaign_outlined,
      accentColor: AppColors.emeraldGreen,
      backgroundColor: AppColors.cloudDancer,
    ),
  ];

  int get _completedCount => _checklistController.completed;
  double get _progressPercent => _checklistController.progress;

  /// Index of the first unfinished item, or -1 when everything is done.
  int get _nextIndex => _checklistController.nextIndex;

  /// Unfinished items first, then completed ones (original order is kept
  /// inside each group). Collapsed view shows only the first 3.
  List<int> get _visibleIndexes {
    final pending = <int>[];
    final done = <int>[];
    for (var i = 0; i < _checklistController.total; i++) {
      (_checklistController.isDone(i) ? done : pending).add(i);
    }
    final ordered = [...pending, ...done];
    return _isChecklistExpanded ? ordered : ordered.take(3).toList();
  }

  /// Protection status shown in the greeting badge. Driven by real progress so
  /// the app never claims "Protected" while most checks are still open.
  ({String label, IconData icon, Color color}) _statusFor(AppStrings s) {
    if (_checklistController.total > 0 &&
        _completedCount == _checklistController.total) {
      return (
        label: s.fullyProtected,
        icon: Icons.verified_user_rounded,
        color: AppColors.emeraldGreen,
      );
    }
    if (_progressPercent >= 0.5) {
      return (
        label: s.partiallyProtected,
        icon: Icons.shield_outlined,
        color: AppColors.royalBlue,
      );
    }
    return (
      label: s.actionNeeded,
      icon: Icons.warning_amber_rounded,
      color: AppColors.crimsonRed,
    );
  }

  NoticeController get _noticeController =>
      widget.noticeController ?? NoticeController.instance;

  int get _sliderItemCount => _noticeController.latest.isNotEmpty
      ? _noticeController.latest.length
      : _notices.length;

  @override
  void initState() {
    super.initState();
    _noticePageController = PageController();
    _startNoticeAutoScroll();
    _noticeController.loadOnce();
    _checklistController.addListener(_onChecklistChanged);
    _checklistController.focusRequests.addListener(_onChecklistFocusRequested);
  }

  void _startNoticeAutoScroll() {
    _noticeSliderTimer?.cancel();
    if (!_noticeAutoPlay) return;
    _noticeSliderTimer = Timer.periodic(const Duration(milliseconds: 3500), (
      _,
    ) {
      if (mounted && _noticePageController.hasClients) {
        final count = _sliderItemCount;
        if (count == 0) return;
        final nextPage = (_currentNoticePage + 1) % count;
        if (nextPage != _currentNoticePage) _autoSlideInFlight = true;
        _noticePageController.animateToPage(
          nextPage,
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeInOut,
        );
      }
    });
  }

  /// Human control: jump to a notice (wraps around at both ends).
  void _goToNotice(int index) {
    if (!_noticePageController.hasClients) return;
    final count = _sliderItemCount;
    if (count == 0) return;
    final target = (index + count) % count;
    _noticePageController.animateToPage(
      target,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  /// Human control: pause / resume the automatic sliding.
  void _toggleNoticeAutoPlay() {
    setState(() => _noticeAutoPlay = !_noticeAutoPlay);
    _startNoticeAutoScroll();
  }

  @override
  void dispose() {
    _checklistController.removeListener(_onChecklistChanged);
    _checklistController.focusRequests.removeListener(
      _onChecklistFocusRequested,
    );
    _noticeSliderTimer?.cancel();
    _noticePageController.dispose();
    super.dispose();
  }

  void _toggleChecklistItem(int index) => _checklistController.toggle(index);

  /// A tick made on another screen (or restored from disk) repaints this one.
  void _onChecklistChanged() {
    if (mounted) setState(() {});
  }

  /// Scrolls the checklist card into view when another screen asks for it,
  /// e.g. the profile's "Action Needed" banner.
  void _onChecklistFocusRequested() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final target = _checklistCardKey.currentContext;
      if (!mounted || target == null) return;
      Scrollable.ensureVisible(
        target,
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeOutCubic,
        alignment: 0.05,
      );
    });
  }

  Widget _buildSearchBar(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: AppColors.cloudDancer,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: AppColors.royalBlue.withValues(alpha: 0.30),
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
          readOnly: true,
          onTap: () {
            if (widget.onSearchTap != null) {
              widget.onSearchTap!();
            } else {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => AppSearchView(
                    onNavigateTab: (idx) {
                      if (idx == 3) widget.onNavigateToNotice?.call();
                      if (idx == 2) widget.onNavigateToFraudChecker?.call();
                    },
                  ),
                ),
              );
            }
          },
          style: const TextStyle(
            color: AppColors.ink,
            fontSize: 14.5,
            fontWeight: FontWeight.w500,
          ),
          textAlignVertical: TextAlignVertical.center,
          decoration: const InputDecoration(
            isDense: true,
            hintText: 'Search services, features... / সেবা খুঁজুন...',
            hintStyle: TextStyle(
              color: AppColors.inkMuted,
              fontSize: 13.5,
              fontWeight: FontWeight.w400,
            ),
            prefixIcon: Icon(
              Icons.search_rounded,
              color: AppColors.royalBlue,
              size: 22,
            ),
            prefixIconConstraints: BoxConstraints(minWidth: 36, minHeight: 36),
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);

    return Scaffold(
      backgroundColor: AppColors.cloudDancer,
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
        children: [
          // Greeting Header
          Padding(
            padding: const EdgeInsets.only(top: 8.0, bottom: 14.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.userName == null
                            ? s.welcome
                            : s.greeting(widget.userName!),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.royalBlue,
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.5,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        s.dashboardSubtitle,
                        style: const TextStyle(
                          color: AppColors.inkMuted,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                _buildStatusBadge(),
              ],
            ),
          ),

          if (widget.showSearchBar) ...[
            _buildSearchBar(context),
            const SizedBox(height: 14),
          ],

          // 1. Hero Card: Pre-Departure Checklist & CR Status Card
          _buildHeroChecklistCard(),

          const SizedBox(height: 18),

          // 2. Auto-Sliding Notice Banner (Notice Board)
          _buildAutoSlidingNoticeBanner(),

          const SizedBox(height: 22),

          // 3. Quick Features Grid (bKash Style)
          _buildQuickFeaturesGrid(),

          const SizedBox(height: 20),
        ],
      ),
    );
  }

  // --- Status badge (greeting header) ---
  Widget _buildStatusBadge() {
    final s = AppStrings.of(context);
    final status = _statusFor(s);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: status.color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: status.color.withValues(alpha: 0.4),
          width: 1.0,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(status.icon, color: status.color, size: 16),
          const SizedBox(width: 4),
          Text(
            status.label,
            style: TextStyle(
              color: status.color,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  /// Opens the Notices tab. If this screen was built without a way there, the
  /// tap still answers.
  void _openNotices() {
    final open = widget.onNavigateToNotice;
    if (open != null) {
      open();
    } else {
      showComingSoon(context, AppStrings.of(context).menuNotices);
    }
  }

  // --- 1. Hero Card Builder ---
  Widget _buildHeroChecklistCard() {
    final s = AppStrings.of(context);
    return Container(
      key: _checklistCardKey,
      decoration: BoxDecoration(
        color: AppColors.cloudDancer,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.royalBlue, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: AppColors.royalBlue.withValues(alpha: 0.08),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      // The header's ripple is drawn on this Material, above the card's fill.
      child: Material(
        type: MaterialType.transparency,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Card Header
            InkWell(
              onTap: () {
                setState(() {
                  _isChecklistExpanded = !_isChecklistExpanded;
                });
              },
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(16),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16.0, 16.0, 16.0, 12.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            s.checklistTitle,
                            style: const TextStyle(
                              color: AppColors.royalBlue,
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              height: 1.25,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        // Dynamic summary badge (e.g. "3/8 Done")
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 250),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: _completedCount == _checklistController.total
                                ? AppColors.emeraldGreen
                                : AppColors.emeraldGreen.withValues(
                                    alpha: 0.12,
                                  ),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: AppColors.emeraldGreen,
                              width: 1.2,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.task_alt_rounded,
                                size: 13,
                                color:
                                    _completedCount ==
                                        _checklistController.total
                                    ? AppColors.cloudDancer
                                    : AppColors.emeraldGreen,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                s.checklistDone(
                                  _completedCount,
                                  _checklistController.total,
                                ),
                                style: TextStyle(
                                  color:
                                      _completedCount ==
                                          _checklistController.total
                                      ? AppColors.cloudDancer
                                      : AppColors.emeraldGreen,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),

                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            s.checklistSubtitle,
                            style: TextStyle(
                              color: AppColors.inkMuted,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Row(
                          children: [
                            Text(
                              s.viewDetails,
                              style: const TextStyle(
                                color: AppColors.royalBlue,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Icon(
                              Icons.chevron_right_rounded,
                              size: 16,
                              color: AppColors.royalBlue,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            const Divider(height: 1, thickness: 1, color: Color(0x221A4B9C)),

            // Dynamic Progress Bar & Ratio
            Padding(
              padding: const EdgeInsets.fromLTRB(16.0, 14.0, 16.0, 8.0),
              child: Semantics(
                label: s.departureReadiness,
                // toInt() floors on purpose: never overstate readiness.
                value: '${(_progressPercent * 100).toInt()}%',
                child: ExcludeSemantics(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            s.departureReadiness,
                            style: const TextStyle(
                              color: AppColors.inkMuted,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            '${(_progressPercent * 100).toInt()}%',
                            style: const TextStyle(
                              color: AppColors.ink,
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: TweenAnimationBuilder<double>(
                          tween: Tween<double>(end: _progressPercent),
                          duration: const Duration(milliseconds: 350),
                          curve: Curves.easeOut,
                          builder: (context, value, _) =>
                              LinearProgressIndicator(
                                value: value,
                                minHeight: 7,
                                backgroundColor: AppColors.royalBlue.withValues(
                                  alpha: 0.12,
                                ),
                                valueColor: const AlwaysStoppedAnimation<Color>(
                                  AppColors.emeraldGreen,
                                ),
                              ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // Interactive Checkable List Items
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Column(
                children: [
                  // Pending items first; top 3 when collapsed, all when expanded.
                  for (final i in _visibleIndexes) _buildChecklistRow(i),
                ],
              ),
            ),

            // Expand / Collapse Action Button
            Center(
              child: TextButton.icon(
                onPressed: () {
                  setState(() {
                    _isChecklistExpanded = !_isChecklistExpanded;
                  });
                },
                icon: Icon(
                  _isChecklistExpanded
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.keyboard_arrow_down_rounded,
                  color: AppColors.royalBlue,
                  size: 18,
                ),
                label: Text(
                  _isChecklistExpanded
                      ? s.showFewerItems
                      : s.showAllItems(_checklistController.total),
                  style: const TextStyle(
                    color: AppColors.royalBlue,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 4),
          ],
        ),
      ),
    );
  }

  Widget _buildChecklistRow(int index) {
    final isDone = _checklistController.isDone(index);
    final isNext = index == _nextIndex;
    final s = AppStrings.of(context);
    final text = s.checklist[index];

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Semantics(
        button: true,
        checked: isDone,
        label: '${text.title}. ${text.subtitle}',
        hint: s.markAsDoneHint,
        onTap: () => _toggleChecklistItem(index),
        excludeSemantics: true,
        child: InkSurface(
          onTap: () => _toggleChecklistItem(index),
          borderRadius: BorderRadius.circular(8),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: isDone
                ? AppColors.emeraldGreen.withValues(alpha: 0.06)
                : AppColors.cloudDancer,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isDone
                  ? AppColors.emeraldGreen.withValues(alpha: 0.35)
                  : isNext
                  ? AppColors.royalBlue.withValues(alpha: 0.5)
                  : AppColors.royalBlue.withValues(alpha: 0.16),
              width: 1.0,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Checkbox icon
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 20,
                height: 20,
                margin: const EdgeInsets.only(top: 1),
                decoration: BoxDecoration(
                  color: isDone
                      ? AppColors.emeraldGreen
                      : AppColors.cloudDancer,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                    color: isDone
                        ? AppColors.emeraldGreen
                        : AppColors.royalBlue.withValues(alpha: 0.5),
                    width: 1.5,
                  ),
                ),
                child: isDone
                    ? const Icon(
                        Icons.check,
                        size: 14,
                        color: AppColors.cloudDancer,
                      )
                    : null,
              ),
              const SizedBox(width: 10),
              // Checklist text (no strikethrough: the green check already
              // says "done", and crossed-out text reads as "dismissed").
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (isNext) ...[
                      Text(
                        s.nextStep,
                        style: const TextStyle(
                          color: AppColors.royalBlue,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.6,
                        ),
                      ),
                      const SizedBox(height: 2),
                    ],
                    Text(
                      text.title,
                      style: TextStyle(
                        color: isDone ? AppColors.inkMuted : AppColors.ink,
                        fontSize: 13,
                        fontWeight: isDone ? FontWeight.w500 : FontWeight.w700,
                        height: 1.25,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      text.subtitle,
                      style: const TextStyle(
                        color: AppColors.inkMuted,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // --- 2. Auto-Sliding Notice Banner Builder ---
  Widget _buildAutoSlidingNoticeBanner() {
    final s = AppStrings.of(context);
    return ListenableBuilder(
      listenable: _noticeController,
      builder: (context, _) {
        final dynamicNotices = _noticeController.latest;
        final bool hasDynamic = dynamicNotices.isNotEmpty;
        final int itemCount = hasDynamic
            ? dynamicNotices.length
            : _notices.length;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.campaign_rounded,
                      color: AppColors.royalBlue,
                      size: 18,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      s.noticeBoard,
                      style: const TextStyle(
                        color: AppColors.royalBlue,
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
                InkWell(
                  onTap: _openNotices,
                  child: Row(
                    children: [
                      Text(
                        s.allNotices,
                        style: const TextStyle(
                          color: AppColors.royalBlue,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const Icon(
                        Icons.chevron_right_rounded,
                        color: AppColors.royalBlue,
                        size: 16,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Carousel PageView (auto-slides every 3.5s; person can swipe,
            // use the arrows / dots, or pause the auto-slide)
            // A page view cannot size itself to its cards, so the height
            // follows the system text size: tag line plus two message lines.
            SizedBox(
              height: math.max(
                86.0,
                26 +
                    MediaQuery.textScalerOf(context).scale(10.5) * 1.45 +
                    MediaQuery.textScalerOf(context).scale(12) * 2.6,
              ),
              child: PageView.builder(
                controller: _noticePageController,
                itemCount: itemCount,
                onPageChanged: (index) {
                  setState(() {
                    _currentNoticePage = index;
                  });
                  // A change the timer did not make came from the person (swipe,
                  // arrow or dot): restart the countdown so the auto-slide does
                  // not jump right after their action.
                  if (_autoSlideInFlight) {
                    _autoSlideInFlight = false;
                  } else {
                    _startNoticeAutoScroll();
                  }
                },
                itemBuilder: (context, index) {
                  final style = _notices[index % _notices.length];
                  final String tagText;
                  final String messageText;

                  if (hasDynamic) {
                    final notice = dynamicNotices[index];
                    tagText = notice.sourceName.toUpperCase();
                    messageText = notice.title;
                  } else {
                    final fallbackText =
                        AppStrings.of(context).noticeSlides[index %
                            AppStrings.of(context).noticeSlides.length];
                    tagText = fallbackText.tag;
                    messageText = fallbackText.message;
                  }

                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2.0),
                    child: InkSurface(
                      onTap: _openNotices,
                      borderRadius: BorderRadius.circular(12),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14.0,
                        vertical: 10.0,
                      ),
                      decoration: BoxDecoration(
                        color: style.backgroundColor,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: style.accentColor.withValues(alpha: 0.35),
                          width: 1.2,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: style.accentColor.withValues(alpha: 0.05),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: style.accentColor.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(
                              style.icon,
                              color: style.accentColor,
                              size: 18,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Row(
                                  children: [
                                    Text(
                                      tagText,
                                      style: TextStyle(
                                        color: style.accentColor,
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: 0.6,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Icon(
                                      Icons.arrow_forward_ios_rounded,
                                      size: 9,
                                      color: style.accentColor,
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  messageText,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: AppColors.ink,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    height: 1.25,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 8),

            // Controls: pause/play (left), previous - dots - next (center).
            Row(
              children: [
                IconButton(
                  onPressed: _toggleNoticeAutoPlay,
                  tooltip: _noticeAutoPlay
                      ? s.pauseAutoSlide
                      : s.resumeAutoSlide,
                  icon: Icon(
                    _noticeAutoPlay
                        ? Icons.pause_circle_outline_rounded
                        : Icons.play_circle_outline_rounded,
                  ),
                  iconSize: 22,
                  color: AppColors.royalBlue,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 36,
                    minHeight: 36,
                  ),
                ),
                Expanded(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        onPressed: () => _goToNotice(_currentNoticePage - 1),
                        tooltip: s.previousNotice,
                        icon: const Icon(Icons.chevron_left_rounded),
                        iconSize: 24,
                        color: AppColors.royalBlue,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 36,
                          minHeight: 36,
                        ),
                      ),
                      ...List.generate(itemCount, (index) {
                        final isActive = _currentNoticePage == index;
                        return GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => _goToNotice(index),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 3,
                              vertical: 14,
                            ),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 250),
                              curve: Curves.easeInOut,
                              width: isActive ? 20 : 6,
                              height: 6,
                              decoration: BoxDecoration(
                                color: isActive
                                    ? AppColors.royalBlue
                                    : AppColors.royalBlue.withValues(
                                        alpha: 0.22,
                                      ),
                                borderRadius: BorderRadius.circular(3),
                              ),
                            ),
                          ),
                        );
                      }),
                      IconButton(
                        onPressed: () => _goToNotice(_currentNoticePage + 1),
                        tooltip: s.nextNotice,
                        icon: const Icon(Icons.chevron_right_rounded),
                        iconSize: 24,
                        color: AppColors.royalBlue,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 36,
                          minHeight: 36,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 36),
              ],
            ),
          ],
        );
      },
    );
  }

  // --- 3. Quick Features Grid (bKash Style) ---
  Widget _buildQuickFeaturesGrid() {
    final s = AppStrings.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          s.quickFeatures,
          style: const TextStyle(
            color: AppColors.royalBlue,
            fontSize: 18,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 12),

        // Two cards side by side
        Row(
          children: [
            // 1. Saved Documents
            Expanded(
              child: _QuickFeatureCard(
                icon: Icons.folder_shared_outlined,
                iconColor: AppColors.royalBlue,
                label: s.savedDocuments,
                borderColor: AppColors.royalBlue.withValues(alpha: 0.22),
                textColor: AppColors.royalBlue,
                onTap:
                    widget.onOpenSavedDocuments ??
                    () => showComingSoon(context, s.savedDocuments),
              ),
            ),
            const SizedBox(width: 12),

            // 2. Fraud Checker
            Expanded(
              child: _QuickFeatureCard(
                icon: Icons.verified_user_outlined,
                iconColor: AppColors.royalBlue,
                label: s.menuFraudChecker,
                borderColor: AppColors.royalBlue.withValues(alpha: 0.22),
                textColor: AppColors.royalBlue,
                onTap:
                    widget.onNavigateToFraudChecker ??
                    () => showComingSoon(context, s.menuFraudChecker),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _QuickFeatureCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final Color borderColor;
  final Color textColor;
  final VoidCallback onTap;

  const _QuickFeatureCard({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.borderColor,
    required this.textColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkSurface(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      // minHeight (not a fixed height) so larger fonts never overflow.
      alignment: Alignment.center,
      constraints: const BoxConstraints(minHeight: 92),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.cloudDancer,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor, width: 1.2),
        boxShadow: [
          BoxShadow(
            color: AppColors.royalBlue.withValues(alpha: 0.04),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: iconColor, size: 24),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: textColor,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
