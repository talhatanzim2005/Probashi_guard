import 'package:flutter/material.dart';
import '../../../l10n/app_strings.dart';
import '../../theme/app_colors.dart';
import 'controllers/payment_controller.dart';
import 'flows/send_flow_view.dart';
import 'models/beneficiary_model.dart';
import 'models/country_model.dart';
import 'widgets/currency_selector_pill.dart';
import 'widgets/payment_card_deck.dart';
import 'widgets/quick_action_buttons.dart';
import 'widgets/quick_send_section.dart';
import 'widgets/receive_bottom_sheet.dart';
import 'widgets/transaction_history_section.dart';
import 'widgets/transfer_dialog.dart';

class PaymentView extends StatefulWidget {
  final PaymentController? controller;

  const PaymentView({super.key, this.controller});

  @override
  State<PaymentView> createState() => _PaymentViewState();
}

class _PaymentViewState extends State<PaymentView> {
  final PaymentController _controller = PaymentController.instance;

  void _openSendFlow([BeneficiaryModel? recipient]) {
    SendFlowView.push(
      context,
      controller: _controller,
      recipient: recipient,
    );
  }

  void _openReceiveModal() {
    ReceiveBottomSheet.show(context, _controller);
  }

  void _openTransferDialog() {
    TransferDialog.show(context, _controller);
  }

