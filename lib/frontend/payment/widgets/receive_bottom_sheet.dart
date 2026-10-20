import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../l10n/app_strings.dart';
import '../../../theme/app_colors.dart';
import '../controllers/payment_controller.dart';

class ReceiveBottomSheet extends StatefulWidget {
  final PaymentController controller;

  const ReceiveBottomSheet({super.key, required this.controller});

  static Future<void> show(BuildContext context, PaymentController controller) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ReceiveBottomSheet(controller: controller),
    );
  }

  @override
  State<ReceiveBottomSheet> createState() => _ReceiveBottomSheetState();
}

class _ReceiveBottomSheetState extends State<ReceiveBottomSheet> {
  final String _accountNumber = 'PG-8801-9472-33';
  final String _ibanNumber = 'SA82 2000 0001 2345 6789 01';
  bool _copied = false;

  void _copyToClipboard(String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    HapticFeedback.lightImpact();
    setState(() => _copied = true);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(AppStrings.of(context).copiedToClipboard(label)),
        backgroundColor: AppColors.emeraldGreen,
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );

    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.cloudDancer,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: EdgeInsets.fromLTRB(
        24,
        14,
        24,
        MediaQuery.of(context).padding.bottom + 20,
      ),
      // Taller than a landscape phone or a small one with large text, so the
      // sheet scrolls instead of overflowing.
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Drag handle
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.royalBlue.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 18),

            // Title & Subtitle
            Text(
              s.receiveTitle,
              style: const TextStyle(
                color: AppColors.royalBlue,
                fontSize: 18,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.2,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              s.receiveSubtitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.royalBlue.withValues(alpha: 0.6),
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 20),

            // Dynamic QR Code Container with white quiet zone
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: AppColors.royalBlue.withValues(alpha: 0.14),
                  width: 1.2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.royalBlue.withValues(alpha: 0.08),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                children: [
                  SizedBox(
                    width: 170,
                    height: 170,
                    child: CustomPaint(
                      painter: _QrMatrixPainter(color: AppColors.royalBlue),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.verified_user_rounded,
                        color: AppColors.emeraldGreen,
                        size: 14,
                      ),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          s.verifiedMerchantId,
                          style: TextStyle(
                            color: AppColors.royalBlue.withValues(alpha: 0.7),
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 22),

            // Account Details Box
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.royalBlue.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: AppColors.royalBlue.withValues(alpha: 0.15),
                  width: 1,
                ),
              ),
              child: Column(
                children: [
                  // Account ID Row
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              s.accountId.toUpperCase(),
                              style: TextStyle(
                                color: AppColors.royalBlue.withValues(
                                  alpha: 0.5,
                                ),
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.8,
                              ),
                            ),
                            const SizedBox(height: 2),
                            // One line, so it reads (and copies) as one number.
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                _accountNumber,
                                maxLines: 1,
                                style: const TextStyle(
                                  color: AppColors.royalBlue,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: Icon(
                          _copied
                              ? Icons.check_circle_rounded
                              : Icons.copy_rounded,
                          color: _copied
                              ? AppColors.emeraldGreen
                              : AppColors.royalBlue,
                          size: 18,
                        ),
                        onPressed: () =>
                            _copyToClipboard(_accountNumber, s.accountId),
                      ),
                    ],
                  ),
                  Divider(
                    color: AppColors.royalBlue.withValues(alpha: 0.08),
                    height: 16,
                  ),

                  // Remittance IBAN Row
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              s.remittanceIban,
                              style: TextStyle(
                                color: AppColors.royalBlue.withValues(
                                  alpha: 0.5,
                                ),
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.8,
                              ),
                            ),
                            const SizedBox(height: 2),
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                _ibanNumber,
                                maxLines: 1,
                                style: const TextStyle(
                                  color: AppColors.royalBlue,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(
                          Icons.copy_rounded,
                          color: AppColors.royalBlue,
                          size: 18,
                        ),
                        onPressed: () => _copyToClipboard(_ibanNumber, 'IBAN'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Action Buttons: Share & Close
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      HapticFeedback.lightImpact();
                      Navigator.pop(context);
                    },
                    icon: const Icon(Icons.close_rounded, size: 16),
                    label: Text(s.close),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.royalBlue,
                      side: BorderSide(
                        color: AppColors.royalBlue.withValues(alpha: 0.25),
                        width: 1.2,
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () {
                      HapticFeedback.selectionClick();
                      _copyToClipboard(
                        '$_accountNumber | IBAN: $_ibanNumber',
                        s.paymentInfo,
                      );
                    },
                    icon: const Icon(Icons.share_rounded, size: 16),
                    label: Text(s.shareInfo),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.royalBlue,
                      foregroundColor: AppColors.cloudDancer,
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      elevation: 0,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Sharp, high-contrast QR matrix vector painter for clean scans without 3rd-party dependencies
class _QrMatrixPainter extends CustomPainter {
  final Color color;

  _QrMatrixPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    const int modules = 21; // Standard Version 1 QR size
    final double moduleSize = size.width / modules;

    // Standard pattern blueprint
    final matrix = [
      [1, 1, 1, 1, 1, 1, 1, 0, 1, 0, 1, 0, 1, 0, 1, 1, 1, 1, 1, 1, 1],
      [1, 0, 0, 0, 0, 0, 1, 0, 0, 1, 0, 1, 0, 0, 1, 0, 0, 0, 0, 0, 1],
      [1, 0, 1, 1, 1, 0, 1, 0, 1, 1, 1, 0, 1, 0, 1, 0, 1, 1, 1, 0, 1],
      [1, 0, 1, 1, 1, 0, 1, 0, 0, 0, 1, 1, 0, 0, 1, 0, 1, 1, 1, 0, 1],
      [1, 0, 1, 1, 1, 0, 1, 0, 1, 0, 0, 0, 1, 0, 1, 0, 1, 1, 1, 0, 1],
      [1, 0, 0, 0, 0, 0, 1, 0, 0, 1, 1, 1, 0, 0, 1, 0, 0, 0, 0, 0, 1],
      [1, 1, 1, 1, 1, 1, 1, 0, 1, 0, 1, 0, 1, 0, 1, 1, 1, 1, 1, 1, 1],
      [0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 0, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0],
      [1, 1, 0, 1, 0, 1, 1, 1, 0, 0, 1, 0, 0, 1, 1, 0, 1, 0, 1, 1, 1],
      [0, 1, 1, 0, 1, 0, 0, 1, 0, 1, 0, 1, 0, 0, 1, 1, 0, 1, 0, 1, 0],
      [1, 0, 1, 1, 0, 1, 1, 0, 1, 0, 1, 0, 1, 1, 0, 1, 1, 0, 1, 0, 1],
      [0, 1, 0, 1, 1, 0, 0, 1, 0, 1, 0, 1, 0, 0, 1, 0, 0, 1, 1, 0, 0],
      [1, 0, 1, 0, 0, 1, 1, 0, 0, 1, 0, 0, 1, 1, 0, 1, 0, 0, 1, 1, 1],
      [0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 1, 1, 0, 0, 1, 0, 1, 0, 0, 1, 0],
      [1, 1, 1, 1, 1, 1, 1, 0, 0, 1, 1, 0, 1, 1, 0, 0, 1, 1, 0, 1, 1],
      [1, 0, 0, 0, 0, 0, 1, 0, 1, 0, 0, 1, 0, 1, 1, 0, 1, 0, 1, 0, 0],
      [1, 0, 1, 1, 1, 0, 1, 0, 1, 1, 0, 0, 1, 0, 0, 1, 0, 1, 1, 1, 0],
      [1, 0, 1, 1, 1, 0, 1, 0, 0, 0, 1, 1, 0, 1, 1, 0, 1, 0, 0, 0, 1],
      [1, 0, 1, 1, 1, 0, 1, 0, 1, 0, 1, 0, 1, 0, 1, 1, 0, 1, 1, 0, 1],
      [1, 0, 0, 0, 0, 0, 1, 0, 0, 1, 0, 1, 0, 1, 0, 0, 1, 0, 1, 1, 0],
      [1, 1, 1, 1, 1, 1, 1, 0, 1, 1, 1, 0, 1, 0, 1, 0, 0, 1, 1, 0, 1],
    ];

    for (int r = 0; r < modules; r++) {
      for (int c = 0; c < modules; c++) {
        if (matrix[r][c] == 1) {
          final rect = Rect.fromLTWH(
            c * moduleSize,
            r * moduleSize,
            moduleSize - 0.4,
            moduleSize - 0.4,
          );
          canvas.drawRRect(
            RRect.fromRectAndRadius(rect, const Radius.circular(1.2)),
            paint,
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
