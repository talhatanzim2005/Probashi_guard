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
