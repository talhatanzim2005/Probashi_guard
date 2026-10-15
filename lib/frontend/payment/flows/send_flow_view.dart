import 'package:flutter/material.dart';
import '../../../theme/app_colors.dart';
import '../controllers/payment_controller.dart';
import '../models/beneficiary_model.dart';
import '../models/wallet_card_model.dart';
import 'send_amount_step.dart';
import 'send_confirm_step.dart';
import 'send_contact_step.dart';

class SendFlowView extends StatefulWidget {
  final PaymentController controller;
  final BeneficiaryModel? initialRecipient;

  const SendFlowView({
    super.key,
    required this.controller,
    this.initialRecipient,
  });

  static Future<void> push(
    BuildContext context, {
    required PaymentController controller,
    BeneficiaryModel? recipient,
  }) {
    return Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SendFlowView(
          controller: controller,
          initialRecipient: recipient,
        ),
      ),
    );
  }

  @override
  State<SendFlowView> createState() => _SendFlowViewState();
}

class _SendFlowViewState extends State<SendFlowView> {
  int _currentStep = 0; // 0 = Contact, 1 = Amount, 2 = Confirm
  BeneficiaryModel? _selectedRecipient;
  WalletCardModel? _sourceCard;
  double _sourceAmount = 0.0;
  String _sourceCurrency = 'SAR';
  double _destinationAmount = 0.0;
  String _destinationCurrency = 'BDT';

  @override
  void initState() {
    super.initState();
    if (widget.initialRecipient != null) {
      _selectedRecipient = widget.initialRecipient;
      _currentStep = 1; // Skip directly to amount
    }
  }

  void _onSelectRecipient(BeneficiaryModel recipient) {
    setState(() {
      _selectedRecipient = recipient;
      _currentStep = 1;
    });
  }

  void _onProceedToConfirm({
    required WalletCardModel sourceCard,
    required double sourceAmount,
    required String sourceCurrency,
    required double destinationAmount,
    required String destinationCurrency,
  }) {
    setState(() {
      _sourceCard = sourceCard;
      _sourceAmount = sourceAmount;
      _sourceCurrency = sourceCurrency;
      _destinationAmount = destinationAmount;
      _destinationCurrency = destinationCurrency;
      _currentStep = 2;
    });
  }

  Future<void> _handleConfirmed() async {
    if (_selectedRecipient == null) return;

    final success = await widget.controller.sendMoney(
      recipient: _selectedRecipient!,
      sourceAmount: _sourceAmount,
      sourceCurrency: _sourceCurrency,
      destinationAmount: _destinationAmount,
      destinationCurrency: _destinationCurrency,
    );

    if (!mounted) return;

    if (success) {
      _showSuccessDialog();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to complete remittance. Please try again.'),
          backgroundColor: AppColors.crimsonRed,
        ),
      );
    }
  }

  void _showSuccessDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog(
        backgroundColor: AppColors.cloudDancer,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 70,
                height: 70,
                decoration: BoxDecoration(
                  color: AppColors.emeraldGreen.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Center(
                  child: Icon(
                    Icons.check_circle_rounded,
                    color: AppColors.emeraldGreen,
                    size: 44,
                  ),
                ),
              ),
              const SizedBox(height: 18),
              const Text(
                'Remittance Successful!',
                style: TextStyle(
                  color: AppColors.royalBlue,
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '৳${_destinationAmount.toStringAsFixed(2)} has been credited to ${_selectedRecipient?.name} (${_selectedRecipient?.providerType}).',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.royalBlue.withValues(alpha: 0.7),
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pop(ctx); // Close dialog
                    Navigator.pop(context); // Close send flow
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.royalBlue,
                    foregroundColor: AppColors.cloudDancer,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: const Text(
                    'Done',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _handleBack() {
    if (_currentStep > 0 && widget.initialRecipient == null) {
      setState(() => _currentStep--);
    } else {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.cloudDancer,
      appBar: AppBar(
        backgroundColor: AppColors.cloudDancer,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: AppColors.royalBlue, size: 20),
          onPressed: _handleBack,
        ),
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildStepIndicator(0, 'Recipient'),
            _buildStepDivider(),
            _buildStepIndicator(1, 'Amount'),
            _buildStepDivider(),
            _buildStepIndicator(2, 'Confirm'),
          ],
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18.0, vertical: 8.0),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              child: child,
            ),
            child: _buildCurrentStep(),
          ),
        ),
      ),
    );
  }

  Widget _buildCurrentStep() {
    switch (_currentStep) {
      case 0:
        return SendContactStep(
          key: const ValueKey('step_0'),
          beneficiaries: widget.controller.beneficiaries,
          onSelectRecipient: _onSelectRecipient,
        );
      case 1:
        return SendAmountStep(
          key: const ValueKey('step_1'),
          recipient: _selectedRecipient!,
          controller: widget.controller,
          onProceed: _onProceedToConfirm,
        );
      case 2:
        return SendConfirmStep(
          key: const ValueKey('step_2'),
          recipient: _selectedRecipient!,
          sourceCard: _sourceCard!,
          sourceAmount: _sourceAmount,
          sourceCurrency: _sourceCurrency,
          destinationAmount: _destinationAmount,
          destinationCurrency: _destinationCurrency,
          onConfirmed: _handleConfirmed,
        );
      default:
        return const SizedBox();
    }
  }

  Widget _buildStepIndicator(int stepIndex, String title) {
    final isActive = _currentStep == stepIndex;
    final isPassed = _currentStep > stepIndex;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isActive
            ? AppColors.royalBlue
            : (isPassed ? AppColors.emeraldGreen : Colors.transparent),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        '${stepIndex + 1}. $title',
        style: TextStyle(
          color: (isActive || isPassed)
              ? AppColors.cloudDancer
              : AppColors.royalBlue.withValues(alpha: 0.5),
          fontSize: 10.5,
          fontWeight: (isActive || isPassed) ? FontWeight.w700 : FontWeight.w500,
        ),
      ),
    );
  }

  Widget _buildStepDivider() {
    return Container(
      width: 10,
      height: 1.5,
      margin: const EdgeInsets.symmetric(horizontal: 2),
      color: AppColors.royalBlue.withValues(alpha: 0.2),
    );
  }
}
