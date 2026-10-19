/// A country a Probashi Guard user can verify a mobile number in, and the
/// shape of a local mobile number there.
///
/// Numbers are typed the way people write them at home — 01712345678 in
/// Bangladesh, 0501234567 in Saudi Arabia — and only turned into E.164 when
/// they leave the screen. [minDigits] and [maxDigits] cap what the keypad
/// accepts, so a Bangladeshi number cannot run past its 11 digits.
class PhoneCountry {
  /// ISO 3166 code; also the key for the country's name in AppStrings.
  final String iso;
  final String flag;

  /// Without the plus, e.g. '880'.
  final String dialCode;

  final int minDigits;
  final int maxDigits;

  /// True where local numbers carry a leading 0 that E.164 drops: 01712345678
  /// in Bangladesh is +8801712345678, not +88001712345678.
  final bool trunkZero;

  /// A typical local mobile number, shown as the field's hint.
  final String example;

  const PhoneCountry({
    required this.iso,
    required this.flag,
    required this.dialCode,
    required this.minDigits,
    required this.maxDigits,
    required this.trunkZero,
    required this.example,
  });

  /// "11", or "10-11" where both lengths are in use.
  String get lengthLabel =>
      minDigits == maxDigits ? '$maxDigits' : '$minDigits-$maxDigits';

  bool isValidLocal(String digits) {
    if (!RegExp(r'^[0-9]+$').hasMatch(digits)) return false;
    if (digits.length < minDigits || digits.length > maxDigits) return false;
    return !trunkZero || digits.startsWith('0');
  }

  /// The number in the form Firebase and the server expect, or null when
  /// [isValidLocal] would refuse it.
  String? toE164(String digits) {
    if (!isValidLocal(digits)) return null;
    final national = trunkZero ? digits.substring(1) : digits;
    return '+$dialCode$national';
  }

  /// Bangladesh first: it is where every recipient is, and where most senders
  /// verify. The rest are where Probashi workers most often live.
  static const List<PhoneCountry> all = [
    PhoneCountry(
      iso: 'BD',
      flag: '🇧🇩',
      dialCode: '880',
      minDigits: 11,
      maxDigits: 11,
      trunkZero: true,
      example: '01712345678',
    ),
    PhoneCountry(
      iso: 'SA',
      flag: '🇸🇦',
      dialCode: '966',
      minDigits: 10,
      maxDigits: 10,
      trunkZero: true,
      example: '0501234567',
    ),
    PhoneCountry(
      iso: 'AE',
      flag: '🇦🇪',
      dialCode: '971',
      minDigits: 10,
      maxDigits: 10,
      trunkZero: true,
      example: '0501234567',
    ),
    PhoneCountry(
      iso: 'QA',
      flag: '🇶🇦',
      dialCode: '974',
      minDigits: 8,
      maxDigits: 8,
      trunkZero: false,
      example: '33123456',
    ),
    PhoneCountry(
      iso: 'KW',
      flag: '🇰🇼',
      dialCode: '965',
      minDigits: 8,
      maxDigits: 8,
      trunkZero: false,
      example: '50012345',
    ),
    PhoneCountry(
      iso: 'OM',
      flag: '🇴🇲',
      dialCode: '968',
      minDigits: 8,
      maxDigits: 8,
      trunkZero: false,
      example: '92123456',
    ),
    PhoneCountry(
      iso: 'MY',
      flag: '🇲🇾',
      dialCode: '60',
      minDigits: 10,
      maxDigits: 11,
      trunkZero: true,
      example: '0123456789',
    ),
    PhoneCountry(
      iso: 'SG',
      flag: '🇸🇬',
      dialCode: '65',
      minDigits: 8,
      maxDigits: 8,
      trunkZero: false,
      example: '81234567',
    ),
  ];

  static PhoneCountry get bangladesh => all.first;
}
