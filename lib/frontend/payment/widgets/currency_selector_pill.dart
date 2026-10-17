import 'package:flutter/material.dart';
import '../../../theme/app_colors.dart';
import '../controllers/payment_controller.dart';
import '../models/currency_model.dart';

/// Compact currency switcher.
///
/// It has a natural (intrinsic) width so a parent can wrap it in a
/// `FittedBox(fit: BoxFit.scaleDown)` and it will shrink instead of
/// overflowing on narrow screens.
class CurrencySelectorPill extends StatelessWidget {
  final PaymentController controller;

  const CurrencySelectorPill({
    super.key,
    required this.controller,
  });

  @override
  Widget build(BuildContext context) {
    final selected = controller.selectedCurrency;

    return Container(
      height: 38,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppColors.cloudDancer,
        borderRadius: BorderRadius.circular(19),
        border: Border.all(
          color: AppColors.royalBlue.withValues(alpha: 0.22),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.royalBlue.withValues(alpha: 0.05),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final currency in CurrencyModel.supportedCurrencies)
            Padding(
              padding: const EdgeInsets.only(right: 2),
              child: _CurrencyChip(
                flag: currency.flag,
                code: currency.code,
                isSelected: currency.code == selected.code,
                onTap: () => controller.setSelectedCurrency(currency),
              ),
            ),
        ],
      ),
    );
  }
}

class _CurrencyChip extends StatelessWidget {
  final String flag;
  final String code;
  final bool isSelected;
  final VoidCallback onTap;

  const _CurrencyChip({
    required this.flag,
    required this.code,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: isSelected,
      label: 'Display currency $code',
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isSelected ? AppColors.royalBlue : Colors.transparent,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(flag, style: const TextStyle(fontSize: 13)),
              const SizedBox(width: 5),
              Text(
                code,
                style: TextStyle(
                  color: isSelected
                      ? AppColors.cloudDancer
                      : AppColors.royalBlueMuted,
                  fontSize: 12.5,
                  fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}