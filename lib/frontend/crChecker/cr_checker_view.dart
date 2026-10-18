import 'package:flutter/material.dart';

import '../../l10n/app_strings.dart';
import '../../theme/app_colors.dart';

class _ChecklistItem {
  bool isCompleted;
  _ChecklistItem({required this.isCompleted});
}

/// Pre-Departure Company & Travel Checklist screen.
/// Displays company registration (CR) verification, visa validation,
/// BMET smart clearance, and pre-departure readiness.
class CrCheckerView extends StatefulWidget {
  const CrCheckerView({super.key});

  @override
  State<CrCheckerView> createState() => _CrCheckerViewState();
}

class _CrCheckerViewState extends State<CrCheckerView> {
  bool _isChecklistExpanded = true;

  /// Default checklist matching initial state (3 completed, 5 pending = 37% readiness).
  final List<_ChecklistItem> _checklist = [
    _ChecklistItem(isCompleted: true),
    _ChecklistItem(isCompleted: true),
    _ChecklistItem(isCompleted: true),
    _ChecklistItem(isCompleted: false),
    _ChecklistItem(isCompleted: false),
    _ChecklistItem(isCompleted: false),
    _ChecklistItem(isCompleted: false),
    _ChecklistItem(isCompleted: false),
  ];

  int get _completedCount => _checklist.where((item) => item.isCompleted).length;
  double get _progressPercent =>
      _checklist.isEmpty ? 0.0 : _completedCount / _checklist.length;

  int get _nextIndex => _checklist.indexWhere((item) => !item.isCompleted);

  List<int> get _visibleIndexes {
    final pending = <int>[];
    final done = <int>[];
    for (var i = 0; i < _checklist.length; i++) {
      (_checklist[i].isCompleted ? done : pending).add(i);
    }
    final ordered = [...pending, ...done];
    return _isChecklistExpanded ? ordered : ordered.take(3).toList();
  }

  void _toggleItem(int index) {
    setState(() {
      _checklist[index].isCompleted = !_checklist[index].isCompleted;
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);

    return Scaffold(
      backgroundColor: AppColors.cloudDancer,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_rounded,
            color: AppColors.royalBlue,
            size: 24,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          s.checklistTitle,
          style: const TextStyle(
            color: AppColors.royalBlue,
            fontSize: 16,
            fontWeight: FontWeight.w800,
          ),
        ),
        centerTitle: false,
      ),
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          child: _buildChecklistCard(s),
        ),
      ),
    );
  }

  Widget _buildChecklistCard(AppStrings s) {
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
          // Header
          Padding(
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
                    // Summary badge (e.g. "3/8 Done")
                    Container(
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
                            s.checklistDone(_completedCount, _checklist.length),
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
                        s.checklistSubtitle,
                        style: const TextStyle(
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
                        const Icon(
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

          const Divider(
            height: 1,
            thickness: 1,
            color: Color(0x221A4B9C),
          ),

          // Departure Readiness Progress
          Padding(
            padding: const EdgeInsets.fromLTRB(16.0, 14.0, 16.0, 8.0),
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
                  child: LinearProgressIndicator(
                    value: _progressPercent,
                    minHeight: 7,
                    backgroundColor: AppColors.royalBlue.withValues(alpha: 0.12),
                    valueColor: const AlwaysStoppedAnimation<Color>(
                      AppColors.emeraldGreen,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Checklist items
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Column(
              children: [
                for (final i in _visibleIndexes) _buildChecklistRow(s, i),
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
                    : s.showAllItems(_checklist.length),
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

  Widget _buildChecklistRow(AppStrings s, int index) {
    final item = _checklist[index];
    final isNext = index == _nextIndex;
    final text = s.checklist[index];

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: InkWell(
        onTap: () => _toggleItem(index),
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
                        color: item.isCompleted
                            ? AppColors.inkMuted
                            : AppColors.ink,
                        fontSize: 13,
                        fontWeight: item.isCompleted
                            ? FontWeight.w500
                            : FontWeight.w700,
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
}
