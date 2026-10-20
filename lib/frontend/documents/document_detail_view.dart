import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import 'models/document_analysis.dart';
import 'widgets/tip_shoi_warning_banner.dart';

/// Full audit of one document: Tip Shoi warning, verdict, 3-line summary,
/// identity details (passports/visas), an accordion of extracted terms, and a
/// side-by-side translation.
///
/// A fresh scan arrives unsaved: pass [onSave] and the worker reads the audit
/// first, then chooses whether it goes into the vault.
class DocumentDetailView extends StatefulWidget {
  final DocumentAnalysis analysis;
  final DocumentLanguage language;

  /// False when the result is not in the vault: either the worker has not
  /// chosen yet ([onSave] set) or the backend could not store it.
  final bool saved;
  final DateTime? scannedAt;

  /// How many pages this audit covered.
  final int pages;

  /// Keeps this result in the vault; returns false if the save failed, with its
  /// reason in [saveError]. When null, no choice is offered (a vault document).
  final Future<bool> Function()? onSave;

  /// Reason the last [onSave] failed, read after it returns false.
  final String? Function()? saveError;

  const DocumentDetailView({
    super.key,
    required this.analysis,
    required this.language,
    this.saved = true,
    this.scannedAt,
    this.pages = 1,
    this.onSave,
    this.saveError,
  });

  @override
  State<DocumentDetailView> createState() => _DocumentDetailViewState();
}

class _DocumentDetailViewState extends State<DocumentDetailView> {
  late bool _saved = widget.saved;
  bool _saving = false;

  /// Set while _discard() pops, which says so itself: without this, leaving the
  /// screen would announce it twice.
  bool _discarding = false;

  /// The choice is pending until the worker saves: dropping the result needs no
  /// request, because an unsaved scan was never stored in the first place.
  bool get _choicePending => widget.onSave != null && !_saved;

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    final ok = await widget.onSave!();
    if (!mounted) return;
    setState(() {
      _saving = false;
      _saved = ok;
    });
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          ok
              ? _savedToast[widget.language]!
              : widget.saveError?.call() ?? _saveFailedToast[widget.language]!,
        ),
        backgroundColor: ok ? AppColors.emeraldGreen : AppColors.crimsonRed,
      ),
    );
  }

  Future<void> _discard() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        // Scrolls on a phone held sideways with large system text.
        scrollable: true,
        backgroundColor: AppColors.cloudDancer,
        title: Text(
          _discardTitle[widget.language]!,
          style: const TextStyle(
            color: AppColors.royalBlue,
            fontWeight: FontWeight.w800,
          ),
        ),
        content: Text(
          _discardBody[widget.language]!,
          style: const TextStyle(color: AppColors.inkMuted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              _keepReading[widget.language]!,
              style: const TextStyle(
                color: AppColors.royalBlue,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              _discardConfirm[widget.language]!,
              style: const TextStyle(
                color: AppColors.crimsonRed,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    _discarding = true;
    Navigator.pop(context);
    _announceNotSaved();
  }

  void _announceNotSaved() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(_discardedToast[widget.language]!),
        backgroundColor: AppColors.royalBlue,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // Going back keeps nothing, which is easy to mistake for a save: say so.
      onPopInvokedWithResult: (didPop, _) {
        if (didPop && _choicePending && !_discarding) _announceNotSaved();
      },
      child: _buildScreen(context),
    );
  }

  Widget _buildScreen(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: AppColors.cloudDancer,
        appBar: AppBar(
          backgroundColor: AppColors.cloudDancer,
          foregroundColor: AppColors.royalBlue,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          title: Text(
            widget.analysis.documentType ?? 'Document',
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
          ),
          bottom: const TabBar(
            labelColor: AppColors.royalBlue,
            unselectedLabelColor: AppColors.royalBlueMuted,
            indicatorColor: AppColors.royalBlue,
            labelStyle: TextStyle(fontWeight: FontWeight.w700),
            tabs: [
              Tab(text: 'Overview'),
              Tab(text: 'Translation'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _OverviewTab(
              analysis: widget.analysis,
              language: widget.language,
              saved: _saved,
              choicePending: _choicePending,
              scannedAt: widget.scannedAt,
              pages: widget.pages,
            ),
            _TranslationTab(
              analysis: widget.analysis,
              language: widget.language,
            ),
          ],
        ),
        bottomNavigationBar: _choicePending
            ? _SaveChoiceBar(
                language: widget.language,
                saving: _saving,
                onSave: _save,
                onDiscard: _discard,
              )
            : null,
      ),
    );
  }
}

