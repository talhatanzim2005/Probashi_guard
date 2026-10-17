import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import 'models/document_analysis.dart';
import 'widgets/tip_shoi_warning_banner.dart';

/// Full audit of one document: Tip Shoi warning, verdict, 3-line summary,
/// identity details (passports/visas), an accordion of extracted terms, and a
/// side-by-side translation.
class DocumentDetailView extends StatelessWidget {
  final DocumentAnalysis analysis;
  final DocumentLanguage language;

  /// False when the backend couldn't store the result in the vault.
  final bool saved;
  final DateTime? scannedAt;

  const DocumentDetailView({
    super.key,
    required this.analysis,
    required this.language,
    this.saved = true,
    this.scannedAt,
  });

  @override
  Widget build(BuildContext context) {
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
            analysis.documentType ?? 'Document',
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
            _OverviewTab(analysis: analysis, language: language, saved: saved, scannedAt: scannedAt),
            _TranslationTab(analysis: analysis, language: language),
          ],
        ),
      ),
    );
  }
}

class _OverviewTab extends StatelessWidget {
  final DocumentAnalysis analysis;
  final DocumentLanguage language;
  final bool saved;
  final DateTime? scannedAt;

  const _OverviewTab({
    required this.analysis,
    required this.language,
    required this.saved,
    required this.scannedAt,
  });

  @override
  Widget build(BuildContext context) {
    final a = analysis;
    // Passports and visas rarely state pay or fees; show the terms only if something was found.
    final hasTerms = a.salary.amount != null ||
        a.fees.isNotEmpty ||
        a.durationText.isNotEmpty ||
        a.cancellationText.isNotEmpty;
    const footnoteStyle = TextStyle(color: AppColors.royalBlueMuted, fontSize: 12.5);
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
            value: a.fees.isEmpty ? 'No fees found' : a.fees.map(_formatFee).join('\n'),
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
            value: a.cancellationText.isEmpty ? 'Not stated' : a.cancellationText,
            explanation: a.cancellationExplanation,
          ),
        ],
        if (scannedAt != null) Text('Scanned ${_formatDate(scannedAt!)}', style: footnoteStyle),
        if (a.sourceEngine != null) Text('Read by ${a.sourceEngine}', style: footnoteStyle),
        if (!saved) const Text('This result was not saved to your document vault.', style: footnoteStyle),
      ],
    );
  }

  static String _formatAmount(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);

  static String _formatSalary(SalaryInfo s) {
    if (s.amount == null) return 'Not stated';
    final period = s.period.isEmpty || s.period == 'unknown' ? '' : ' / ${s.period}';
    final sar = s.monthlySarEquivalent != null && s.currency != 'SAR'
        ? ' (≈ SAR ${_formatAmount(s.monthlySarEquivalent!)} / month)'
        : '';
    return '${_formatAmount(s.amount!)} ${s.currency ?? ''}$period$sar';
  }

  static String _formatFee(FeeItem fee) {
    final amount = fee.amount != null ? ' — ${_formatAmount(fee.amount!)} ${fee.currency ?? ''}' : '';
    final payer = fee.paidBy == 'worker' ? ' (you pay)' : '';
    return '• ${fee.description}$amount$payer';
  }
}

