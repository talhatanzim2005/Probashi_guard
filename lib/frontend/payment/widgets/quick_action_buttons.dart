import 'package:flutter/material.dart';
import '../../../theme/app_colors.dart';

class QuickActionButtons extends StatelessWidget {
  final VoidCallback onSendTap;
  final VoidCallback onReceiveTap;
  final VoidCallback onTransferTap;

  const QuickActionButtons({
    super.key,
    required this.onSendTap,
    required this.onReceiveTap,
    required this.onTransferTap,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // 1. Send Pill
        Expanded(
          flex: 4,
          child: _ActionPill(
            icon: Icons.north_east_rounded,
            label: 'Send',
            onTap: onSendTap,
          ),
        ),
        const SizedBox(width: 10),

        // 2. Receive Pill
        Expanded(
          flex: 4,
          child: _ActionPill(
            icon: Icons.south_west_rounded,
            label: 'Receive',
            onTap: onReceiveTap,
          ),
        ),
        const SizedBox(width: 10),

        // 3. Swap / Transfer Button
        _TransferButton(onTap: onTransferTap),
      ],
    );
  }
}

class _ActionPill extends StatefulWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _ActionPill({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  State<_ActionPill> createState() => _ActionPillState();
}

class _ActionPillState extends State<_ActionPill> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _isPressed = true),
      onTapUp: (_) {
        setState(() => _isPressed = false);
        widget.onTap();
      },
      onTapCancel: () => setState(() => _isPressed = false),
      child: AnimatedScale(
        scale: _isPressed ? 0.96 : 1.0,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOutCubic,
        child: Container(
          height: 48,
          decoration: BoxDecoration(
            color: AppColors.cloudDancer,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: AppColors.royalBlue.withValues(alpha: 0.16),
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: AppColors.royalBlue.withValues(alpha: 0.05),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                widget.icon,
                color: AppColors.royalBlue,
                size: 16,
              ),
              const SizedBox(width: 7),
              Text(
                widget.label,
                style: const TextStyle(
                  color: AppColors.royalBlue,
                  fontSize: 14.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TransferButton extends StatefulWidget {
  final VoidCallback onTap;

  const _TransferButton({required this.onTap});

  @override
  State<_TransferButton> createState() => _TransferButtonState();
}

class _TransferButtonState extends State<_TransferButton> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _isPressed = true),
      onTapUp: (_) {
        setState(() => _isPressed = false);
        widget.onTap();
      },
      onTapCancel: () => setState(() => _isPressed = false),
      child: AnimatedScale(
        scale: _isPressed ? 0.94 : 1.0,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOutCubic,
        child: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: AppColors.cloudDancer,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: AppColors.royalBlue.withValues(alpha: 0.16),
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: AppColors.royalBlue.withValues(alpha: 0.05),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: const Center(
            child: Icon(
              Icons.swap_horiz_rounded,
              color: AppColors.royalBlue,
              size: 20,
            ),
          ),
        ),
      ),
    );
  }
}