const _savedToast = {
  DocumentLanguage.bangla: 'নথি আপনার ভল্টে সংরক্ষণ করা হয়েছে।',
  DocumentLanguage.english: 'Saved to your document vault.',
  DocumentLanguage.chinese: '已保存到您的文件保险库。',
};

const _saveFailedToast = {
  DocumentLanguage.bangla: 'সংরক্ষণ করা যায়নি। আবার চেষ্টা করুন।',
  DocumentLanguage.english: 'Could not save it. Please try again.',
  DocumentLanguage.chinese: '保存失败，请重试。',
};

const _discardTitle = {
  DocumentLanguage.bangla: 'ফলাফল মুছে ফেলবেন?',
  DocumentLanguage.english: 'Discard this result?',
  DocumentLanguage.chinese: '放弃此结果？',
};

const _discardBody = {
  DocumentLanguage.bangla:
      'এটি ভল্টে থাকবে না। আবার দেখতে চাইলে নথিটি আবার স্ক্যান করতে হবে।',
  DocumentLanguage.english:
      'It will not be kept in your vault. To see it again you will have to scan the document again.',
  DocumentLanguage.chinese: '它不会保存在保险库中。若要再次查看，需重新扫描该文件。',
};

const _keepReading = {
  DocumentLanguage.bangla: 'পড়া চালিয়ে যান',
  DocumentLanguage.english: 'Keep reading',
  DocumentLanguage.chinese: '继续阅读',
};

const _discardConfirm = {
  DocumentLanguage.bangla: 'মুছে ফেলুন',
  DocumentLanguage.english: 'Discard',
  DocumentLanguage.chinese: '放弃',
};

const _discardedToast = {
  DocumentLanguage.bangla: 'ফলাফল সংরক্ষণ করা হয়নি।',
  DocumentLanguage.english: 'The result was not saved.',
  DocumentLanguage.chinese: '结果未保存。',
};

const _saveLabel = {
  DocumentLanguage.bangla: 'ভল্টে সংরক্ষণ করুন',
  DocumentLanguage.english: 'Save to vault',
  DocumentLanguage.chinese: '保存到保险库',
};

const _dontSaveLabel = {
  DocumentLanguage.bangla: 'সংরক্ষণ করবেন না',
  DocumentLanguage.english: "Don't save",
  DocumentLanguage.chinese: '不保存',
};

const _choiceHint = {
  DocumentLanguage.bangla: 'এই ফলাফল এখনো সংরক্ষণ করা হয়নি।',
  DocumentLanguage.english: 'This result has not been saved yet.',
  DocumentLanguage.chinese: '此结果尚未保存。',
};

/// Save or drop a fresh scan. Nothing reaches the vault until "Save" is tapped,
/// so a worker reading a contract in a recruiter's office can leave no trace.
class _SaveChoiceBar extends StatelessWidget {
  final DocumentLanguage language;
  final bool saving;
  final VoidCallback onSave;
  final VoidCallback onDiscard;

