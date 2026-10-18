import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../l10n/app_strings.dart';
import '../../../theme/app_colors.dart';
import '../controllers/payment_controller.dart';
import '../models/wallet_card_model.dart';

class TransferDialog extends StatefulWidget {
  final PaymentController controller;

  const TransferDialog({super.key, required this.controller});

  static Future<void> show(BuildContext context, PaymentController controller) {
    return showDialog(
      context: context,
      barrierDismissible: true,
      builder: (_) => TransferDialog(controller: controller),
    );
  }

  @override
  State<TransferDialog> createState() => _TransferDialogState();
}

class _TransferDialogState extends State<TransferDialog> {
  late WalletCardModel _fromCard;
  late WalletCardModel _toCard;
  final TextEditingController _amountController = TextEditingController(text: '5000');
  bool _isTransferring = false;

  @override
  void initState() {
    super.initState();
    final cards = widget.controller.cards;
    _fromCard = cards.isNotEmpty ? cards[0] : const WalletCardModel(
      id: 'default',
      title: 'WPS Card',
      providerName: 'Payroll',
      cardNumberMasked: '•••• 8420',
      balance: 10000,
      currency: 'BDT',
      expiryDate: '12/28',
      cardType: CardType.wpsPayroll,
      primaryColor: Color(0xFF111625),
      accentColor: AppColors.emeraldGreen,
    );
    _toCard = cards.length > 1 ? cards[1] : _fromCard;
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  void _swapSelection() {
    HapticFeedback.selectionClick();
    setState(() {
      final temp = _fromCard;
      _fromCard = _toCard;
      _toCard = temp;
    });
  }

  Future<void> _handleTransfer() async {
    final amount = double.tryParse(_amountController.text.trim()) ?? 0.0;
    if (amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppStrings.of(context).enterValidTransferAmount),
          backgroundColor: AppColors.crimsonRed,
        ),
      );
      return;
    }

    if (_fromCard.balance < amount) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppStrings.of(context).insufficientSourceBalance),
          backgroundColor: AppColors.crimsonRed,
        ),
      );
      return;
    }

    setState(() => _isTransferring = true);
    final success = await widget.controller.interCardSwap(
      fromCardId: _fromCard.id,
      toCardId: _toCard.id,
      amountInBdt: amount,
    );
    setState(() => _isTransferring = false);

    if (mounted) {
      Navigator.pop(context);
      if (success) {
        HapticFeedback.mediumImpact();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Successfully transferred ৳${amount.toStringAsFixed(2)} to ${_toCard.title}',
            ),
            backgroundColor: AppColors.emeraldGreen,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final cards = widget.controller.cards;

    return Dialog(
      backgroundColor: AppColors.cloudDancer,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.all(22.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  s.interCardTransfer,
                  style: const TextStyle(
                    color: AppColors.royalBlue,
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 20, color: AppColors.royalBlue),
                  onPressed: () => Navigator.pop(context),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              s.interCardSubtitle,
              style: TextStyle(
                color: AppColors.royalBlue.withValues(alpha: 0.6),
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 18),

            // From Card Dropdown Box
            _buildCardSelector(
              label: s.fromAccount,
              current: _fromCard,
              cards: cards,
              onChanged: (c) => setState(() => _fromCard = c!),
            ),

            // Swap Arrow Center Icon
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: IconButton(
                  onPressed: _swapSelection,
                  icon: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: AppColors.royalBlue.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.swap_vert_rounded,
                      color: AppColors.royalBlue,
                      size: 20,
                    ),
                  ),
                ),
              ),
            ),

            // To Card Dropdown Box
            _buildCardSelector(
              label: s.toAccount,
              current: _toCard,
              cards: cards,
              onChanged: (c) => setState(() => _toCard = c!),
            ),
            const SizedBox(height: 16),

            // Amount Input
            TextField(
              controller: _amountController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: const TextStyle(
                color: AppColors.royalBlue,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
              decoration: InputDecoration(
                labelText: 'Amount (BDT ৳)',
                labelStyle: TextStyle(
                  color: AppColors.royalBlue.withValues(alpha: 0.7),
                  fontSize: 13,
                ),
                prefixText: '৳ ',
                prefixStyle: const TextStyle(
                  color: AppColors.royalBlue,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
                filled: true,
                fillColor: Colors.white,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(
                    color: AppColors.royalBlue.withValues(alpha: 0.2),
                  ),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(
                    color: AppColors.royalBlue.withValues(alpha: 0.2),
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(
                    color: AppColors.royalBlue,
                    width: 1.5,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 22),

            // Transfer Submit Button
            ElevatedButton(
              onPressed: _isTransferring ? null : _handleTransfer,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.royalBlue,
                foregroundColor: AppColors.cloudDancer,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                elevation: 0,
              ),
              child: _isTransferring
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.cloudDancer,
                      ),
                    )
                  : Text(
                      s.confirmTransfer,
                      style: const TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCardSelector({
    required String label,
    required WalletCardModel current,
    required List<WalletCardModel> cards,
    required ValueChanged<WalletCardModel?> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: AppColors.royalBlue.withValues(alpha: 0.16),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: TextStyle(
              color: AppColors.royalBlue.withValues(alpha: 0.5),
              fontSize: 9.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 2),
          DropdownButtonHideUnderline(
            child: DropdownButton<WalletCardModel>(
              value: current,
              isExpanded: true,
              icon: const Icon(Icons.arrow_drop_down, color: AppColors.royalBlue),
              items: cards.map((c) {
                return DropdownMenuItem<WalletCardModel>(
                  value: c,
                  child: Text(
                    '${c.title} (৳${c.balance.toStringAsFixed(0)})',
                    style: const TextStyle(
                      color: AppColors.royalBlue,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                );
              }).toList(),
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }
}
