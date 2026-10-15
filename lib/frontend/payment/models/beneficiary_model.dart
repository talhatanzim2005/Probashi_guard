class BeneficiaryModel {
  final String id;
  final String name;
  final String phoneOrAccount;
  final String providerType; // bKash, Nagad, STC Pay, Careem Pay, Bank, etc.
  final String avatarUrl;
  final String initials;
  final bool isRecent;
  final String countryCode; // BD, SA, AE, QA, MY, US, etc.
  final String countryFlag; // 🇧🇩, 🇸🇦, 🇦🇪, 🇶🇦, 🇲🇾, 🇺🇸, etc.
  final String countryName; // Bangladesh, Saudi Arabia, UAE, etc.
  final String countryDialCode; // +880, +966, +971, +974, etc.
  final String currency; // BDT, SAR, AED, QAR, etc.
  final String currencySymbol; // ৳, ﷼, د.إ, ر.ق, etc.

  const BeneficiaryModel({
    required this.id,
    required this.name,
    required this.phoneOrAccount,
    required this.providerType,
    required this.avatarUrl,
    required this.initials,
    this.isRecent = true,
    this.countryCode = 'BD',
    this.countryFlag = '🇧🇩',
    this.countryName = 'Bangladesh',
    this.countryDialCode = '+880',
    this.currency = 'BDT',
    this.currencySymbol = '৳',
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'phone_or_account': phoneOrAccount,
      'provider_type': providerType,
      'avatar_url': avatarUrl,
      'initials': initials,
      'is_recent': isRecent,
      'country_code': countryCode,
      'country_flag': countryFlag,
      'country_name': countryName,
      'country_dial_code': countryDialCode,
      'currency': currency,
      'currency_symbol': currencySymbol,
    };
  }

  factory BeneficiaryModel.fromMap(Map<String, dynamic> map) {
    return BeneficiaryModel(
      id: map['id'] ?? '',
      name: map['name'] ?? '',
      phoneOrAccount: map['phone_or_account'] ?? '',
      providerType: map['provider_type'] ?? 'bKash',
      avatarUrl: map['avatar_url'] ?? '',
      initials: map['initials'] ??
          (map['name']?.isNotEmpty == true ? map['name'][0] : 'U'),
      isRecent: map['is_recent'] ?? true,
      countryCode: map['country_code'] ?? 'BD',
      countryFlag: map['country_flag'] ?? '🇧🇩',
      countryName: map['country_name'] ?? 'Bangladesh',
      countryDialCode: map['country_dial_code'] ?? '+880',
      currency: map['currency'] ?? 'BDT',
      currencySymbol: map['currency_symbol'] ?? '৳',
    );
  }
}
