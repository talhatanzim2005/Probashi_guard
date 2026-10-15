import 'package:flutter/material.dart';
import '../../../theme/app_colors.dart';
import '../controllers/payment_controller.dart';
import '../models/currency_model.dart';

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
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.cloudDancer,
        borderRadius: BorderRadius.circular(17),
        border: Border.all(
          color: AppColors.royalBlue.withValues(alpha: 0.18),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.royalBlue.withValues(alpha: 0.04),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        shrinkWrap: true,
        itemCount: CurrencyModel.supportedCurrencies.length,
        separatorBuilder: (context, index) => const SizedBox(width: 4),
        itemBuilder: (context, index) {
          final currency = CurrencyModel.supportedCurrencies[index];
          final isSelected = currency.code == selected.code;

          return GestureDetector(
            onTap: () {
              controller.setSelectedCurrency(currency);
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOutCubic,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: isSelected ? AppColors.royalBlue : Colors.transparent,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    currency.flag,
                    style: const TextStyle(fontSize: 11),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    currency.code,
                    style: TextStyle(
                      color: isSelected
                          ? AppColors.cloudDancer
                          : AppColors.royalBlue.withValues(alpha: 0.7),
                      fontSize: 11,
                      fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
