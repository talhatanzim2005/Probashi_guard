import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../theme/app_colors.dart';

class HoldToConfirmButton extends StatefulWidget {
  final Future<void> Function() onConfirmed;
  final String label;

  const HoldToConfirmButton({
    super.key,
    required this.onConfirmed,
    this.label = 'Hold to Confirm',
  });

  @override
  State<HoldToConfirmButton> createState() => _HoldToConfirmButtonState();
}

class _HoldToConfirmButtonState extends State<HoldToConfirmButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  bool _isCompleted = false;
  bool _isProcessing = false;
  int _lastHapticStep = 0;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1300),
    );

    _controller.addListener(() {
      setState(() {});

      // Subtle step haptics as the cloud billows across
      final currentStep = (_controller.value * 4).floor();
      if (currentStep > _lastHapticStep && currentStep < 4) {
        _lastHapticStep = currentStep;
        HapticFeedback.selectionClick();
      }

      if (_controller.value >= 1.0 && !_isCompleted) {
        _onHoldCompleted();
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onHoldCompleted() async {
    _isCompleted = true;
    _isProcessing = true;
    HapticFeedback.heavyImpact();

    await widget.onConfirmed();

    if (mounted) {
      setState(() {
        _isProcessing = false;
      });
    }
  }

  void _handleTapDown(TapDownDetails details) {
    if (_isCompleted || _isProcessing) return;
    _lastHapticStep = 0;
    HapticFeedback.lightImpact();
    _controller.forward();
  }

  void _handleTapUp(TapUpDetails details) {
    if (_isCompleted || _isProcessing) return;
    _controller.reverse();
  }

  void _handleTapCancel() {
    if (_isCompleted || _isProcessing) return;
    _controller.reverse();
  }

  @override
  Widget build(BuildContext context) {
    final progress = _controller.value;

    return GestureDetector(
      onTapDown: _handleTapDown,
      onTapUp: _handleTapUp,
      onTapCancel: _handleTapCancel,
      child: Container(
        height: 56,
        decoration: BoxDecoration(
          color: AppColors.royalBlue,
          borderRadius: BorderRadius.circular(28),
          boxShadow: [
            BoxShadow(
              color: AppColors.royalBlue.withValues(alpha: 0.28),
              blurRadius: 14,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            // Ambient subtle background clouds on royal blue
            Positioned(
              right: 12,
              bottom: 4,
              child: Icon(
                Icons.cloud_queue_rounded,
                size: 40,
                color: Colors.white.withValues(alpha: 0.06),
              ),
            ),

            // Base Text Layer: White/CloudDancer text on Royal Blue
            Center(
              child: _buildButtonContent(
                textColor: AppColors.cloudDancer,
                iconColor: AppColors.cloudDancer,
              ),
            ),

            // Animated White Cloud Fill Layer (direct Canvas painting of billowing ellipses)
            if (progress > 0)
              Positioned.fill(
                child: CustomPaint(
                  painter: _CloudBillowPainter(progress: progress),
                ),
              ),

            // Overlaid Text Layer: Royal Blue text revealed over white cloud via hardware-scissored ClipRect
            if (progress > 0)
              ClipRect(
                clipper: _CloudTextRevealClipper(progress: progress),
                child: Center(
                  child: _buildButtonContent(
                    textColor: AppColors.royalBlue,
                    iconColor: _isCompleted
                        ? AppColors.emeraldGreen
                        : AppColors.royalBlue,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildButtonContent({
    required Color textColor,
    required Color iconColor,
  }) {
    if (_isProcessing) {
      return SizedBox(
        width: 22,
        height: 22,
        child: CircularProgressIndicator(
          strokeWidth: 2.4,
          color: iconColor,
        ),
      );
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          _isCompleted ? Icons.check_circle_rounded : Icons.cloud_rounded,
          color: iconColor,
          size: 20,
        ),
        const SizedBox(width: 8),
        Text(
          _isCompleted ? 'Transfer Confirmed' : widget.label,
          style: TextStyle(
            color: textColor,
            fontSize: 15,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.2,
          ),
        ),
      ],
    );
  }
}

/// Renders an advancing white cloud front made of organic interlocking ellipses directly to the Canvas.
/// Using direct canvas drawing avoids Skia fragment shader clip processor generation on WebGL/CanvasKit.
class _CloudBillowPainter extends CustomPainter {
  final double progress;

  _CloudBillowPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0) return;

    final cloudPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    // When fully confirmed, fill the entire button area
    if (progress >= 1.0) {
      canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), cloudPaint);
      return;
    }

    final xFront = progress * (size.width + 48) - 16;

    // 1. Solid rectangular body behind advancing cloud front
    if (xFront > 10) {
      canvas.drawRect(
        Rect.fromLTWH(0, 0, xFront - 8, size.height),
        cloudPaint,
      );
    }

    // 2. Billowing white cloud lobes (interlocking ellipses along advancing front)
    // Top lobe
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(xFront - 2, size.height * 0.22),
        width: 42,
        height: 36,
      ),
      cloudPaint,
    );

    // High-center billowing lobe (leading forward)
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(xFront + 10, size.height * 0.44),
        width: 52,
        height: 44,
      ),
      cloudPaint,
    );

    // Low-center lobe
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(xFront + 2, size.height * 0.70),
        width: 46,
        height: 38,
      ),
      cloudPaint,
    );

    // Bottom lobe
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(xFront - 6, size.height * 0.90),
        width: 38,
        height: 30,
      ),
      cloudPaint,
    );

    // Secondary trailing internal puffs ensuring no hollow gaps between ellipses
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(xFront - 16, size.height * 0.34),
        width: 40,
        height: 34,
      ),
      cloudPaint,
    );
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(xFront - 14, size.height * 0.64),
        width: 40,
        height: 34,
      ),
      cloudPaint,
    );

    // 3. Subtle internal cloud contours for 3D fluffy puff depth
    final puffPaint = Paint()
      ..color = AppColors.royalBlue.withValues(alpha: 0.05)
      ..style = PaintingStyle.fill;

    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(xFront - 6, size.height * 0.38),
        width: 24,
        height: 18,
      ),
      puffPaint,
    );
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(xFront - 10, size.height * 0.64),
        width: 22,
        height: 16,
      ),
      puffPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _CloudBillowPainter oldDelegate) =>
      oldDelegate.progress != progress;
}

/// Simple axis-aligned bounding box clipper for revealing royal blue text over white clouds.
/// Scissor clipping (ClipRect) uses native GPU hardware scissor testing (glScissor)
/// without generating any Skia fragment-shader analytic clip processors.
class _CloudTextRevealClipper extends CustomClipper<Rect> {
  final double progress;

  _CloudTextRevealClipper({required this.progress});

  @override
  Rect getClip(Size size) {
    if (progress <= 0) return Rect.zero;
    if (progress >= 1.0) return Rect.fromLTWH(0, 0, size.width, size.height);
    final x = progress * (size.width + 48) - 16;
    return Rect.fromLTWH(0, 0, x.clamp(0.0, size.width), size.height);
  }

  @override
  bool shouldReclip(covariant _CloudTextRevealClipper oldClipper) =>
      oldClipper.progress != progress;
}
