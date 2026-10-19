class CurrencyModel {
  final String code;
  final String symbol;
  final String name;
  final String flag;
  final double rateToBdt;

  const CurrencyModel({
    required this.code,
    required this.symbol,
    required this.name,
    required this.flag,
    required this.rateToBdt,
  });

  /// Standard conversion from BDT to this currency
  double convertFromBdt(double amountInBdt) {
    if (rateToBdt == 0) return 0.0;
    return amountInBdt / rateToBdt;
  }

  /// Standard conversion from this currency to BDT
  double convertToBdt(double amountInThisCurrency) {
    return amountInThisCurrency * rateToBdt;
  }

  /// Every transfer is charged through Stripe in USD regardless of what the
  /// sender typed or what the recipient is paid in, so the gateway sees one
  /// settlement currency.
  static const String settlementCurrency = 'USD';

  static CurrencyModel get usd =>
      supportedCurrencies.firstWhere((c) => c.code == settlementCurrency);

  /// VAT charged on the transfer commission.
  static const double vatOnCommissionRate = 0.0001; // 0.01%

  /// The VAT this transfer owes, in whatever currency [amount] is given in.
  static double vatOnCommission(double amount) => amount * vatOnCommissionRate;

  /// Converts an amount in this currency into the USD the gateway is charged.
  double toUsd(double amountInThisCurrency) {
    final usdRate = usd.rateToBdt;
    if (usdRate == 0) return 0.0;
    return convertToBdt(amountInThisCurrency) / usdRate;
  }

  /// Converts a USD gateway amount back into this currency, which is what the
  /// recipient's country is actually paid in.
  double fromUsd(double amountInUsd) {
    return convertFromBdt(amountInUsd * usd.rateToBdt);
  }

  static const List<CurrencyModel> supportedCurrencies = [
    CurrencyModel(
      code: 'BDT',
      symbol: '৳',
      name: 'Bangladeshi Taka',
      flag: '🇧🇩',
      rateToBdt: 1.0,
    ),
    CurrencyModel(
      code: 'SAR',
      symbol: '﷼',
      name: 'Saudi Riyal',
      flag: '🇸🇦',
      rateToBdt: 31.85,
    ),
    CurrencyModel(
      code: 'AED',
      symbol: 'د.إ',
      name: 'UAE Dirham',
      flag: '🇦🇪',
      rateToBdt: 32.50,
    ),
    CurrencyModel(
      code: 'QAR',
      symbol: 'ر.ق',
      name: 'Qatari Riyal',
      flag: '🇶🇦',
      rateToBdt: 32.80,
    ),
    CurrencyModel(
      code: 'USD',
      symbol: '\$',
      name: 'US Dollar',
      flag: '🇺🇸',
      rateToBdt: 119.50,
    ),
  ];
}
