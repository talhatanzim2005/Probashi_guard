import 'dart:async';
import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';

class HomeView extends StatefulWidget {
  final VoidCallback? onNavigateToNotice;
  final VoidCallback? onNavigateToCrChecker;

  /// Shown in the greeting. Falls back to "Welcome" when null.
  final String? userName;

  const HomeView({
    super.key,
    this.onNavigateToNotice,
    this.onNavigateToCrChecker,
    this.userName,
  });

  @override
  State<HomeView> createState() => _HomeViewState();
}

class _ChecklistItem {
  final String title;
  final String subtitle;
  bool isCompleted;

  _ChecklistItem({
    required this.title,
    required this.subtitle,
    required this.isCompleted,
  });
}

class _NoticeItem {
  final String tag;
  final String message;
  final IconData icon;
  final Color accentColor;
  final Color backgroundColor;

  const _NoticeItem({
    required this.tag,
    required this.message,
    required this.icon,
    required this.accentColor,
    required this.backgroundColor,
  });
}

class _HomeViewState extends State<HomeView> {
  // 1. Checklist State
  bool _isChecklistExpanded = false;

  final List<_ChecklistItem> _checklist = [
    _ChecklistItem(
      title: 'Verify Company Commercial Registration (CR/Trade License) is active',
      subtitle: 'Official host country establishment database status',
      isCompleted: true,
    ),
    _ChecklistItem(
      title: 'Confirm work visa is authentic on the host country immigration portal',
      subtitle: 'Cross-check visa number directly with ministry records',
      isCompleted: true,
    ),
    _ChecklistItem(
      title: 'Ensure visa type is \'Work/Employment\' (NOT Visit or Tourist)',
      subtitle: 'Avoid illegal travel on visitor visas without legal protections',
      isCompleted: true,
    ),
    _ChecklistItem(
      title: 'Verify BMET Smart Clearance Card via QR code scan',
      subtitle: 'Government authorized emigrant clearance registration',
      isCompleted: false,
    ),
    _ChecklistItem(
      title: 'Cross-check that company name on contract matches the visa',
      subtitle: 'Guarantees the sponsor matches the real workplace',
      isCompleted: false,
    ),
    _ChecklistItem(
      title: 'Confirm salary, food allowance, and accommodation terms in writing',
      subtitle: 'Legally attested employment agreement terms',
      isCompleted: false,
    ),
    _ChecklistItem(
      title: 'Obtain company representative contact and airport pickup details',
      subtitle: 'Authorized reception contact point at arrival airport',
      isCompleted: false,
    ),
    _ChecklistItem(
      title: 'Save embassy helpline and labor dispute contact numbers',
      subtitle: 'Direct hotlines for legal and labor grievance support',
      isCompleted: false,
    ),
  ];

  // 2. Auto-Sliding Notice Slider State
  late final PageController _noticePageController;
  Timer? _noticeSliderTimer;
  int _currentNoticePage = 0;

  /// Auto-slide on/off. The person can switch it with the pause/play button.
  bool _noticeAutoPlay = true;

  /// True only while the auto-slide timer itself is changing the page, so we
  /// can tell timer-made changes apart from the person's own swipes/taps.
  bool _autoSlideInFlight = false;

  final List<_NoticeItem> _notices = const [
    _NoticeItem(
      tag: 'FRAUD ALERT',
      message:
          'Fraud Alert: Verify all work permits on the official embassy portal before booking flights.',
      icon: Icons.warning_amber_rounded,
      accentColor: AppColors.crimsonRed,
      backgroundColor: AppColors.cloudDancer,
    ),
    _NoticeItem(
      tag: 'EMBASSY ADVISORY',
      message:
          'Embassy Advisory: Mandatory BMET Smart Card scanning at airport immigration.',
      icon: Icons.verified_user_outlined,
      accentColor: AppColors.royalBlue,
      backgroundColor: AppColors.cloudDancer,
    ),
    _NoticeItem(
      tag: 'LABOR WING NOTICE',
      message:
          'Labor Wing Notice: Updated minimum wage standards for destination countries.',
      icon: Icons.campaign_outlined,
      accentColor: AppColors.emeraldGreen,
      backgroundColor: AppColors.cloudDancer,
    ),
  ];

  int get _completedCount => _checklist.where((item) => item.isCompleted).length;
  double get _progressPercent =>
      _checklist.isEmpty ? 0.0 : _completedCount / _checklist.length;

  /// Index of the first unfinished item, or -1 when everything is done.
  int get _nextIndex => _checklist.indexWhere((item) => !item.isCompleted);

  /// Unfinished items first, then completed ones (original order is kept
  /// inside each group). Collapsed view shows only the first 3.
  List<int> get _visibleIndexes {
    final pending = <int>[];
    final done = <int>[];
    for (var i = 0; i < _checklist.length; i++) {
      (_checklist[i].isCompleted ? done : pending).add(i);
    }
    final ordered = [...pending, ...done];
    return _isChecklistExpanded ? ordered : ordered.take(3).toList();
  }

