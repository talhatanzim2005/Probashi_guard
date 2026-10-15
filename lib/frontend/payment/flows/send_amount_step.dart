import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../theme/app_colors.dart';
import '../controllers/payment_controller.dart';
import '../models/beneficiary_model.dart';
import '../models/country_model.dart';
import '../models/currency_model.dart';
import '../models/wallet_card_model.dart';

class SendAmountStep extends StatefulWidget {
  final BeneficiaryModel recipient;
  final PaymentController controller;
  final void Function({
    required WalletCardModel sourceCard,
    required double sourceAmount,
    required String sourceCurrency,
    required double destinationAmount,
    required String destinationCurrency,
  }) onProceed;

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
  final TextEditingController _amountController = TextEditingController(text: '100');
  late WalletCardModel _selectedCard;
  CurrencyModel _inputCurrency = CurrencyModel.supportedCurrencies[1]; // SAR default

  @override
  void initState() {
    super.initState();
    _selectedCard = widget.controller.activeCard ??
        (widget.controller.cards.isNotEmpty
            ? widget.controller.cards.first
            : const WalletCardModel(
                id: 'wps',
                title: 'WPS Payroll Card',
                providerName: 'Al Rajhi',
                cardNumberMasked: '•••• 8420',
                balance: 98420.12,
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

  double get _enteredAmount => double.tryParse(_amountController.text.trim()) ?? 0.0;

  /// Recipient's destination country information
  CountryModel get _destCountry => CountryModel.findByCode(widget.recipient.countryCode);

  /// Convert source input amount to baseline BDT
  double get _amountInBdt {
    if (_inputCurrency.code == 'BDT') return _enteredAmount;
    return _inputCurrency.convertToBdt(_enteredAmount);
  }

  /// Official 2.5% Bangladesh government cash incentive for remitters to Bangladesh
  bool get _isRemittanceToBangladesh => widget.recipient.countryCode.toUpperCase() == 'BD';

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
        const SnackBar(
          content: Text('Please enter an amount greater than 0'),
          backgroundColor: AppColors.crimsonRed,
        ),
      );
      return;
    }

    if (_amountInBdt > _selectedCard.balance) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Entered amount exceeds your available card balance'),
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
    );
  }

  @override
  Widget build(BuildContext context) {
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
                      backgroundColor: AppColors.royalBlue.withValues(alpha: 0.12),
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
                          Text(
                            widget.recipient.name,
                            style: const TextStyle(
                              color: AppColors.royalBlue,
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '(${widget.recipient.countryName})',
                            style: TextStyle(
                              color: AppColors.royalBlue.withValues(alpha: 0.5),
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                      Text(
                        '${widget.recipient.providerType} • ${widget.recipient.phoneOrAccount}',
                        style: TextStyle(
                          color: AppColors.royalBlue.withValues(alpha: 0.6),
                          fontSize: 11.5,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.emeraldGreen.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    'Active',
                    style: TextStyle(
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
                  'PAY FROM',
                  style: TextStyle(
                    color: AppColors.royalBlue.withValues(alpha: 0.5),
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.6,
                  ),
                ),
                DropdownButtonHideUnderline(
                  child: DropdownButton<WalletCardModel>(
                    value: _selectedCard,
                    isExpanded: true,
                    icon: const Icon(Icons.keyboard_arrow_down, color: AppColors.royalBlue),
                    items: cards.map((c) {
                      return DropdownMenuItem<WalletCardModel>(
                        value: c,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              c.title,
                              style: const TextStyle(
                                color: AppColors.royalBlue,
                                fontWeight: FontWeight.w700,
                                fontSize: 13.5,
                              ),
                            ),
                            Text(
                              'Avail: ৳${c.balance.toStringAsFixed(0)}',
                              style: TextStyle(
                                color: AppColors.royalBlue.withValues(alpha: 0.6),
                                fontSize: 12,
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
                  'SEND AMOUNT',
                  style: TextStyle(
                    color: AppColors.royalBlue.withValues(alpha: 0.5),
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
                        color: AppColors.royalBlue,
                        fontSize: 32,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(width: 6),
                    IntrinsicWidth(
                      child: TextField(
                        controller: _amountController,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        onChanged: (_) => setState(() {}),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: AppColors.royalBlue,
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
                    Row(
                      children: [
                        Text(
                          widget.recipient.countryFlag,
                          style: const TextStyle(fontSize: 15),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Recipient Gets in ${widget.recipient.countryName}:',
                          style: TextStyle(
                            color: AppColors.royalBlue.withValues(alpha: 0.7),
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
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
                  _isRemittanceToBangladesh ? Icons.stars_rounded : Icons.sync_alt_rounded,
                  color: AppColors.emeraldGreen,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _isRemittanceToBangladesh
                        ? '1 ${_inputCurrency.code} = ৳${_exchangeRate.toStringAsFixed(2)} • Includes ৳${_govtIncentive.toStringAsFixed(2)} (2.5% Bangladesh Govt Remittance Incentive)'
                        : '1 ${_inputCurrency.code} = ${widget.recipient.currencySymbol}${_exchangeRate.toStringAsFixed(2)} • Verified Cross-Border Remittance to ${widget.recipient.countryName}',
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
            child: const Text(
              'Review Transfer Details',
              style: TextStyle(
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
