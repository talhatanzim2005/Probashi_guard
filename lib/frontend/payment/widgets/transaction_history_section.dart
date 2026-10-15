import 'package:flutter/material.dart';
import '../../../theme/app_colors.dart';
import '../controllers/payment_controller.dart';
import '../models/transaction_model.dart';

class TransactionHistorySection extends StatelessWidget {
  final PaymentController controller;
  final VoidCallback onSeeAllTap;

  const TransactionHistorySection({
    super.key,
    required this.controller,
    required this.onSeeAllTap,
  });

  @override
  Widget build(BuildContext context) {
    final transactions = controller.transactions;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.cloudDancer,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: AppColors.royalBlue.withValues(alpha: 0.12),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.royalBlue.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Transaction History',
                style: TextStyle(
                  color: AppColors.royalBlue,
                  fontSize: 16.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.2,
                ),
              ),
              GestureDetector(
                onTap: onSeeAllTap,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
                  child: Text(
                    'See all',
                    style: TextStyle(
                      color: AppColors.royalBlue.withValues(alpha: 0.75),
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          if (transactions.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24.0),
              child: Center(
                child: Text(
                  'No transactions recorded yet',
                  style: TextStyle(
                    color: AppColors.royalBlue.withValues(alpha: 0.5),
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: transactions.length > 5 ? 5 : transactions.length,
              separatorBuilder: (context, index) => Divider(
                color: AppColors.royalBlue.withValues(alpha: 0.08),
                height: 20,
              ),
              itemBuilder: (context, index) {
                final tx = transactions[index];
                return _TransactionTile(tx: tx);
              },
            ),
        ],
      ),
    );
  }
}

class _TransactionTile extends StatelessWidget {
  final TransactionModel tx;

  const _TransactionTile({required this.tx});

  @override
  Widget build(BuildContext context) {
    final isIncome = tx.isIncoming;

    return Row(
      children: [
        // Category Icon Circle
        _buildLeadingIcon(tx),
        const SizedBox(width: 14),

        // Title & Subtitle Column
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                tx.title,
                style: const TextStyle(
                  color: AppColors.royalBlue,
                  fontSize: 14.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.1,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                tx.subtitle,
                style: TextStyle(
                  color: AppColors.royalBlue.withValues(alpha: 0.55),
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),

        // Amount & Date/Type Column
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              '${isIncome ? '+' : '-'}${_getCurrencySymbol(tx.currency)}${tx.amount.toStringAsFixed(tx.amount.truncateToDouble() == tx.amount ? 0 : 2)}',
              style: TextStyle(
                color: isIncome ? AppColors.emeraldGreen : const Color(0xFF1E2430),
                fontSize: 15,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.2,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              _formatDate(tx.timestamp),
              style: TextStyle(
                color: AppColors.royalBlue.withValues(alpha: 0.5),
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildLeadingIcon(TransactionModel tx) {
    IconData iconData;
    Color iconColor;
    Color bgColor;

    switch (tx.iconCategory) {
      case 'google':
        iconData = Icons.g_mobiledata_rounded;
        iconColor = const Color(0xFF4285F4);
        bgColor = const Color(0xFF4285F4).withValues(alpha: 0.12);
        break;
      case 'salary':
        iconData = Icons.account_balance_wallet_rounded;
        iconColor = AppColors.emeraldGreen;
        bgColor = AppColors.emeraldGreen.withValues(alpha: 0.12);
        break;
      case 'remittance':
        iconData = Icons.send_rounded;
        iconColor = AppColors.royalBlue;
        bgColor = AppColors.royalBlue.withValues(alpha: 0.12);
        break;
      case 'netflix':
        iconData = Icons.tv_rounded;
        iconColor = AppColors.crimsonRed;
        bgColor = AppColors.crimsonRed.withValues(alpha: 0.12);
        break;
      default:
        iconData = tx.isIncoming ? Icons.arrow_downward_rounded : Icons.person_rounded;
        iconColor = tx.isIncoming ? AppColors.emeraldGreen : AppColors.royalBlue;
        bgColor = iconColor.withValues(alpha: 0.12);
    }

    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        color: bgColor,
        shape: BoxShape.circle,
        border: Border.all(
          color: iconColor.withValues(alpha: 0.25),
          width: 1,
        ),
      ),
      child: Center(
        child: Icon(
          iconData,
          color: iconColor,
          size: 22,
        ),
      ),
    );
  }

  String _getCurrencySymbol(String currencyCode) {
    switch (currencyCode.toUpperCase()) {
      case 'USD':
        return '\$';
      case 'BDT':
        return '৳';
      case 'SAR':
        return '﷼';
      case 'AED':
        return 'د.إ ';
      case 'QAR':
        return 'ر.ق ';
      default:
        return '$currencyCode ';
    }
  }

  String _formatDate(DateTime dt) {
    final now = DateTime.now();
    final difference = now.difference(dt);

    if (difference.inMinutes < 60) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inHours < 24) {
      final hour = dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour);
      final period = dt.hour >= 12 ? 'PM' : 'AM';
      final minute = dt.minute.toString().padLeft(2, '0');
      return '$hour:$minute $period - Today';
    } else {
      return '${dt.day}/${dt.month}/${dt.year}';
    }
  }
}
