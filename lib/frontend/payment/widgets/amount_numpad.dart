import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../theme/app_colors.dart';

/// The 0-9 keypad the amount fields are driven by.
///
/// The amount fields are read-only, so this is the only way to type an amount:
/// the system keyboard never opens and nothing but digits can ever be entered,
/// on any platform. That also means the keypad is always on screen rather than
/// waiting for a soft keyboard that desktop and web never show.
class AmountNumpad extends StatelessWidget {
  final TextEditingController controller;

  /// Called after every key, so the caller can recompute totals.
  final VoidCallback onChanged;

  /// Upper bound on digits, which stops an accidental long press producing an
  /// amount the gateway would reject.
  final int maxDigits;

  /// For amounts, "0" then "5" is "5". A phone number or a one-time code is a
  /// string of digits, not a quantity, so its leading 0 has to survive.
  final bool replaceLeadingZero;

  /// What a screen reader announces for the clear key.
  final String clearLabel;

  const AmountNumpad({
    super.key,
    required this.controller,
    required this.onChanged,
    this.maxDigits = 9,
    this.replaceLeadingZero = true,
    this.clearLabel = 'Clear amount',
  });

  void _append(String digit) {
    final current = controller.text;
    final next = replaceLeadingZero && (current == '0' || current.isEmpty)
        ? digit
        : current + digit;
    if (next.length > maxDigits) return;
    HapticFeedback.selectionClick();
    controller.text = next;
    onChanged();
  }

  void _backspace() {
    final current = controller.text;
    if (current.isEmpty) return;
    HapticFeedback.selectionClick();
    controller.text = current.substring(0, current.length - 1);
    onChanged();
  }

  void _clear() {
    if (controller.text.isEmpty) return;
    HapticFeedback.mediumImpact();
    controller.clear();
    onChanged();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final row in const [
          ['1', '2', '3'],
          ['4', '5', '6'],
          ['7', '8', '9'],
        ])
          Row(
            children: [
              for (final digit in row) Expanded(child: _digitKey(digit)),
            ],
          ),
        Row(
          children: [
            Expanded(
              child: _key(
                onTap: _clear,
                semanticLabel: clearLabel,
                child: const Icon(
                  Icons.clear_rounded,
                  color: AppColors.crimsonRed,
                  size: 22,
                ),
              ),
            ),
            Expanded(child: _digitKey('0')),
            Expanded(
              child: _key(
                onTap: _backspace,
                semanticLabel: 'Delete last digit',
                child: const Icon(
                  Icons.backspace_outlined,
                  color: AppColors.royalBlue,
                  size: 21,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _digitKey(String digit) {
    return _key(
      onTap: () => _append(digit),
      semanticLabel: digit,
      child: Text(
        digit,
        style: const TextStyle(
          color: AppColors.ink,
          fontSize: 23,
          fontWeight: FontWeight.w700,
          fontFeatures: [FontFeature.tabularFigures()],
        ),
      ),
    );
  }

  Widget _key({
    required VoidCallback onTap,
    required String semanticLabel,
    required Widget child,
  }) {
    return Semantics(
      button: true,
      label: semanticLabel,
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(14),
            child: Container(
              height: 52,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: AppColors.royalBlue.withValues(alpha: 0.14),
                ),
              ),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}
