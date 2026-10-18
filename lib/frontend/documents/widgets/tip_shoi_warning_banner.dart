import 'package:flutter/material.dart';
import '../../../theme/app_colors.dart';
import '../models/document_analysis.dart';

/// Red, impossible-to-miss warning shown when the backend reports a
/// Tip Shoi (টিপ সই) trap: blank space before a signature, a blank
/// promissory note, or a loan acknowledgment the worker didn't agree to.
class TipShoiWarningBanner extends StatelessWidget {
  final DocumentLanguage language;
  final List<TipShoiFinding> findings;

  const TipShoiWarningBanner({
    super.key,
    required this.language,
    required this.findings,
  });

  /// Always shown in Bangla: the workers this protects read it first.
  static const warning = 'সতর্কতা: খালি কাগজে বা অর্থ দাবির দলিলে কোনো অবস্থাতেই টিপ সই বা স্বাক্ষর দিবেন না!';

  static const _translations = {
    DocumentLanguage.english:
        'Warning: Never give your thumbprint or signature on a blank paper or on a document that demands money!',
    DocumentLanguage.chinese: '警告：无论如何都不要在空白纸张或索要钱款的文件上按手印或签字！',
  };

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.crimsonRed,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: AppColors.crimsonRed.withValues(alpha: 0.3),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.front_hand_rounded, color: AppColors.cloudDancer, size: 28),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    warning,
                    style: TextStyle(
                      color: AppColors.cloudDancer,
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ),
            if (_translations[language] case final translation?) ...[
              const SizedBox(height: 8),
              Text(
                translation,
                style: const TextStyle(
                  color: AppColors.cloudDancer,
                  fontSize: 14.5,
                  fontWeight: FontWeight.w700,
                  height: 1.4,
                ),
              ),
            ],
            for (final finding in findings)
              if (finding.explanation.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(top: 2),
                        child: Icon(Icons.error_outline, color: AppColors.cloudDancer, size: 16),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          finding.location.isEmpty
                              ? finding.explanation
                              : '${finding.location}: ${finding.explanation}',
                          style: const TextStyle(
                            color: AppColors.cloudDancer,
                            fontSize: 13.5,
                            height: 1.35,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
          ],
        ),
      ),
    );
  }
}