String _formatDate(DateTime d) {
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
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
            analysis.fullTranslation.isEmpty ? 'No translation available.' : analysis.fullTranslation,
            style: const TextStyle(color: AppColors.royalBlue, fontSize: 15, height: 1.5),
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
            separatorBuilder: (_, _) => Divider(color: AppColors.royalBlue.withValues(alpha: 0.12)),
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
      style: const TextStyle(color: AppColors.royalBlue, fontSize: 13.5, fontWeight: FontWeight.w800),
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
          border: Border.all(color: AppColors.crimsonRed.withValues(alpha: 0.4)),
        ),
        child: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: AppColors.crimsonRed, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                segment.translated.isEmpty ? 'Blank space' : segment.translated,
                style: const TextStyle(color: AppColors.crimsonRed, fontWeight: FontWeight.w700),
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
            style: const TextStyle(color: AppColors.royalBlueMuted, fontSize: 14, height: 1.45),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: SelectableText(
            segment.translated,
            style: const TextStyle(
              color: AppColors.royalBlue,
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
              style: TextStyle(color: color, fontSize: 19, fontWeight: FontWeight.w800),
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
      SigningVerdict.proceedWithCaution => (AppColors.royalBlue, Icons.report_problem_rounded),
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
    const labelStyle = TextStyle(color: AppColors.royalBlueMuted, fontSize: 13.5);
    const valueStyle = TextStyle(color: AppColors.royalBlue, fontSize: 14.5, fontWeight: FontWeight.w700);

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
        border: Border.all(color: AppColors.royalBlue.withValues(alpha: 0.16), width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(isVisa ? Icons.approval_rounded : Icons.badge_rounded, color: AppColors.royalBlue, size: 20),
              const SizedBox(width: 8),
              Text(
                isVisa ? 'Visa details' : 'Identity details',
                style: const TextStyle(color: AppColors.royalBlue, fontSize: 15.5, fontWeight: FontWeight.w800),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (fields.isEmpty) const Text('No details could be read.', style: labelStyle),
          for (final (label, value) in fields) row(label, value),
          const Divider(height: 18),
          if (readOnDevice)
            row('Passport code (MRZ)', 'Check digits verified on this phone')
          else ...[
            row('Signature', _visible(authenticity.signaturePresent)),
            row('Official stamp', stamp),
            if (authenticity.stampText.isNotEmpty) row('Stamp text', authenticity.stampText),
          ],
          if (authenticity.notes.isNotEmpty && !readOnDevice) Text(authenticity.notes, style: labelStyle),
          const SizedBox(height: 4),
          Text(
            readOnDevice
                ? 'A valid code shows the details were read correctly. It cannot prove the passport is genuine.'
                : 'This checks only what is visible in the photo. It cannot prove the document is genuine.',
            style: const TextStyle(color: AppColors.royalBlueMuted, fontSize: 12, fontStyle: FontStyle.italic),
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
              Icon(Icons.short_text_rounded, color: AppColors.cloudDancer, size: 20),
              SizedBox(width: 6),
              Text(
                'Summary',
                style: TextStyle(color: AppColors.cloudDancer, fontSize: 15.5, fontWeight: FontWeight.w800),
              ),
            ],
          ),
          const SizedBox(height: 10),
          for (var i = 0; i < lines.length; i++)
            Padding(
              padding: EdgeInsets.only(bottom: i == lines.length - 1 ? 0 : 8),
              child: Text(
                '${i + 1}. ${lines[i]}',
                style: const TextStyle(color: AppColors.cloudDancer, fontSize: 15, height: 1.45),
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
        color: isHigh ? AppColors.crimsonRed.withValues(alpha: 0.5) : AppColors.royalBlue.withValues(alpha: 0.16),
        width: 1.2,
      ),
    );
    const valueStyle = TextStyle(color: AppColors.royalBlue, fontSize: 15, fontWeight: FontWeight.w600, height: 1.4);

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
                style: const TextStyle(color: AppColors.royalBlue, fontSize: 15.5, fontWeight: FontWeight.w800),
              ),
            ),
            if (risk != null && risk != RiskLevel.unknown) _RiskChip(risk: risk),
          ],
        ),
        // Preview while collapsed; the full value is in the body.
        subtitle: _expanded
            ? null
            : Text(widget.value, maxLines: 1, overflow: TextOverflow.ellipsis, style: valueStyle),
        children: [
          Text(widget.value, style: valueStyle),
          if (widget.explanation.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              widget.explanation,
              style: const TextStyle(color: AppColors.royalBlueMuted, fontSize: 14, height: 1.4),
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
        style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700),
      ),
    );
  }
}
