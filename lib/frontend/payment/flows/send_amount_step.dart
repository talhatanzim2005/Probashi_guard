import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../l10n/app_strings.dart';
import '../../../theme/app_colors.dart';
import '../controllers/payment_controller.dart';
import '../models/beneficiary_model.dart';
import '../models/country_model.dart';
import '../models/currency_model.dart';
import '../models/wallet_card_model.dart';
import '../widgets/amount_numpad.dart';

class SendAmountStep extends StatefulWidget {
  final BeneficiaryModel recipient;
  final PaymentController controller;
  final void Function({
    required WalletCardModel sourceCard,
    required double sourceAmount,
    required String sourceCurrency,
    required double destinationAmount,
    required String destinationCurrency,
    required double exchangeRate,
    required double amountBdt,
    required double incentiveBdt,
    required double vatOnCommission,
    required double usdAmount,
  })
  onProceed;

  const SendAmountStep({
    super.key,
    required this.recipient,
    required this.controller,
    required this.onProceed,
  });

  @override
  State<SendAmountStep> createState() => _SendAmountStepState();
}

class _SendAmountStepState extends State<SendAmountStep> {
  final TextEditingController _amountController = TextEditingController(
    text: '100',
  );
  late WalletCardModel _selectedCard;
  CurrencyModel _inputCurrency =
      CurrencyModel.supportedCurrencies[1]; // SAR default

