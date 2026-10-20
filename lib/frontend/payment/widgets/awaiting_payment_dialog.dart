import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../l10n/app_strings.dart';
import '../../../theme/app_colors.dart';
import '../controllers/payment_controller.dart';

/// Holds a payment flow while the person pays on Stripe's hosted page.
///
/// The app cannot observe that page, so this polls the session's status, and
/// re-checks the moment the app comes back to the foreground — which is
/// normally the instant the person returns from the browser.
///
/// Pops with `true` once Stripe reports the session paid, `false` otherwise.
class AwaitingPaymentDialog extends StatefulWidget {
  final PaymentController controller;
  final String sessionId;
  final String checkoutUrl;

  /// Who or what is being paid, shown in the dialog body.
  final String recipientName;

  const AwaitingPaymentDialog({
    super.key,
    required this.controller,
    required this.sessionId,
    required this.checkoutUrl,
    required this.recipientName,
  });

  @override
  State<AwaitingPaymentDialog> createState() => _AwaitingPaymentDialogState();
}

class _AwaitingPaymentDialogState extends State<AwaitingPaymentDialog>
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
      // Taller than a phone held sideways, so it scrolls rather than overflow.
      child: SingleChildScrollView(
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
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
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
                  disabledBackgroundColor: AppColors.emeraldGreen.withValues(
                    alpha: 0.5,
                  ),
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
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
