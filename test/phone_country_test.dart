import 'package:flutter_test/flutter_test.dart';
import 'package:probashi_guard/frontend/auth/phone_country.dart';

/// TC-PHONE: how a number typed at home becomes the E.164 string Firebase and
/// the server expect. A wrong conversion would send the SMS (or bind the proof)
/// to a different number than the one on the screen.
void main() {
  PhoneCountry country(String iso) =>
      PhoneCountry.all.firstWhere((c) => c.iso == iso);

  group('PhoneCountry.toE164', () {
    // Every case: (country, what the person types, what leaves the screen).
    const accepted = <(String, String, String)>[
      ('BD', '01712345678', '+8801712345678'),
      ('SA', '0501234567', '+966501234567'),
      ('AE', '0501234567', '+971501234567'),
      ('QA', '33123456', '+97433123456'),
      ('KW', '50012345', '+96550012345'),
      ('OM', '92123456', '+96892123456'),
      ('MY', '0123456789', '+60123456789'), // 10 digits
      ('MY', '01123456789', '+601123456789'), // 11 digits
      ('SG', '81234567', '+6581234567'),
    ];
    for (final (iso, typed, e164) in accepted) {
      test('$iso $typed -> $e164', () {
        expect(country(iso).toE164(typed), e164);
      });
    }

    test('the ten Firebase test numbers typed locally map to +8801700000000..09', () {
      final bd = PhoneCountry.bangladesh;
      for (var i = 0; i < 10; i++) {
        expect(bd.toE164('0170000000$i'), '+880170000000$i');
      }
    });

    test('the trunk 0 is dropped exactly once and never doubled', () {
      expect(PhoneCountry.bangladesh.toE164('01712345678'), isNot(contains('8800')));
      expect(country('SA').toE164('0501234567'), startsWith('+9665'));
    });
  });

  group('PhoneCountry.isValidLocal refuses', () {
    const rejected = <(String, String, String)>[
      ('BD', '', 'empty'),
      ('BD', '0171234567', 'one digit short'),
      ('BD', '017123456789', 'one digit long'),
      ('BD', '1712345678', 'trunk zero missing'),
      ('BD', '+8801712345678', 'already international'),
      ('BD', '01712 345678', 'a space'),
      ('BD', '0171234567a', 'a letter'),
      ('BD', '017-1234567', 'a dash'),
      ('SA', '050123456', 'short'),
      ('QA', '3312345', 'short'),
      ('QA', '331234567', 'long'),
      ('SG', '8123456', 'short'),
      ('MY', '012345678', '9 digits'),
      ('MY', '011234567890', '12 digits'),
      ('MY', '1123456789', 'no trunk zero'),
    ];
    for (final (iso, typed, why) in rejected) {
      test('$iso "$typed" ($why)', () {
        expect(country(iso).isValidLocal(typed), isFalse);
        expect(country(iso).toE164(typed), isNull);
      });
    }

    test('Bengali-script digits are not digits to this check (the keypad converts them first)', () {
      expect(PhoneCountry.bangladesh.isValidLocal('০১৭১২৩৪৫৬৭৮'), isFalse);
    });
  });

  group('The country table', () {
    test('Bangladesh is first, because that is where recipients are', () {
      expect(PhoneCountry.all.first.iso, 'BD');
      expect(PhoneCountry.bangladesh.dialCode, '880');
    });

    test('ISO codes and dial codes are unique', () {
      final isos = PhoneCountry.all.map((c) => c.iso).toSet();
      final dials = PhoneCountry.all.map((c) => c.dialCode).toSet();
      expect(isos.length, PhoneCountry.all.length);
      expect(dials.length, PhoneCountry.all.length);
    });

    test('every country\'s own example number is accepted by its own rule', () {
      for (final c in PhoneCountry.all) {
        expect(c.isValidLocal(c.example), isTrue, reason: '${c.iso} ${c.example}');
        expect(c.toE164(c.example), startsWith('+${c.dialCode}'));
      }
    });

    test('every E.164 result is within the 6-15 digit range the database accepts', () {
      // profiles_phone_format: ^\+?[0-9]{6,15}$ — a number that passes here but
      // not there would fail at the very last step.
      final shape = RegExp(r'^\+[0-9]{6,15}$');
      for (final c in PhoneCountry.all) {
        expect(shape.hasMatch(c.toE164(c.example)!), isTrue, reason: c.iso);
      }
    });

    test('lengthLabel reads "11" or "10-11"', () {
      expect(PhoneCountry.bangladesh.lengthLabel, '11');
      expect(country('MY').lengthLabel, '10-11');
    });
  });
}