  const _SaveChoiceBar({
    required this.language,
    required this.saving,
    required this.onSave,
    required this.onDiscard,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        16,
        10,
        16,
        10 + MediaQuery.of(context).padding.bottom,
      ),
      decoration: BoxDecoration(
        color: AppColors.cloudDancer,
        border: Border(
          top: BorderSide(
            color: AppColors.royalBlue.withValues(alpha: 0.16),
            width: 1.2,
          ),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _choiceHint[language]!,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.inkMuted, fontSize: 12.5),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: saving ? null : onDiscard,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.royalBlue,
                    side: BorderSide(
                      color: AppColors.royalBlue.withValues(alpha: 0.4),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: Text(
                    _dontSaveLabel[language]!,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: saving ? null : onSave,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.royalBlue,
                    foregroundColor: AppColors.cloudDancer,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  icon: saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.cloudDancer,
                          ),
                        )
                      : const Icon(Icons.save_rounded, size: 20),
                  label: Text(
                    _saveLabel[language]!,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _OverviewTab extends StatelessWidget {
  final DocumentAnalysis analysis;
  final DocumentLanguage language;
  final bool saved;

  /// The save/discard bar is up, so it speaks for the unsaved state.
  final bool choicePending;
  final DateTime? scannedAt;
  final int pages;

  const _OverviewTab({
    required this.analysis,
    required this.language,
    required this.saved,
    required this.choicePending,
    required this.scannedAt,
    required this.pages,
  });

  @override
  Widget build(BuildContext context) {
    final a = analysis;
    // Passports and visas rarely state pay or fees; show the terms only if something was found.
    final hasTerms =
        a.salary.amount != null ||
        a.fees.isNotEmpty ||
        a.durationText.isNotEmpty ||
        a.cancellationText.isNotEmpty;
    const footnoteStyle = TextStyle(color: AppColors.inkMuted, fontSize: 12.5);
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      children: [
        if (a.tipShoiDetected) ...[
          TipShoiWarningBanner(language: language, findings: a.tipShoiFindings),
          const SizedBox(height: 12),
        ],
        _VerdictCard(verdict: a.verdict, language: language),
        const SizedBox(height: 12),
        if (a.summary3Lines.isNotEmpty) _SummaryCard(lines: a.summary3Lines),
        if (a.category.isIdentityDocument) _IdentityCard(analysis: a),
        if (!a.category.isIdentityDocument || hasTerms) ...[
          _TermSection(
            icon: Icons.payments_rounded,
            title: 'Salary',
            risk: a.salary.risk,
            value: _formatSalary(a.salary),
            explanation: a.salary.explanation,
          ),
          _TermSection(
            icon: Icons.receipt_long_rounded,
            title: 'Fees',
            risk: a.feesRisk,
            value: a.fees.isEmpty
                ? 'No fees found'
                : a.fees.map(_formatFee).join('\n'),
            explanation: a.feesExplanation,
          ),
          _TermSection(
            icon: Icons.event_rounded,
            title: 'Duration',
            value: a.durationText.isEmpty ? 'Not stated' : a.durationText,
          ),
          _TermSection(
            icon: Icons.gavel_rounded,
            title: 'Cancellation',
            risk: a.cancellationRisk,
            value: a.cancellationText.isEmpty
                ? 'Not stated'
                : a.cancellationText,
            explanation: a.cancellationExplanation,
          ),
        ],
        if (scannedAt != null)
          Text('Scanned ${_formatDate(scannedAt!)}', style: footnoteStyle),
        if (pages > 1)
          Text('$pages pages checked together', style: footnoteStyle),
        if (a.sourceEngine != null)
          Text('Read by ${a.sourceEngine}', style: footnoteStyle),
        if (!saved && !choicePending)
          const Text(
            'This result was not saved to your document vault.',
            style: footnoteStyle,
          ),
      ],
    );
  }

  static String _formatAmount(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);

  static String _formatSalary(SalaryInfo s) {
    if (s.amount == null) return 'Not stated';
    final period = s.period.isEmpty || s.period == 'unknown'
        ? ''
        : ' / ${s.period}';
    final sar = s.monthlySarEquivalent != null && s.currency != 'SAR'
        ? ' (≈ SAR ${_formatAmount(s.monthlySarEquivalent!)} / month)'
        : '';
    return '${_formatAmount(s.amount!)} ${s.currency ?? ''}$period$sar';
  }

  static String _formatFee(FeeItem fee) {
    final amount = fee.amount != null
        ? ' — ${_formatAmount(fee.amount!)} ${fee.currency ?? ''}'
        : '';
    final payer = fee.paidBy == 'worker' ? ' (you pay)' : '';
    return '• ${fee.description}$amount$payer';
  }
}

String _formatDate(DateTime d) {
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  String two(int n) => n.toString().padLeft(2, '0');
  return '${d.day} ${months[d.month - 1]} ${d.year}, ${two(d.hour)}:${two(d.minute)}';
}

class _TranslationTab extends StatelessWidget {
  final DocumentAnalysis analysis;
  final DocumentLanguage language;

  const _TranslationTab({required this.analysis, required this.language});

  @override
  Widget build(BuildContext context) {
    final segments = analysis.translationSegments;
    if (segments.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(20),
        children: [
          SelectableText(
            analysis.fullTranslation.isEmpty
                ? 'No translation available.'
                : analysis.fullTranslation,
            style: const TextStyle(
              color: AppColors.ink,
              fontSize: 15,
              height: 1.5,
            ),
          ),
        ],
      );
    }

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          color: AppColors.royalBlue.withValues(alpha: 0.06),
          child: Row(
            children: [
              const Expanded(child: _ColumnHeader('Original')),
              const SizedBox(width: 12),
              Expanded(child: _ColumnHeader(language.label)),
            ],
          ),
        ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            itemCount: segments.length,
            separatorBuilder: (_, _) =>
                Divider(color: AppColors.royalBlue.withValues(alpha: 0.12)),
            itemBuilder: (_, i) => _SegmentRow(segment: segments[i]),
          ),
        ),
      ],
    );
  }
}

