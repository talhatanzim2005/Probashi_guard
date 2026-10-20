import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:probashi_guard/frontend/payment/models/beneficiary_model.dart';
import 'package:probashi_guard/frontend/payment/models/country_model.dart';
import 'package:probashi_guard/frontend/payment/models/currency_model.dart';
import 'package:probashi_guard/frontend/payment/models/transaction_model.dart';

/// TC-MODEL: the numbers and records the wallet is built from.
void main() {
  // -------------------------------------------------------------------------
  group('TransactionModel.parseStatus', () {
    test('maps the gateway\'s and the database\'s spellings onto three states', () {
      const pending = ['pending', 'processing', 'unpaid', 'open', 'PENDING', 'Open'];
      const failed = ['failed', 'canceled', 'cancelled', 'expired', 'FAILED'];
      const completed = ['completed', 'paid', 'complete', 'succeeded'];
      for (final s in pending) {
        expect(TransactionModel.parseStatus(s), TransactionStatus.pending, reason: s);
      }
      for (final s in failed) {
        expect(TransactionModel.parseStatus(s), TransactionStatus.failed, reason: s);
      }
      for (final s in completed) {
        expect(TransactionModel.parseStatus(s), TransactionStatus.completed, reason: s);
      }
    });

    test('null and unknown values count as completed (an old row with no status)', () {
      expect(TransactionModel.parseStatus(null), TransactionStatus.completed);
      expect(TransactionModel.parseStatus(''), TransactionStatus.completed);
      expect(TransactionModel.parseStatus('refunded'), TransactionStatus.completed);
    });
  });

  // -------------------------------------------------------------------------
  group('TransactionModel serialisation', () {
    final full = TransactionModel(
      id: 'cs_test_1',
      title: 'Rahim',
      subtitle: 'Awaiting payment',
      amount: 3264.63,
      amountBdt: 3185,
      convertedAmount: 100,
      currency: 'BDT',
      timestamp: DateTime.utc(2026, 10, 20, 9, 30),
      type: TransactionType.send,
      status: TransactionStatus.pending,
      cardId: 'card_wps',
      iconCategory: 'remittance',
      stripeSessionId: 'cs_test_1',
      debitedAmount: 100.01,
      debitedCurrency: 'SAR',
      creditedAmount: 3264.63,
      creditedCurrency: 'BDT',
      transferGroup: 'grp-1',
    );

    test('a row survives toMap -> fromMap with every field', () {
      final back = TransactionModel.fromMap(full.toMap());
      expect(back.id, full.id);
      expect(back.title, full.title);
      expect(back.amount, full.amount);
      expect(back.amountBdt, full.amountBdt);
      expect(back.convertedAmount, full.convertedAmount);
      expect(back.timestamp, full.timestamp);
      expect(back.type, TransactionType.send);
      expect(back.status, TransactionStatus.pending);
      expect(back.cardId, 'card_wps');
      expect(back.stripeSessionId, 'cs_test_1');
      expect(back.debitedAmount, 100.01);
      expect(back.debitedCurrency, 'SAR');
      expect(back.creditedAmount, 3264.63);
      expect(back.transferGroup, 'grp-1');
      expect(back.hasBothLegs, isTrue);
      expect(back.isPending, isTrue);
    });

    test('every type round-trips', () {
      for (final t in TransactionType.values) {
        final back = TransactionModel.fromMap(
          TransactionModel(
            id: 'x',
            title: 't',
            subtitle: 's',
            amount: 1,
            currency: 'BDT',
            timestamp: DateTime.utc(2026),
            type: t,
          ).toMap(),
        );
        expect(back.type, t);
      }
    });

    test('an almost-empty map still builds a row with safe defaults', () {
      final row = TransactionModel.fromMap(const {});
      expect(row.id, '');
      expect(row.amount, 0);
      expect(row.currency, 'BDT');
      expect(row.type, TransactionType.send);
      expect(row.status, TransactionStatus.completed);
      expect(row.isIncoming, isFalse);
    });

    test('a bad timestamp becomes "now", not a crash', () {
      final before = DateTime.now().subtract(const Duration(seconds: 1));
      final row = TransactionModel.fromMap(const {'timestamp': 'not a date'});
      expect(row.timestamp.isAfter(before), isTrue);
    });

    test('older rows without explicit legs fall back to the source and BDT amounts', () {
      final row = TransactionModel.fromMap(const {
        'currency': 'SAR',
        'converted_amount': 100,
        'amount_bdt': 3185,
      });
      expect(row.debitedAmount, 100);
      expect(row.debitedCurrency, 'SAR');
      expect(row.creditedAmount, 3185);
      expect(row.creditedCurrency, 'BDT');
      expect(row.hasBothLegs, isTrue);
    });

    test('copyWith changes only what it is given', () {
      final settled = full.copyWith(status: TransactionStatus.completed, subtitle: 'Done');
      expect(settled.status, TransactionStatus.completed);
      expect(settled.subtitle, 'Done');
      expect(settled.id, full.id);
      expect(settled.amount, full.amount);
      expect(settled.stripeSessionId, full.stripeSessionId);
    });
  });

  group('TransactionModel.transferPair', () {
    final pair = TransactionModel.transferPair(
      groupId: 'g1',
      timestamp: DateTime.utc(2026, 10, 20),
      debitTitle: 'To Rahim',
      debitSubtitle: 'Remittance',
      debitAmount: 100,
      debitCurrency: 'SAR',
      debitCardId: 'card_wps',
      creditTitle: 'From you',
      creditSubtitle: 'Received',
      creditAmount: 3185,
      creditCurrency: 'BDT',
    );

    test('makes a credit and a debit, credit listed first', () {
      expect(pair.length, 2);
      expect(pair[0].type, TransactionType.receive);
      expect(pair[1].type, TransactionType.send);
    });

    test('both legs share the group but have different ids', () {
      expect(pair[0].transferGroup, 'g1');
      expect(pair[1].transferGroup, 'g1');
      expect(pair[0].id, isNot(pair[1].id));
    });

    test('each leg is one-sided: the debit only the debit, the credit only the credit', () {
      expect(pair[1].debitedAmount, 100);
      expect(pair[1].creditedAmount, isNull);
      expect(pair[0].creditedAmount, 3185);
      expect(pair[0].debitedAmount, isNull);
      expect(pair[0].hasBothLegs, isFalse);
    });
  });

  // -------------------------------------------------------------------------
  group('BeneficiaryModel', () {
    test('round-trips', () {
      const b = BeneficiaryModel(
        id: 'b1',
        name: 'Rahim Uddin',
        phoneOrAccount: '+8801900000114',
        providerType: 'Nagad',
        avatarUrl: '',
        initials: 'RU',
        isRecent: false,
        countryCode: 'SA',
        countryFlag: '🇸🇦',
        countryName: 'Saudi Arabia',
        countryDialCode: '+966',
        currency: 'SAR',
        currencySymbol: '﷼',
      );
      final back = BeneficiaryModel.fromMap(b.toMap());
      expect(back.toMap(), b.toMap());
    });

    test('defaults to a Bangladeshi bKash recipient when fields are missing', () {
      final b = BeneficiaryModel.fromMap(const {'name': 'Amina'});
      expect(b.initials, 'A');
      expect(b.providerType, 'bKash');
      expect(b.countryCode, 'BD');
      expect(b.currency, 'BDT');
      expect(b.countryDialCode, '+880');
    });

    test('with no name at all the initial is U', () {
      expect(BeneficiaryModel.fromMap(const {}).initials, 'U');
      expect(BeneficiaryModel.fromMap(const {'name': ''}).initials, 'U');
    });
  });

  // -------------------------------------------------------------------------
  group('CountryModel', () {
    test('lookup by code ignores case and falls back to Bangladesh', () {
      expect(CountryModel.findByCode('sa').name, 'Saudi Arabia');
      expect(CountryModel.findByCode('SA').code, 'SA');
      expect(CountryModel.findByCode('ZZ').code, 'BD');
      expect(CountryModel.findByCode('').code, 'BD');
    });

    test('lookup by dial code falls back to Bangladesh', () {
      expect(CountryModel.findByDialCode('+971').code, 'AE');
      expect(CountryModel.findByDialCode('+000').code, 'BD');
    });

    test('codes are unique, every country has providers, and only Bangladesh has the incentive', () {
      final codes = CountryModel.supportedCountries.map((c) => c.code).toList();
      expect(codes.toSet().length, codes.length);
      for (final c in CountryModel.supportedCountries) {
        expect(c.providers, isNotEmpty, reason: c.code);
        expect(c.rateToBdt, greaterThan(0), reason: c.code);
        expect(c.dialCode, startsWith('+'), reason: c.code);
      }
      final withIncentive = CountryModel.supportedCountries.where((c) => c.hasGovtRemittanceIncentive);
      expect(withIncentive.map((c) => c.code), ['BD']);
    });

    test('Bangladesh is the default and is worth exactly 1 BDT', () {
      expect(CountryModel.defaultCountry.code, 'BD');
      expect(CountryModel.defaultCountry.rateToBdt, 1.0);
    });
  });

  // -------------------------------------------------------------------------
  group('CurrencyModel', () {
    CurrencyModel cur(String code) => CurrencyModel.supportedCurrencies.firstWhere((c) => c.code == code);

    test('BDT is 1, and the others convert in and out without drift', () {
      expect(cur('BDT').rateToBdt, 1.0);
      for (final c in CurrencyModel.supportedCurrencies) {
        expect(c.convertFromBdt(c.convertToBdt(250)), closeTo(250, 1e-9), reason: c.code);
      }
    });

    test('100 SAR is 3,185 BDT; 3,185 BDT is 100 SAR', () {
      expect(cur('SAR').convertToBdt(100), closeTo(3185, 1e-9));
      expect(cur('SAR').convertFromBdt(3185), closeTo(100, 1e-9));
    });

    test('every transfer settles in USD; toUsd and fromUsd are inverses', () {
      expect(CurrencyModel.settlementCurrency, 'USD');
      expect(CurrencyModel.usd.code, 'USD');
      expect(cur('SAR').toUsd(100), closeTo(3185 / 119.5, 1e-9));
      expect(cur('SAR').fromUsd(cur('SAR').toUsd(100)), closeTo(100, 1e-9));
      expect(cur('USD').toUsd(50), 50);
    });

    test('VAT on commission is 0.01% of the amount, in whatever currency it is typed', () {
      expect(CurrencyModel.vatOnCommissionRate, 0.0001);
      expect(CurrencyModel.vatOnCommission(10000), closeTo(1, 1e-12));
      expect(CurrencyModel.vatOnCommission(0), 0);
    });

    test('a zero rate cannot divide by zero', () {
      const broken = CurrencyModel(code: 'XXX', symbol: 'x', name: 'x', flag: '', rateToBdt: 0);
      expect(broken.convertFromBdt(100), 0);
    });

    test('the currency table and the country table agree on every shared rate', () {
      for (final c in CurrencyModel.supportedCurrencies) {
        final country = CountryModel.supportedCountries.where((k) => k.currencyCode == c.code);
        for (final k in country) {
          expect(k.rateToBdt, c.rateToBdt, reason: '${c.code} / ${k.code}');
        }
      }
    });
  });

  // -------------------------------------------------------------------------
  group('the app and the server price a transfer with the same constants', () {
    // flutter test runs from the project root. If either side changes a rate
    // or the VAT rate alone, the charge and the credit stop agreeing.
    final pricing = File('backend_service/src/pricing.ts').readAsStringSync();
    final checkout = File('backend_service/src/routes/checkout.ts').readAsStringSync();

    double constant(String source, String name) {
      final m = RegExp('$name\\s*=\\s*([0-9.]+)').firstMatch(source);
      expect(m, isNotNull, reason: '$name not found');
      return double.parse(m!.group(1)!);
    }

    test('USD_TO_BDT and VAT_ON_COMMISSION_RATE', () {
      expect(constant(pricing, 'USD_TO_BDT'), CurrencyModel.usd.rateToBdt);
      expect(constant(pricing, 'VAT_ON_COMMISSION_RATE'), CurrencyModel.vatOnCommissionRate);
    });

    test('the baseline rates /api/rates serves match the bundled currency table', () {
      for (final c in CurrencyModel.supportedCurrencies) {
        final m = RegExp('\\b${c.code}:\\s*([0-9.]+)').firstMatch(checkout);
        expect(m, isNotNull, reason: '${c.code} missing from baselineRates');
        expect(double.parse(m!.group(1)!), c.rateToBdt, reason: c.code);
      }
    });

    test('the three card ids match', () {
      for (final id in ['card_wps', 'card_probashi', 'card_visa']) {
        expect(pricing, contains("'$id'"), reason: id);
      }
    });
  });
}
