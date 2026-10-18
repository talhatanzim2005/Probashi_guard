import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../l10n/app_strings.dart';
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

  // Figures the gateway needs, carried over from the amount step.
  double _exchangeRate = 1.0;
  double _amountBdt = 0.0;
  double _incentiveBdt = 0.0;

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
    required double exchangeRate,
    required double amountBdt,
    required double incentiveBdt,
  }) {
    setState(() {
      _sourceCard = sourceCard;
      _sourceAmount = sourceAmount;
      _sourceCurrency = sourceCurrency;
      _destinationAmount = destinationAmount;
      _destinationCurrency = destinationCurrency;
      _exchangeRate = exchangeRate;
      _amountBdt = amountBdt;
      _incentiveBdt = incentiveBdt;
      _currentStep = 2;
    });
  }

  /// Runs the hold-to-confirm gesture through the real gateway: open a Stripe
  /// Checkout session, hand the person off to Stripe's hosted page, and only
  /// treat the remittance as sent once Stripe says the session was paid.
  ///
  /// Returns false when the transfer did not go through, which releases the
  /// hold-to-confirm button so the person can try again.
  Future<bool> _handleConfirmed() async {
    final recipient = _selectedRecipient;
    final sourceCard = _sourceCard;
    if (recipient == null || sourceCard == null) return false;

    // Resolved up front: everything below runs after an await.
    final s = AppStrings.of(context);
    final pendingSubtitle = s.awaitingPaymentVia(recipient.providerType);
    final settledSubtitle = s.remittanceTo(recipient.phoneOrAccount);

    Map<String, dynamic>? session;
    try {
      session = await widget.controller.sendMoneyWithResult(
        recipient: recipient,
        sourceAmount: _sourceAmount,
        sourceCurrency: _sourceCurrency,
        exchangeRate: _exchangeRate,
        amountBdt: _amountBdt,
        incentiveBdt: _incentiveBdt,
        pendingSubtitle: pendingSubtitle,
      );
    } catch (e) {
      if (!mounted) return false;
      _showFailure(_readableError(e));
      return false;
    }

    final checkoutUrl = session?['checkoutUrl']?.toString() ?? '';
    final sessionId = session?['sessionId']?.toString() ?? '';

    if (checkoutUrl.isEmpty) {
      widget.controller.discardPendingTransaction(sessionId);
      if (!mounted) return false;
      _showFailure(s.gatewayNoCheckoutPage);
      return false;
    }

    if (!await _openStripeCheckout(checkoutUrl)) {
      widget.controller.discardPendingTransaction(sessionId);
      if (!mounted) return false;
      _showFailure(s.couldNotOpenCheckout);
      return false;
    }

    if (!mounted) return false;

    // Payment happens outside the app, so wait here and ask Stripe whether the
    // session was actually paid before recording anything.
    final paid = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (_) => _AwaitingPaymentDialog(
            controller: widget.controller,
            sessionId: sessionId,
            checkoutUrl: checkoutUrl,
            recipientName: recipient.name,
          ),
        ) ??
        false;

    if (!paid) {
      widget.controller.discardPendingTransaction(sessionId);
      if (!mounted) return false;
      _showFailure(s.paymentNotCompleted);
      return false;
    }

    await widget.controller.completeRemittance(
      recipient: recipient,
      cardId: sourceCard.id,
      sourceAmount: _sourceAmount,
      sourceCurrency: _sourceCurrency,
      exchangeRate: _exchangeRate,
      amountBdt: _amountBdt,
      incentiveBdt: _incentiveBdt,
      sessionId: sessionId,
      settledSubtitle: settledSubtitle,
    );

    if (!mounted) return true;
    _showSuccessDialog();
    return true;
  }

  Future<bool> _openStripeCheckout(String checkoutUrl) async {
    final uri = Uri.tryParse(checkoutUrl);
    if (uri == null) return false;
    try {
      // The hosted page must own the whole screen, and the person needs the
      // browser's address bar to see they really are on checkout.stripe.com.
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint('[SendFlowView] Could not open Stripe Checkout: $e');
      return false;
    }
  }

  /// Gateway errors arrive as `Exception: Payment Gateway Error: ...`; show the
  /// message without the Dart wrapper.
  String _readableError(Object error) {
    final text = error.toString();
    return text.startsWith('Exception: ')
        ? text.substring('Exception: '.length)
        : text;
  }

  void _showFailure(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppColors.crimsonRed,
        duration: const Duration(seconds: 5),
      ),
    );
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
              Text(
                AppStrings.of(ctx).remittanceSuccessful,
                style: const TextStyle(
                  color: AppColors.royalBlue,
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                AppStrings.of(ctx).creditedTo(
                  '৳${_destinationAmount.toStringAsFixed(2)}',
                  _selectedRecipient?.name ?? '',
                  _selectedRecipient?.providerType ?? '',
                ),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.ink,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                AppStrings.of(ctx).appearsInHistory,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.inkMuted,
                  fontSize: 12,
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
                  child: Text(
                    AppStrings.of(ctx).done,
                    style: const TextStyle(fontWeight: FontWeight.w700),
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
    final s = AppStrings.of(context);

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
            _buildStepIndicator(0, s.stepRecipient),
            _buildStepDivider(),
            _buildStepIndicator(1, s.stepAmount),
            _buildStepDivider(),
            _buildStepIndicator(2, s.stepConfirm),
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
              : AppColors.inkMuted,
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

/// Holds the flow while the person pays on Stripe's hosted page.
///
/// The app cannot observe that page, so this polls the session's status, and
/// re-checks the moment the app comes back to the foreground — which is
/// normally the instant the person returns from the browser.
class _AwaitingPaymentDialog extends StatefulWidget {
  final PaymentController controller;
  final String sessionId;
  final String checkoutUrl;
  final String recipientName;

  const _AwaitingPaymentDialog({
    required this.controller,
    required this.sessionId,
    required this.checkoutUrl,
    required this.recipientName,
  });

  @override
  State<_AwaitingPaymentDialog> createState() => _AwaitingPaymentDialogState();
}

class _AwaitingPaymentDialogState extends State<_AwaitingPaymentDialog>
    with WidgetsBindingObserver {
  static const Duration _pollInterval = Duration(seconds: 3);

  /// Stop polling by itself after this long; the manual check stays available.
  static const Duration _pollWindow = Duration(minutes: 10);

  Timer? _poller;
  DateTime? _startedAt;
  bool _isChecking = false;
  bool _closed = false;

  @override
  void initState() {
    super.initState();
    _startedAt = DateTime.now();
    WidgetsBinding.instance.addObserver(this);
    _poller = Timer.periodic(_pollInterval, (_) => _check());
  }

  @override
  void dispose() {
    _poller?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _check();
  }

  Future<void> _check({bool manual = false}) async {
    if (_closed || _isChecking) return;

    final startedAt = _startedAt;
    if (!manual &&
        startedAt != null &&
        DateTime.now().difference(startedAt) > _pollWindow) {
      _poller?.cancel();
      return;
    }

    setState(() => _isChecking = true);
    bool paid = false;
    try {
      paid = await widget.controller.verifyCheckoutSession(widget.sessionId);
    } catch (e) {
      debugPrint('[AwaitingPayment] verify failed: $e');
    }

    if (!mounted) return;
    setState(() => _isChecking = false);

    if (paid) _close(true);
  }

  void _close(bool paid) {
    if (_closed) return;
    _closed = true;
    _poller?.cancel();
    Navigator.of(context).pop(paid);
  }

  Future<void> _reopenCheckout() async {
    final uri = Uri.tryParse(widget.checkoutUrl);
    if (uri == null) return;
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint('[AwaitingPayment] could not reopen Checkout: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);

    return Dialog(
      backgroundColor: AppColors.cloudDancer,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 46,
              height: 46,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                color: AppColors.royalBlue,
                backgroundColor: AppColors.royalBlue.withValues(alpha: 0.12),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              s.completePaymentOnStripe,
              style: const TextStyle(
                color: AppColors.royalBlue,
                fontSize: 17,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              s.stripeHandoffBody(widget.recipientName),
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.ink,
                fontSize: 12.5,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _isChecking ? null : _reopenCheckout,
                icon: const Icon(Icons.open_in_new_rounded, size: 18),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.royalBlue,
                  side: BorderSide(
                    color: AppColors.royalBlue.withValues(alpha: 0.4),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                label: Text(
                  s.reopenStripePage,
                  style:
                      const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                ),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isChecking ? null : () => _check(manual: true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.emeraldGreen,
                  foregroundColor: AppColors.cloudDancer,
                  disabledBackgroundColor:
                      AppColors.emeraldGreen.withValues(alpha: 0.5),
                  disabledForegroundColor: AppColors.cloudDancer,
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  elevation: 0,
                ),
                child: Text(
                  _isChecking ? s.checkingWithStripe : s.ivePaidCheckNow,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13.5,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 4),
            TextButton(
              onPressed: () => _close(false),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.crimsonRed,
              ),
              child: Text(
                s.cancelTransfer,
                style:
                    const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