class _ColumnHeader extends StatelessWidget {
  final String label;

  const _ColumnHeader(this.label);

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: const TextStyle(
        color: AppColors.royalBlue,
        fontSize: 13.5,
        fontWeight: FontWeight.w800,
      ),
    );
  }
}

class _SegmentRow extends StatelessWidget {
  final TranslationSegment segment;

  const _SegmentRow({required this.segment});

  @override
  Widget build(BuildContext context) {
    // Blank lines are where text can be added after signing: make them stand out.
    if (segment.isBlank) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.crimsonRed.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: AppColors.crimsonRed.withValues(alpha: 0.4),
          ),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.warning_amber_rounded,
              color: AppColors.crimsonRed,
              size: 18,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                segment.translated.isEmpty ? 'Blank space' : segment.translated,
                style: const TextStyle(
                  color: AppColors.crimsonRed,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: SelectableText(
            segment.original,
            style: const TextStyle(
              color: AppColors.inkMuted,
              fontSize: 14,
              height: 1.45,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: SelectableText(
            segment.translated,
            style: const TextStyle(
              color: AppColors.ink,
              fontSize: 14.5,
              fontWeight: FontWeight.w600,
              height: 1.45,
            ),
          ),
        ),
      ],
    );
  }
}

class _VerdictCard extends StatelessWidget {
  final SigningVerdict verdict;
  final DocumentLanguage language;

  const _VerdictCard({required this.verdict, required this.language});