  /// Protection status shown in the greeting badge. Driven by real progress so
  /// the app never claims "Protected" while most checks are still open.
  ({String label, IconData icon, Color color}) get _status {
    if (_checklist.isNotEmpty && _completedCount == _checklist.length) {
      return (
        label: 'Fully Protected',
        icon: Icons.verified_user_rounded,
        color: AppColors.emeraldGreen,
      );
    }
    if (_progressPercent >= 0.5) {
      return (
        label: 'Partially Protected',
        icon: Icons.shield_outlined,
        color: AppColors.royalBlue,
      );
    }
    return (
      label: 'Action Needed',
      icon: Icons.warning_amber_rounded,
      color: AppColors.crimsonRed,
    );
  }

  @override
  void initState() {
    super.initState();
    _noticePageController = PageController();
    _startNoticeAutoScroll();
  }

  void _startNoticeAutoScroll() {
    _noticeSliderTimer?.cancel();
    if (!_noticeAutoPlay) return;
    _noticeSliderTimer = Timer.periodic(const Duration(milliseconds: 3500), (_) {
      if (mounted && _noticePageController.hasClients) {
        final nextPage = (_currentNoticePage + 1) % _notices.length;
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
    final target = (index + _notices.length) % _notices.length;
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
    _noticeSliderTimer?.cancel();
    _noticePageController.dispose();
    super.dispose();
  }

  void _toggleChecklistItem(int index) {
    setState(() {
      _checklist[index].isCompleted = !_checklist[index].isCompleted;
    });
  }

  @override
  Widget build(BuildContext context) {
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
                            ? 'Welcome'
                            : 'Hi, ${widget.userName}',
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
                      const Text(
                        'Your Overseas Protection Dashboard',
                        style: TextStyle(
                          color: AppColors.royalBlueMuted,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
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
    final status = _status;
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

  // --- 1. Hero Card Builder ---
  Widget _buildHeroChecklistCard() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.cloudDancer,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.royalBlue,
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.royalBlue.withValues(alpha: 0.08),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Card Header
          InkWell(
            onTap: widget.onNavigateToCrChecker,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
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
                          'Pre-Departure Company & Travel Checklist',
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
                          color: _completedCount == _checklist.length
                              ? AppColors.emeraldGreen
                              : AppColors.emeraldGreen.withValues(alpha: 0.12),
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
                              color: _completedCount == _checklist.length
                                  ? AppColors.cloudDancer
                                  : AppColors.emeraldGreen,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '$_completedCount/${_checklist.length} Done',
                              style: TextStyle(
                                color: _completedCount == _checklist.length
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
                          'Check your company and documents before you fly',
                          style: TextStyle(
                            color: AppColors.royalBlueMuted,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Row(
                        children: const [
                          Text(
                            'View Details',
                            style: TextStyle(
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

          const Divider(
            height: 1,
            thickness: 1,
            color: Color(0x221A4B9C),
          ),

          // Dynamic Progress Bar & Ratio
          Padding(
            padding: const EdgeInsets.fromLTRB(16.0, 14.0, 16.0, 8.0),
            child: Semantics(
              label: 'Departure readiness',
              // toInt() floors on purpose: never overstate readiness.
              value: '${(_progressPercent * 100).toInt()} percent',
              child: ExcludeSemantics(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Departure Readiness',
                          style: TextStyle(
                            color: AppColors.royalBlueMuted,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          '${(_progressPercent * 100).toInt()}%',
                          style: const TextStyle(
                            color: AppColors.royalBlue,
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
                        builder: (context, value, _) => LinearProgressIndicator(
                          value: value,
                          minHeight: 7,
                          backgroundColor:
                              AppColors.royalBlue.withValues(alpha: 0.12),
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
                    ? 'Show Fewer Items'
                    : 'Show All ${_checklist.length} Checklist Items',
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
    );
  }

  Widget _buildChecklistRow(int index) {
    final item = _checklist[index];
    final isNext = index == _nextIndex;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Semantics(
        button: true,
        checked: item.isCompleted,
        label: '${item.title}. ${item.subtitle}',
        hint: 'Double tap to mark as done',
        onTap: () => _toggleChecklistItem(index),
        excludeSemantics: true,
        child: InkWell(
          onTap: () => _toggleChecklistItem(index),
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: item.isCompleted
                  ? AppColors.emeraldGreen.withValues(alpha: 0.06)
                  : AppColors.cloudDancer,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: item.isCompleted
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
                    color: item.isCompleted
                        ? AppColors.emeraldGreen
                        : AppColors.cloudDancer,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: item.isCompleted
                          ? AppColors.emeraldGreen
                          : AppColors.royalBlue.withValues(alpha: 0.5),
                      width: 1.5,
                    ),
                  ),
                  child: item.isCompleted
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
                        const Text(
                          'NEXT STEP',
                          style: TextStyle(
                            color: AppColors.royalBlue,
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.6,
                          ),
                        ),
                        const SizedBox(height: 2),
                      ],
                      Text(
                        item.title,
                        style: TextStyle(
                          color: item.isCompleted
                              ? AppColors.royalBlueMuted
                              : AppColors.royalBlue,
                          fontSize: 13,
                          fontWeight: item.isCompleted
                              ? FontWeight.w500
                              : FontWeight.w700,
                          height: 1.25,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        item.subtitle,
                        style: const TextStyle(
                          color: AppColors.royalBlueMuted,
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
      ),
    );
  }

  // --- 2. Auto-Sliding Notice Banner Builder ---
  Widget _buildAutoSlidingNoticeBanner() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: const [
                Icon(
                  Icons.campaign_rounded,
                  color: AppColors.royalBlue,
                  size: 18,
                ),
                SizedBox(width: 6),
                Text(
                  'Notice Board',
                  style: TextStyle(
                    color: AppColors.royalBlue,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            InkWell(
              onTap: widget.onNavigateToNotice,
              child: Row(
                children: const [
                  Text(
                    'All Notices',
                    style: TextStyle(
                      color: AppColors.royalBlue,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Icon(
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
        SizedBox(
          height: 86,
          child: PageView.builder(
            controller: _noticePageController,
            itemCount: _notices.length,
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
              final notice = _notices[index];
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2.0),
                child: InkWell(
                  onTap: widget.onNavigateToNotice,
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14.0,
                      vertical: 10.0,
                    ),
                    decoration: BoxDecoration(
                      color: notice.backgroundColor,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: notice.accentColor.withValues(alpha: 0.35),
                        width: 1.2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: notice.accentColor.withValues(alpha: 0.05),
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
                            color: notice.accentColor.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(
                            notice.icon,
                            color: notice.accentColor,
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
                                    notice.tag,
                                    style: TextStyle(
                                      color: notice.accentColor,
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 0.6,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Icon(
                                    Icons.arrow_forward_ios_rounded,
                                    size: 9,
                                    color: notice.accentColor,
                                  ),
                                ],
                              ),
                              const SizedBox(height: 3),
                              Text(
                                notice.message,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: AppColors.royalBlue,
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
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 8),

        // Controls: pause/play (left), previous - dots - next (center).
        // The dots are tappable. The empty box on the right keeps the
        // dots visually centered.
        Row(
          children: [
            IconButton(
              onPressed: _toggleNoticeAutoPlay,
              tooltip: _noticeAutoPlay
                  ? 'Pause auto-slide'
                  : 'Resume auto-slide',
              icon: Icon(
                _noticeAutoPlay
                    ? Icons.pause_circle_outline_rounded
                    : Icons.play_circle_outline_rounded,
              ),
              iconSize: 22,
              color: AppColors.royalBlue,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            ),
            Expanded(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    onPressed: () => _goToNotice(_currentNoticePage - 1),
                    tooltip: 'Previous notice',
                    icon: const Icon(Icons.chevron_left_rounded),
                    iconSize: 24,
                    color: AppColors.royalBlue,
                    padding: EdgeInsets.zero,
                    constraints:
                        const BoxConstraints(minWidth: 36, minHeight: 36),
                  ),
                  ...List.generate(_notices.length, (index) {
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
                                : AppColors.royalBlue.withValues(alpha: 0.22),
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                      ),
                    );
                  }),
                  IconButton(
                    onPressed: () => _goToNotice(_currentNoticePage + 1),
                    tooltip: 'Next notice',
                    icon: const Icon(Icons.chevron_right_rounded),
                    iconSize: 24,
                    color: AppColors.royalBlue,
                    padding: EdgeInsets.zero,
                    constraints:
                        const BoxConstraints(minWidth: 36, minHeight: 36),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 36),
          ],
        ),
      ],
    );
  }

  // --- 3. Quick Features Grid (bKash Style) ---
  Widget _buildQuickFeaturesGrid() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Quick Features',
          style: TextStyle(
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
                label: 'Saved Documents',
                borderColor: AppColors.royalBlue.withValues(alpha: 0.22),
                textColor: AppColors.royalBlue,
                onTap: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Opening Saved Documents vault...'),
                      backgroundColor: AppColors.royalBlue,
                      duration: Duration(seconds: 1),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(width: 12),

            // 2. Fraud Checker
            Expanded(
              child: _QuickFeatureCard(
                icon: Icons.verified_user_outlined,
                iconColor: AppColors.royalBlue,
                label: 'Fraud Checker',
                borderColor: AppColors.royalBlue.withValues(alpha: 0.22),
                textColor: AppColors.royalBlue,
                onTap: widget.onNavigateToCrChecker ?? () {},
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
  final Color? backgroundColor;
  final double iconSize;
  final VoidCallback onTap;

  const _QuickFeatureCard({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.borderColor,
    required this.textColor,
    this.backgroundColor,
    this.iconSize = 24,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        // minHeight (not a fixed height) so larger fonts never overflow.
        alignment: Alignment.center,
        constraints: const BoxConstraints(minHeight: 92),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        decoration: BoxDecoration(
          color: backgroundColor ?? AppColors.cloudDancer,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: borderColor,
            width: 1.2,
          ),
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
              child: Icon(
                icon,
                color: iconColor,
                size: iconSize,
              ),
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
      ),
    );
  }
}