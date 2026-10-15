class CountryModel {
  final String code; // BD, SA, AE, QA, KW, OM, MY, SG, US, GB, IN, PK, PH
  final String name;
  final String flag;
  final String dialCode;
  final String currencyCode;
  final String currencySymbol;
  final double rateToBdt; // e.g. 1 unit of foreign currency = X BDT
  final List<String> providers;
  final bool hasGovtRemittanceIncentive; // 2.5% official incentive for BDT

  const CountryModel({
    required this.code,
    required this.name,
    required this.flag,
    required this.dialCode,
    required this.currencyCode,
    required this.currencySymbol,
    required this.rateToBdt,
    required this.providers,
    this.hasGovtRemittanceIncentive = false,
  });

  static const List<CountryModel> supportedCountries = [
    CountryModel(
      code: 'BD',
      name: 'Bangladesh',
      flag: '🇧🇩',
      dialCode: '+880',
      currencyCode: 'BDT',
      currencySymbol: '৳',
      rateToBdt: 1.0,
      providers: ['bKash', 'Nagad', 'Rocket', 'Bank Account'],
      hasGovtRemittanceIncentive: true,
    ),
    CountryModel(
      code: 'SA',
      name: 'Saudi Arabia',
      flag: '🇸🇦',
      dialCode: '+966',
      currencyCode: 'SAR',
      currencySymbol: '﷼',
      rateToBdt: 31.85,
      providers: ['STC Pay', 'Urpay', 'Al Rajhi', 'Bank Account'],
      hasGovtRemittanceIncentive: false,
    ),
    CountryModel(
      code: 'AE',
      name: 'United Arab Emirates',
      flag: '🇦🇪',
      dialCode: '+971',
      currencyCode: 'AED',
      currencySymbol: 'د.إ',
      rateToBdt: 32.50,
      providers: ['e& money', 'Careem Pay', 'Liv.', 'Bank Account'],
      hasGovtRemittanceIncentive: false,
    ),
    CountryModel(
      code: 'QA',
      name: 'Qatar',
      flag: '🇶🇦',
      dialCode: '+974',
      currencyCode: 'QAR',
      currencySymbol: 'ر.ق',
      rateToBdt: 32.80,
      providers: ['Ooredoo Money', 'QNB', 'Bank Account'],
      hasGovtRemittanceIncentive: false,
    ),
    CountryModel(
      code: 'KW',
      name: 'Kuwait',
      flag: '🇰🇼',
      dialCode: '+965',
      currencyCode: 'KWD',
      currencySymbol: 'د.ك',
      rateToBdt: 388.50,
      providers: ['Weyay', 'NBK', 'Bank Account'],
      hasGovtRemittanceIncentive: false,
    ),
    CountryModel(
      code: 'OM',
      name: 'Oman',
      flag: '🇴🇲',
      dialCode: '+968',
      currencyCode: 'OMR',
      currencySymbol: 'ر.ع.',
      rateToBdt: 310.20,
      providers: ['Thawani', 'Bank Muscat'],
      hasGovtRemittanceIncentive: false,
    ),
    CountryModel(
      code: 'MY',
      name: 'Malaysia',
      flag: '🇲🇾',
      dialCode: '+60',
      currencyCode: 'MYR',
      currencySymbol: 'RM',
      rateToBdt: 27.20,
      providers: ['Touch n Go', 'DuitNow', 'Maybank'],
      hasGovtRemittanceIncentive: false,
    ),
    CountryModel(
      code: 'SG',
      name: 'Singapore',
      flag: '🇸🇬',
      dialCode: '+65',
      currencyCode: 'SGD',
      currencySymbol: 'S\$',
      rateToBdt: 91.40,
      providers: ['PayNow', 'DBS PayLah!', 'GrabPay'],
      hasGovtRemittanceIncentive: false,
    ),
    CountryModel(
      code: 'US',
      name: 'United States',
      flag: '🇺🇸',
      dialCode: '+1',
      currencyCode: 'USD',
      currencySymbol: '\$',
      rateToBdt: 119.50,
      providers: ['Zelle', 'PayPal', 'Bank Transfer'],
      hasGovtRemittanceIncentive: false,
    ),
    CountryModel(
      code: 'GB',
      name: 'United Kingdom',
      flag: '🇬🇧',
      dialCode: '+44',
      currencyCode: 'GBP',
      currencySymbol: '£',
      rateToBdt: 154.20,
      providers: ['Faster Payments', 'Revolut', 'Bank Transfer'],
      hasGovtRemittanceIncentive: false,
    ),
    CountryModel(
      code: 'IN',
      name: 'India',
      flag: '🇮🇳',
      dialCode: '+91',
      currencyCode: 'INR',
      currencySymbol: '₹',
      rateToBdt: 1.42,
      providers: ['UPI', 'Google Pay', 'PhonePe', 'Bank Account'],
      hasGovtRemittanceIncentive: false,
    ),
    CountryModel(
      code: 'PK',
      name: 'Pakistan',
      flag: '🇵🇰',
      dialCode: '+92',
      currencyCode: 'PKR',
      currencySymbol: '₨',
      rateToBdt: 0.43,
      providers: ['Easypaisa', 'JazzCash', 'Raast', 'Bank Account'],
      hasGovtRemittanceIncentive: false,
    ),
  ];

  static CountryModel get defaultCountry => supportedCountries[0];

  static CountryModel findByCode(String code) {
    return supportedCountries.firstWhere(
      (c) => c.code.toUpperCase() == code.toUpperCase(),
      orElse: () => defaultCountry,
    );
  }

  static CountryModel findByDialCode(String dialCode) {
    return supportedCountries.firstWhere(
      (c) => c.dialCode == dialCode,
      orElse: () => defaultCountry,
    );
  }
}
