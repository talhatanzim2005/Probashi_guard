import 'package:flutter/material.dart';
import '../../../l10n/app_strings.dart';
import '../../../theme/app_colors.dart';
import '../models/beneficiary_model.dart';
import '../models/wallet_card_model.dart';
import '../widgets/hold_to_confirm_button.dart';

class SendConfirmStep extends StatelessWidget {
  final BeneficiaryModel recipient;
  final WalletCardModel sourceCard;
  final double sourceAmount;
  final String sourceCurrency;
  final double destinationAmount;
  final String destinationCurrency;
  final double vatOnCommission;
  final double usdAmount;
  final Future<bool> Function() onConfirmed;

  const SendConfirmStep({
    super.key,
    required this.recipient,
    required this.sourceCard,
    required this.sourceAmount,
    required this.sourceCurrency,
    required this.destinationAmount,
    required this.destinationCurrency,
    required this.vatOnCommission,
    required this.usdAmount,
    required this.onConfirmed,
  });

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            s.reviewAndConfirm,
            style: const TextStyle(
              color: AppColors.royalBlue,
              fontSize: 20,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            s.reviewSubtitle,
            style: const TextStyle(color: AppColors.inkMuted, fontSize: 13),
          ),
          const SizedBox(height: 18),

          // Receipt Container
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                color: AppColors.royalBlue.withValues(alpha: 0.16),
                width: 1.2,
              ),
              boxShadow: [
                BoxShadow(
                  color: AppColors.royalBlue.withValues(alpha: 0.05),
                  blurRadius: 14,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              children: [
                // Highlight Amount Received
                Text(
                  s.recipientReceives,
                  style: const TextStyle(
                    color: AppColors.inkMuted,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${recipient.currencySymbol}${destinationAmount.toStringAsFixed(2)}',
                  style: const TextStyle(
                    color: AppColors.emeraldGreen,
                    fontSize: 32,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.5,
                  ),
                ),
                Text(
                  recipient.countryCode == 'BD'
                      ? s.govtBonusIncluded
                      : s.guaranteedSettlement(recipient.countryName),
                  style: TextStyle(
                    color: AppColors.emeraldGreen.withValues(alpha: 0.85),
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Divider(
                  color: AppColors.royalBlue.withValues(alpha: 0.1),
                  height: 30,
                ),

                // Breakdown rows
                _buildReceiptRow(
                  s.stepRecipient,
                  '${recipient.countryFlag} ${recipient.name}',
                ),
                _buildReceiptRow(
                  s.destinationCountry,
                  '${recipient.countryFlag} ${recipient.countryName}',
                ),
                _buildReceiptRow(s.accountOrPhone, recipient.phoneOrAccount),
                _buildReceiptRow(s.channelProvider, recipient.providerType),
                _buildReceiptRow(
                  s.sourceDeduction,
                  '$sourceCurrency ${sourceAmount.toStringAsFixed(2)}',
                ),
                _buildReceiptRow(
                  s.debitedFrom,
                  '${sourceCard.title} (${sourceCard.cardNumberMasked})',
                ),
                _buildReceiptRow(s.transferFee, s.feeFree, isPositive: true),
                _buildReceiptRow(
                  '${s.vatOnCommission} (0.01%)',
                  '$sourceCurrency ${vatOnCommission.toStringAsFixed(2)}',
                ),
                _buildReceiptRow(
                  s.totalDebited,
                  '$sourceCurrency ${(sourceAmount + vatOnCommission).toStringAsFixed(2)}',
                ),
                _buildReceiptRow(
                  s.chargedInUsd,
                  'USD ${usdAmount.toStringAsFixed(2)}',
                ),
                _buildReceiptRow(
                  s.settlementSpeed,
                  s.instantVerified,
                  isPositive: true,
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),

          // Security Guarantee Badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.royalBlue.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: AppColors.royalBlue.withValues(alpha: 0.18),
                width: 1,
              ),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.shield_outlined,
                  color: AppColors.royalBlue,
                  size: 20,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    s.remittanceProtectionNote,
                    style: const TextStyle(
                      color: AppColors.royalBlue,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Hold to Confirm Button
          HoldToConfirmButton(onConfirmed: onConfirmed, label: s.holdToConfirm),
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  Widget _buildReceiptRow(
    String label,
    String value, {
    bool isPositive = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: AppColors.inkMuted,
              fontSize: 12.5,
              fontWeight: FontWeight.w500,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              color: isPositive ? AppColors.emeraldGreen : AppColors.ink,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
