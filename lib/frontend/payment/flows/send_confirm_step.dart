import 'package:flutter/material.dart';
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
  final Future<void> Function() onConfirmed;

  const SendConfirmStep({
    super.key,
    required this.recipient,
    required this.sourceCard,
    required this.sourceAmount,
    required this.sourceCurrency,
    required this.destinationAmount,
    required this.destinationCurrency,
    required this.onConfirmed,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Review & Confirm',
            style: TextStyle(
              color: AppColors.royalBlue,
              fontSize: 20,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Please verify recipient and remittance amount carefully',
            style: TextStyle(
              color: AppColors.royalBlue.withValues(alpha: 0.6),
              fontSize: 13,
            ),
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
                  'RECIPIENT RECEIVES',
                  style: TextStyle(
                    color: AppColors.royalBlue.withValues(alpha: 0.5),
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
                      ? 'Govt 2.5% Cash Bonus included'
                      : 'Guaranteed Cross-Border Settlement to ${recipient.countryName}',
                  style: TextStyle(
                    color: AppColors.emeraldGreen.withValues(alpha: 0.85),
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Divider(
                  color: AppColors.royalBlue.withValues(alpha: 0.1),
                  height: 30,
                ),

                // Breakdown rows
                _buildReceiptRow('Recipient', '${recipient.countryFlag} ${recipient.name}'),
                _buildReceiptRow('Destination Country', '${recipient.countryFlag} ${recipient.countryName}'),
                _buildReceiptRow('Account / Phone', recipient.phoneOrAccount),
                _buildReceiptRow('Channel / Provider', recipient.providerType),
                _buildReceiptRow(
                  'Source Deduction',
                  '$sourceCurrency ${sourceAmount.toStringAsFixed(2)}',
                ),
                _buildReceiptRow('Debited From', '${sourceCard.title} (${sourceCard.cardNumberMasked})'),
                _buildReceiptRow('Transfer Fee', 'FREE (0.00)', isPositive: true),
                _buildReceiptRow('Settlement Speed', 'Instant Verified', isPositive: true),
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
            child: const Row(
              children: [
                Icon(
                  Icons.shield_outlined,
                  color: AppColors.royalBlue,
                  size: 20,
                ),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Protected by Bangladesh Bank Expatriate Remittance Guidelines & Host WPS Guarantee.',
                    style: TextStyle(
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
          HoldToConfirmButton(
            onConfirmed: onConfirmed,
            label: 'Hold to Confirm',
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  Widget _buildReceiptRow(String label, String value, {bool isPositive = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              color: AppColors.royalBlue.withValues(alpha: 0.6),
              fontSize: 12.5,
              fontWeight: FontWeight.w500,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              color: isPositive ? AppColors.emeraldGreen : AppColors.royalBlue,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