  void _openAddBeneficiaryDialog() {
    final nameController = TextEditingController();
    final phoneController = TextEditingController();
    CountryModel selectedCountry = CountryModel.defaultCountry;
    String selectedProvider = selectedCountry.providers.first;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Container(
          decoration: const BoxDecoration(
            color: AppColors.cloudDancer,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: EdgeInsets.fromLTRB(
            22,
            16,
            22,
            MediaQuery.of(ctx).viewInsets.bottom + 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.royalBlue.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                AppStrings.of(context).addBeneficiary,
                style: const TextStyle(
                  color: AppColors.royalBlue,
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                AppStrings.of(context).addBeneficiarySubtitle,
                style: TextStyle(
                  color: AppColors.royalBlue.withValues(alpha: 0.6),
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 16),

              // Country / Nationality Selector
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppColors.royalBlue.withValues(alpha: 0.18),
                  ),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<CountryModel>(
                    value: selectedCountry,
                    isExpanded: true,
                    icon: const Icon(Icons.arrow_drop_down, color: AppColors.royalBlue),
                    items: CountryModel.supportedCountries.map((c) {
                      return DropdownMenuItem<CountryModel>(
                        value: c,
                        child: Row(
                          children: [
                            Text(c.flag, style: const TextStyle(fontSize: 18)),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '${c.name} (${c.dialCode})',
                                style: const TextStyle(
                                  color: AppColors.royalBlue,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                    onChanged: (newC) {
                      if (newC != null) {
                        setSheetState(() {
                          selectedCountry = newC;
                          selectedProvider = newC.providers.first;
                        });
                      }
                    },
                  ),
                ),
              ),
              const SizedBox(height: 12),

              TextField(
                controller: nameController,
                decoration: InputDecoration(
                  labelText: AppStrings.of(context).recipientFullName,
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: phoneController,
                keyboardType: TextInputType.phone,
                decoration: InputDecoration(
                  labelText: AppStrings.of(context)
                      .mobileNumberHint(selectedCountry.dialCode),
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 12),

              // Dynamic Providers for Selected Country
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: selectedCountry.providers.map((provider) {
                    final isSelected = selectedProvider == provider;
                    return Padding(
                      padding: const EdgeInsets.only(right: 8.0),
                      child: ChoiceChip(
                        label: Text(provider),
                        selected: isSelected,
                        selectedColor: AppColors.royalBlue,
                        backgroundColor: Colors.white,
                        labelStyle: TextStyle(
                          color: isSelected ? AppColors.cloudDancer : AppColors.royalBlue,
                          fontWeight: FontWeight.w700,
                        ),
                        onSelected: (val) {
                          if (val) setSheetState(() => selectedProvider = provider);
                        },
                      ),
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () {
                  final name = nameController.text.trim();
                  final phone = phoneController.text.trim();
                  if (name.isEmpty || phone.isEmpty) return;

                  final fullPhone = phone.startsWith('+')
                      ? phone
                      : '${selectedCountry.dialCode} $phone';

                  final newBen = BeneficiaryModel(
                    id: 'ben_${DateTime.now().millisecondsSinceEpoch}',
                    name: name,
                    phoneOrAccount: fullPhone,
                    providerType: selectedProvider,
                    avatarUrl: '',
                    initials: name.isNotEmpty ? name[0].toUpperCase() : 'B',
                    countryCode: selectedCountry.code,
                    countryFlag: selectedCountry.flag,
                    countryName: selectedCountry.name,
                    countryDialCode: selectedCountry.dialCode,
                    currency: selectedCountry.currencyCode,
                    currencySymbol: selectedCountry.currencySymbol,
                  );

                  _controller.addBeneficiary(newBen);
                  Navigator.pop(ctx);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.royalBlue,
                  foregroundColor: AppColors.cloudDancer,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: Text(AppStrings.of(context).saveBeneficiary,
                    style: const TextStyle(fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showAllTransactionsModal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.75,
        maxChildSize: 0.95,
        minChildSize: 0.5,
        builder: (_, scrollController) => Container(
          decoration: const BoxDecoration(
            color: AppColors.cloudDancer,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 12),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.royalBlue.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                AppStrings.of(context).completeLedger,
                style: const TextStyle(
                  color: AppColors.royalBlue,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 14),
              Expanded(
                child: ListView.separated(
                  controller: scrollController,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  itemCount: _controller.transactions.length,
                  separatorBuilder: (context, index) => Divider(
                    color: AppColors.royalBlue.withValues(alpha: 0.08),
                  ),
                  itemBuilder: (_, index) {
                    final tx = _controller.transactions[index];
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: CircleAvatar(
                        backgroundColor: tx.isIncoming
                            ? AppColors.emeraldGreen.withValues(alpha: 0.12)
                            : AppColors.royalBlue.withValues(alpha: 0.1),
                        child: Icon(
                          tx.isIncoming ? Icons.arrow_downward : Icons.arrow_upward,
                          color: tx.isIncoming ? AppColors.emeraldGreen : AppColors.royalBlue,
                          size: 18,
                        ),
                      ),
                      title: Text(
                        tx.title,
                        style: const TextStyle(
                          color: AppColors.ink,
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                      subtitle: Text(
                        '${tx.subtitle} • ${tx.timestamp.day}/${tx.timestamp.month}/${tx.timestamp.year}',
                        style: const TextStyle(
                          color: AppColors.inkMuted,
                          fontSize: 12,
                        ),
                      ),
                      trailing: Text(
                        '${tx.isIncoming ? '+' : '-'}${tx.currency} ${tx.amount.toStringAsFixed(2)}',
                        style: TextStyle(
                          color: tx.isPending
                              ? AppColors.inkMuted
                              : (tx.isIncoming
                                  ? AppColors.emeraldGreen
                                  : AppColors.ink),
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) {
        if (_controller.isLoading) {
          return const Center(
            child: CircularProgressIndicator(color: AppColors.royalBlue),
          );
        }

        return RefreshIndicator(
          color: AppColors.royalBlue,
          backgroundColor: AppColors.cloudDancer,
          onRefresh: _controller.init,
          child: Stack(
            children: [
              // Subtle background watermark "PROBASHI" matching the "GIVPAY" watermark in mockup
              Positioned(
                top: 40,
                left: -20,
                right: -20,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    'PROBASHI',
                    style: TextStyle(
                      fontSize: 110,
                      fontWeight: FontWeight.w900,
                      color: AppColors.royalBlue.withValues(alpha: 0.035),
                      letterSpacing: 8,
                    ),
                  ),
                ),
              ),

              // Main Scrollable Content
              ListView(
                padding: const EdgeInsets.fromLTRB(18, 12, 18, 30),
                children: [
                  // Currency Selector Pill Row
                  Row(
                    children: [
                      const Icon(
                        Icons.currency_exchange_rounded,
                        size: 16,
                        color: AppColors.royalBlue,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        AppStrings.of(context).currency,
                        style: const TextStyle(
                          color: AppColors.royalBlueMuted,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerRight,
                            child: CurrencySelectorPill(controller: _controller),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // 3D Layered Card Deck (WPS, Multi-Currency, bKash)
                  PaymentCardDeck(controller: _controller),
                  const SizedBox(height: 22),

                  // Quick Action Buttons Row (Send, Receive, Transfer)
                  QuickActionButtons(
                    onSendTap: () => _openSendFlow(),
                    onReceiveTap: _openReceiveModal,
                    onTransferTap: _openTransferDialog,
                  ),
                  const SizedBox(height: 26),

                  // Quick Send Contacts Horizontal List
                  QuickSendSection(
                    beneficiaries: _controller.beneficiaries,
                    onBeneficiaryTap: (contact) => _openSendFlow(contact),
                    onAddTap: _openAddBeneficiaryDialog,
                  ),
                  const SizedBox(height: 26),

                  // Transaction History List Section
                  TransactionHistorySection(
                    controller: _controller,
                    onSeeAllTap: _showAllTransactionsModal,
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}