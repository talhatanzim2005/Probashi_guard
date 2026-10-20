import 'package:flutter_test/flutter_test.dart';
import 'package:probashi_guard/frontend/payment/models/beneficiary_model.dart';
import 'package:probashi_guard/frontend/payment/utils/phone_search_helper.dart';

/// TC-SEARCH-RECIPIENT: finding a saved recipient the way people look for a
/// contact — by name, country, provider, or any piece of their number.
void main() {
  const elizabeth = BeneficiaryModel(
    id: 'ben_1',
    name: 'Elizabeth',
    phoneOrAccount: '+880 1712-345678',
    providerType: 'bKash',
    avatarUrl: '',
    initials: 'EL',
  );
  const william = BeneficiaryModel(
    id: 'ben_2',
    name: 'William',
    phoneOrAccount: '+966 55 123 4567',
    providerType: 'STC Pay',
    avatarUrl: '',
    initials: 'WI',
    countryCode: 'SA',
    countryFlag: '🇸🇦',
    countryName: 'Saudi Arabia',
    countryDialCode: '+966',
    currency: 'SAR',
    currencySymbol: '﷼',
  );

  bool match(BeneficiaryModel c, String q) => PhoneSearchHelper.matches(c, q);

  test('an empty or blank query shows everyone', () {
    expect(match(elizabeth, ''), isTrue);
    expect(match(elizabeth, '   '), isTrue);
  });

  test('name: case-insensitive, any part of it', () {
    expect(match(elizabeth, 'eliz'), isTrue);
    expect(match(elizabeth, 'ELIZABETH'), isTrue);
    expect(match(elizabeth, 'beth'), isTrue);
    expect(match(elizabeth, 'william'), isFalse);
  });

  test('country by name, ISO code and flag', () {
    expect(match(william, 'saudi'), isTrue);
    expect(match(william, 'sa'), isTrue);
    expect(match(william, '🇸🇦'), isTrue);
    expect(match(elizabeth, 'saudi'), isFalse);
  });

  test('provider', () {
    expect(match(elizabeth, 'bkash'), isTrue);
    expect(match(william, 'stc'), isTrue);
    expect(match(william, 'bkash'), isFalse);
  });

  group('number, however the person types it', () {
    test('the whole number, with or without the separators', () {
      expect(match(elizabeth, '+880 1712-345678'), isTrue);
      expect(match(elizabeth, '+8801712345678'), isTrue);
      expect(match(elizabeth, '8801712345678'), isTrue);
    });

    test('the local form with the leading zero (01712345678)', () {
      expect(match(elizabeth, '01712345678'), isTrue);
      expect(match(elizabeth, '01712'), isTrue);
    });

    test('a piece from the middle or the end', () {
      expect(match(elizabeth, '345678'), isTrue);
      expect(match(elizabeth, '5678'), isTrue);
      expect(match(william, '4567'), isTrue);
    });

    test('a different number does not match', () {
      expect(match(elizabeth, '01999999999'), isFalse);
      expect(match(elizabeth, '9999'), isFalse);
      expect(match(william, '01712'), isFalse);
    });
  });

  test('characters that mean something to a regular expression are just text', () {
    for (final q in ['(', ')', '[', '\\', '.*', '+', '?', '|', r'$', '^']) {
      expect(() => match(elizabeth, q), returnsNormally, reason: q);
    }
    expect(match(elizabeth, '.*'), isFalse);
  });

  test('known gap SEC-35: a number typed with Bengali digits finds nothing', () {
    // The sign-in code field converts Bengali digits; the recipient search does
    // not, so a Bangla keyboard cannot find 01712345678 by typing ০১৭১২৩৪৫৬৭৮.
    expect(match(elizabeth, '০১৭১২৩৪৫৬৭৮'), isTrue);
  }, skip: 'SEC-35: PhoneSearchHelper does not normalise Bengali digits; unskip when it does');
}