  @override
  void initState() {
    super.initState();
    _selectedCard =
        widget.controller.activeCard ??
        (widget.controller.cards.isNotEmpty
            ? widget.controller.cards.first
            : const WalletCardModel(
                id: 'wps',
                title: 'WPS Payroll Card',
                providerName: 'Al Rajhi',
                cardNumberMasked: '•••• 8420',
                balance: 50000.00,
                currency: 'BDT',
                expiryDate: '12/28',
                cardType: CardType.wpsPayroll,
                primaryColor: Color(0xFF111625),
                accentColor: AppColors.emeraldGreen,
              ));
    _inputCurrency = widget.controller.selectedCurrency;
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  double get _enteredAmount =>
      double.tryParse(_amountController.text.trim()) ?? 0.0;

  /// Recipient's destination country information
  CountryModel get _destCountry =>
      CountryModel.findByCode(widget.recipient.countryCode);

  /// Convert source input amount to baseline BDT
  double get _amountInBdt {
    if (_inputCurrency.code == 'BDT') return _enteredAmount;
    return _inputCurrency.convertToBdt(_enteredAmount);
  }

  /// Official 2.5% Bangladesh government cash incentive for remitters to Bangladesh
  bool get _isRemittanceToBangladesh =>
      widget.recipient.countryCode.toUpperCase() == 'BD';

  double get _govtIncentive {
    if (!_isRemittanceToBangladesh) return 0.0;
    return _amountInBdt * 0.025;
  }

  /// Converted amount the recipient gets in their local country currency
  double get _destinationAmount {
    final destRate = _destCountry.rateToBdt;
    if (destRate <= 0) return 0.0;

    if (_isRemittanceToBangladesh) {
      return _amountInBdt + _govtIncentive;
    } else {
      return _amountInBdt / destRate;
    }
  }

  /// Exchange rate between chosen input currency and recipient's currency
  double get _exchangeRate {
    final destRate = _destCountry.rateToBdt;
    if (destRate <= 0) return 1.0;
    return _inputCurrency.rateToBdt / destRate;
  }

  /// VAT on the transfer commission, in the currency the sender typed in.
  double get _vatOnCommission => CurrencyModel.vatOnCommission(_enteredAmount);

  /// What leaves the sender's card: the transfer plus the VAT on commission.
  double get _totalDebit => _enteredAmount + _vatOnCommission;

  /// Stripe is always charged in USD, whatever the sender typed in.
  double get _usdSettlement => _inputCurrency.toUsd(_totalDebit);

  Widget _buildBreakdownRow(
    String label,
    String value, {
    bool emphasised = false,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        // A long label wraps instead of pushing the figure off the card.
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              color: AppColors.inkMuted,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          value,
          style: TextStyle(
            color: emphasised ? AppColors.ink : AppColors.inkMuted,
            fontSize: emphasised ? 13.5 : 12.5,
            fontWeight: emphasised ? FontWeight.w800 : FontWeight.w600,
          ),
        ),
      ],
    );
  }

  void _addAmount(double addVal) {
    HapticFeedback.selectionClick();
    final current = _enteredAmount;
    _amountController.text = (current + addVal).toStringAsFixed(0);
    setState(() {});
  }

  void _handleContinue() {
    final amount = _enteredAmount;
    if (amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppStrings.of(context).enterAmountGreaterThanZero),
          backgroundColor: AppColors.crimsonRed,
        ),
      );
      return;
    }

    if (_inputCurrency.convertToBdt(_totalDebit) > _selectedCard.balance) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppStrings.of(context).amountExceedsBalance),
          backgroundColor: AppColors.crimsonRed,
        ),
      );
      return;
    }

    widget.onProceed(
      sourceCard: _selectedCard,
      sourceAmount: amount,
      sourceCurrency: _inputCurrency.code,
      destinationAmount: _destinationAmount,
      destinationCurrency: widget.recipient.currency,
      exchangeRate: _exchangeRate,
      amountBdt: _amountInBdt,
      incentiveBdt: _govtIncentive,
      vatOnCommission: _vatOnCommission,
      usdAmount: _usdSettlement,
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final cards = widget.controller.cards;

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Recipient Card Summary Banner with Country Flag
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: AppColors.royalBlue.withValues(alpha: 0.15),
                width: 1,
              ),
            ),
            child: Row(
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    CircleAvatar(
                      radius: 20,
                      backgroundColor: AppColors.royalBlue.withValues(
                        alpha: 0.12,
                      ),
                      child: Text(
                        widget.recipient.initials,
                        style: const TextStyle(
                          color: AppColors.royalBlue,
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                        ),
                      ),
                    ),
                    Positioned(
                      bottom: -2,
                      right: -2,
                      child: Text(
                        widget.recipient.countryFlag,
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              widget.recipient.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: AppColors.ink,
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              '(${widget.recipient.countryName})',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: AppColors.inkMuted,
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                      Text(
                        '${widget.recipient.providerType} • ${widget.recipient.phoneOrAccount}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.inkMuted,
                          fontSize: 11.5,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.emeraldGreen.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    s.active,
                    style: const TextStyle(
                      color: AppColors.emeraldGreen,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Source Card Selector
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: AppColors.royalBlue.withValues(alpha: 0.15),
                width: 1,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  s.payFrom,
                  style: const TextStyle(
                    color: AppColors.inkMuted,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.6,
                  ),
                ),
                DropdownButtonHideUnderline(
                  child: DropdownButton<WalletCardModel>(
                    value: _selectedCard,
                    isExpanded: true,
                    icon: const Icon(
                      Icons.keyboard_arrow_down,
                      color: AppColors.royalBlue,
                    ),
                    items: cards.map((c) {
                      return DropdownMenuItem<WalletCardModel>(
                        value: c,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(
                                c.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: AppColors.ink,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13.5,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                s.availableShort(
                                  '৳${c.balance.toStringAsFixed(0)}',
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: AppColors.inkMuted,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                    onChanged: (c) {
                      if (c != null) setState(() => _selectedCard = c);
                    },
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),

          // Dual Currency Amount Card
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: AppColors.royalBlue.withValues(alpha: 0.18),
                width: 1.2,
              ),
              boxShadow: [
                BoxShadow(
                  color: AppColors.royalBlue.withValues(alpha: 0.04),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  s.sendAmount,
                  style: const TextStyle(
                    color: AppColors.inkMuted,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(height: 8),

                // Large Amount Input with Currency Symbol
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text(
                      _inputCurrency.symbol,
                      style: const TextStyle(
                        color: AppColors.ink,
                        fontSize: 32,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(width: 6),
                    IntrinsicWidth(
                      child: TextField(
                        controller: _amountController,
                        // The on-screen numpad below is the only way in, so the
                        // system keyboard never opens and nothing but digits
                        // can ever be entered — on every platform.
                        readOnly: true,
                        showCursor: true,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: AppColors.ink,
                          fontSize: 36,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.5,
                        ),
                        decoration: const InputDecoration(
                          border: InputBorder.none,
                          hintText: '0',
                          isDense: true,
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),

                // Currency selector dropdown
                DropdownButtonHideUnderline(
                  child: DropdownButton<CurrencyModel>(
                    value: _inputCurrency,
                    items: CurrencyModel.supportedCurrencies.map((cur) {
                      return DropdownMenuItem<CurrencyModel>(
                        value: cur,
                        child: Text(
                          '${cur.flag} ${cur.code} (${cur.symbol})',
                          style: const TextStyle(
                            color: AppColors.royalBlue,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      );
                    }).toList(),
                    onChanged: (newCur) {
                      if (newCur != null) {
                        setState(() => _inputCurrency = newCur);
                      }
                    },
                  ),
                ),
                Divider(
                  color: AppColors.royalBlue.withValues(alpha: 0.1),
                  height: 24,
                ),

                // Destination Live Conversion with Recipient's Country Flag & Name
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          Text(
                            widget.recipient.countryFlag,
                            style: const TextStyle(fontSize: 15),
                          ),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              s.recipientGetsIn(widget.recipient.countryName),
                              style: const TextStyle(
                                color: AppColors.ink,
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${widget.recipient.currencySymbol}${_destinationAmount.toStringAsFixed(2)}',
                      style: const TextStyle(
                        color: AppColors.emeraldGreen,
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
                Divider(
                  color: AppColors.royalBlue.withValues(alpha: 0.1),
                  height: 22,
                ),

                // Fee breakdown and the USD the gateway actually charges.
                _buildBreakdownRow(
                  '${s.vatOnCommission} (0.01%)',
                  '${_inputCurrency.symbol}${_vatOnCommission.toStringAsFixed(2)}',
                ),
                const SizedBox(height: 6),
                _buildBreakdownRow(
                  s.totalDebited,
                  '${_inputCurrency.symbol}${_totalDebit.toStringAsFixed(2)}',
                  emphasised: true,
                ),
                const SizedBox(height: 6),
                _buildBreakdownRow(
                  s.chargedInUsd,
                  '\$${_usdSettlement.toStringAsFixed(2)}',
                  emphasised: true,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Exchange Rate Banner (with Govt Incentive for BD, or Direct Exchange for other countries)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.emeraldGreen.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: AppColors.emeraldGreen.withValues(alpha: 0.25),
                width: 1,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  _isRemittanceToBangladesh
                      ? Icons.stars_rounded
                      : Icons.sync_alt_rounded,
                  color: AppColors.emeraldGreen,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _isRemittanceToBangladesh
                        ? '1 ${_inputCurrency.code} = ৳${_exchangeRate.toStringAsFixed(2)} • ${s.govtIncentive} ৳${_govtIncentive.toStringAsFixed(2)} (2.5%)'
                        : '1 ${_inputCurrency.code} = ${widget.recipient.currencySymbol}${_exchangeRate.toStringAsFixed(2)} • ${s.guaranteedSettlement(widget.recipient.countryName)}',
                    style: const TextStyle(
                      color: AppColors.emeraldGreen,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // The keypad the amount is typed on.
          AmountNumpad(
            controller: _amountController,
            onChanged: () => setState(() {}),
          ),
          const SizedBox(height: 14),

          // Quick Amount Preset Chips
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [50, 100, 250, 500, 1000].map((val) {
              return ActionChip(
                label: Text('+${_inputCurrency.symbol}$val'),
                backgroundColor: Colors.white,
                labelStyle: const TextStyle(
                  color: AppColors.royalBlue,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(
                    color: AppColors.royalBlue.withValues(alpha: 0.2),
                  ),
                ),
                onPressed: () => _addAmount(val.toDouble()),
              );
            }).toList(),
          ),
          const SizedBox(height: 24),

          // Next Step Button
          ElevatedButton(
            onPressed: _handleContinue,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.royalBlue,
              foregroundColor: AppColors.cloudDancer,
              padding: const EdgeInsets.symmetric(vertical: 15),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              elevation: 0,
            ),
            child: Text(
              s.reviewTransferDetails,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.2,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