  @override
  Widget build(BuildContext context) {
    final (color, icon) = verdictStyle(verdict);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color, width: 1.6),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 32),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              verdict.label(language),
              style: TextStyle(
                color: color,
                fontSize: 19,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Palette color and icon for a verdict, shared with the vault list.
(Color, IconData) verdictStyle(SigningVerdict verdict) => switch (verdict) {
  SigningVerdict.safeToSign => (AppColors.emeraldGreen, Icons.verified_rounded),
  SigningVerdict.proceedWithCaution => (
    AppColors.royalBlue,
    Icons.report_problem_rounded,
  ),
  SigningVerdict.doNotSign => (AppColors.crimsonRed, Icons.block_rounded),
};

/// Holder details from a passport, BMET card or visa, plus what is visibly on it.
class _IdentityCard extends StatelessWidget {
  final DocumentAnalysis analysis;

  const _IdentityCard({required this.analysis});

  static String _visible(bool? present) => switch (present) {
    true => 'Visible',
    false => 'Not found',
    null => 'Unclear',
  };

  @override
  Widget build(BuildContext context) {
    final fields = analysis.identity.presentFields;
    final authenticity = analysis.authenticity;
    final isVisa = analysis.category == DocumentCategory.visa;
    // An MRZ read says nothing about signatures or stamps, only that the code is consistent.
    final readOnDevice = analysis.sourceEngine == onDeviceMrzEngine;
    final stamp = switch (authenticity.stampPresent) {
      true => authenticity.stampKindLabel ?? _visible(true),
      final present => _visible(present),
    };
    const labelStyle = TextStyle(color: AppColors.inkMuted, fontSize: 13.5);
    const valueStyle = TextStyle(
      color: AppColors.ink,
      fontSize: 14.5,
      fontWeight: FontWeight.w700,
    );

    Widget row(String label, String value) => Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 130, child: Text(label, style: labelStyle)),
          Expanded(child: SelectableText(value, style: valueStyle)),
        ],
      ),
    );

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cloudDancer,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.royalBlue.withValues(alpha: 0.16),
          width: 1.2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isVisa ? Icons.approval_rounded : Icons.badge_rounded,
                color: AppColors.royalBlue,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                isVisa ? 'Visa details' : 'Identity details',
                style: const TextStyle(
                  color: AppColors.royalBlue,
                  fontSize: 15.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (fields.isEmpty)
            const Text('No details could be read.', style: labelStyle),
          for (final (label, value) in fields) row(label, value),
          const Divider(height: 18),
          if (readOnDevice)
            row('Passport code (MRZ)', 'Check digits verified on this phone')
          else ...[
            row('Signature', _visible(authenticity.signaturePresent)),
            row('Official stamp', stamp),
            if (authenticity.stampText.isNotEmpty)
              row('Stamp text', authenticity.stampText),
          ],
          if (authenticity.notes.isNotEmpty && !readOnDevice)
            Text(authenticity.notes, style: labelStyle),
          const SizedBox(height: 4),
          Text(
            readOnDevice
                ? 'A valid code shows the details were read correctly. It cannot prove the passport is genuine.'
                : 'This checks only what is visible in the photo. It cannot prove the document is genuine.',
            style: const TextStyle(
              color: AppColors.inkMuted,
              fontSize: 12,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final List<String> lines;

  const _SummaryCard({required this.lines});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.royalBlue,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(
                Icons.short_text_rounded,
                color: AppColors.cloudDancer,
                size: 20,
              ),
              SizedBox(width: 6),
              Text(
                'Summary',
                style: TextStyle(
                  color: AppColors.cloudDancer,
                  fontSize: 15.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          for (var i = 0; i < lines.length; i++)
            Padding(
              padding: EdgeInsets.only(bottom: i == lines.length - 1 ? 0 : 8),
              child: Text(
                '${i + 1}. ${lines[i]}',
                style: const TextStyle(
                  color: AppColors.cloudDancer,
                  fontSize: 15,
                  height: 1.45,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// One accordion section of extracted terms. High-risk terms start expanded;
/// collapsed sections still preview their value.
class _TermSection extends StatefulWidget {
  final IconData icon;
  final String title;
  final String value;
  final String explanation;
  final RiskLevel? risk;

  const _TermSection({
    required this.icon,
    required this.title,
    required this.value,
    this.explanation = '',
    this.risk,
  });

  @override
  State<_TermSection> createState() => _TermSectionState();
}

class _TermSectionState extends State<_TermSection> {
  late bool _expanded = widget.risk == RiskLevel.high;

  @override
  Widget build(BuildContext context) {
    final risk = widget.risk;
    final isHigh = risk == RiskLevel.high;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
      side: BorderSide(
        color: isHigh
            ? AppColors.crimsonRed.withValues(alpha: 0.5)
            : AppColors.royalBlue.withValues(alpha: 0.16),
        width: 1.2,
      ),
    );
    const valueStyle = TextStyle(
      color: AppColors.ink,
      fontSize: 15,
      fontWeight: FontWeight.w600,
      height: 1.4,
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: ExpansionTile(
        initiallyExpanded: _expanded,
        onExpansionChanged: (expanded) => setState(() => _expanded = expanded),
        shape: shape,
        collapsedShape: shape,
        backgroundColor: AppColors.cloudDancer,
        collapsedBackgroundColor: AppColors.cloudDancer,
        iconColor: AppColors.royalBlue,
        collapsedIconColor: AppColors.royalBlueMuted,
        tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
        childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        leading: Icon(widget.icon, color: AppColors.royalBlue, size: 20),
        title: Row(
          children: [
            Expanded(
              child: Text(
                widget.title,
                style: const TextStyle(
                  color: AppColors.royalBlue,
                  fontSize: 15.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            if (risk != null && risk != RiskLevel.unknown)
              _RiskChip(risk: risk),
          ],
        ),
        // Preview while collapsed; the full value is in the body.
        subtitle: _expanded
            ? null
            : Text(
                widget.value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: valueStyle,
              ),
        children: [
          Text(widget.value, style: valueStyle),
          if (widget.explanation.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              widget.explanation,
              style: const TextStyle(
                color: AppColors.inkMuted,
                fontSize: 14,
                height: 1.4,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _RiskChip extends StatelessWidget {
  final RiskLevel risk;

  const _RiskChip({required this.risk});

  @override
  Widget build(BuildContext context) {
    final (color, label) = switch (risk) {
      RiskLevel.high => (AppColors.crimsonRed, 'High risk'),
      RiskLevel.medium => (AppColors.royalBlue, 'Medium risk'),
      _ => (AppColors.emeraldGreen, 'Low risk'),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
