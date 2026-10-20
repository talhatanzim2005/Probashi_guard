/// A country a Probashi Guard user can verify a mobile number in, and the
/// shape of a local mobile number there.
///
/// The field shows the country's dial code (+880) in front of what is typed,
/// so what is typed is the national number without the trunk 0: 1712345678 in
/// Bangladesh, 501234567 in Saudi Arabia. [minDigits] and [maxDigits] count
/// those national digits, so a Bangladeshi number cannot run past its 10.
///
/// People still write numbers the way they do at home (01712345678), and
/// autofill and paste hand them over that way. [stripTrunkZero] drops that
/// leading 0, so both forms end up the same and only become E.164 when they
/// leave the screen.
class PhoneCountry {
  /// ISO 3166 code; also the key for the country's name in AppStrings.
  final String iso;
  final String flag;

  /// Without the plus, e.g. '880'.
  final String dialCode;

  final int minDigits;
  final int maxDigits;

  /// True where local numbers are written with a leading 0 that E.164 drops:
  /// 01712345678 in Bangladesh is +8801712345678, not +88001712345678. The 0
  /// is never part of [minDigits]/[maxDigits]; it is removed as it is typed.
  final bool trunkZero;

  /// A typical national mobile number (no trunk 0), shown as the field's hint.
  final String example;

  /// Regular expression a valid national mobile number must match, where that
  /// is stricter than its length. Null means length alone decides. Kept as a
  /// string because a RegExp cannot sit in a const constructor.
  final String? nationalPattern;

  const PhoneCountry({
    required this.iso,
    required this.flag,
    required this.dialCode,
    required this.minDigits,
    required this.maxDigits,
    required this.trunkZero,
    required this.example,
    this.nationalPattern,
  });

  /// "10", or "9-10" where both lengths are in use.
  String get lengthLabel =>
      minDigits == maxDigits ? '$maxDigits' : '$minDigits-$maxDigits';

  /// [digits] without the trunk 0 people write at home, where this country
  /// has one: 01712345678 becomes 1712345678. Anything else is returned as is.
  String stripTrunkZero(String digits) =>
      trunkZero && digits.startsWith('0') ? digits.substring(1) : digits;

  /// True for a national number, typed with or without its trunk 0.
  bool isValidLocal(String digits) {
    final national = stripTrunkZero(digits);
    if (!RegExp(r'^[0-9]+$').hasMatch(national)) return false;
    if (national.length < minDigits || national.length > maxDigits) {
      return false;
    }
    final pattern = nationalPattern;
    return pattern == null || RegExp(pattern).hasMatch(national);
  }

  /// The number in the form Firebase and the server expect, or null when
  /// [isValidLocal] would refuse it.
  String? toE164(String digits) {
    if (!isValidLocal(digits)) return null;
    return '+$dialCode${stripTrunkZero(digits)}';
  }

  /// Bangladesh first: it is where every recipient is, and where most senders
  /// verify. The rest are where Probashi workers most often live.
  static const List<PhoneCountry> all = [
    PhoneCountry(
      iso: 'BD',
      flag: '🇧🇩',
      dialCode: '880',
      minDigits: 10,
      maxDigits: 10,
      trunkZero: true,
      example: '1712345678',
      // Mobile operators use 013-019; 1[3-9] then eight more digits.
      nationalPattern: r'^1[3-9][0-9]{8}$',
    ),
    PhoneCountry(
      iso: 'SA',
      flag: '🇸🇦',
      dialCode: '966',
      minDigits: 9,
      maxDigits: 9,
      trunkZero: true,
      example: '501234567',
    ),
    PhoneCountry(
      iso: 'AE',
      flag: '🇦🇪',
      dialCode: '971',
      minDigits: 9,
      maxDigits: 9,
      trunkZero: true,
      example: '501234567',
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
      minDigits: 9,
      maxDigits: 10,
      trunkZero: true,
      example: '123456789',
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