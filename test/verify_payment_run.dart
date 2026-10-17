// ignore_for_file: avoid_print

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:probashi_guard/frontend/payment/repository/supabase_payment_repository.dart';

void main() {
  final client = SupabaseClient(
    'https://xfwxiawapksepskcevwe.supabase.co',
    'sb_publishable_j189-L73p34K9QMvj-2Msg_dTYOWhIh',
  );

  setUp(() async {
    // Reset baseline wallet balance
    await client
        .from('wallets')
        .update({'balance_bdt': 98420.12})
        .eq('phone', '+8801700000000');
  });

  test('Combination #1: 100 SAR to BDT (BD Beneficiary + 2.5% Incentive)', () async {
    print('\n================ TEST #1: 100.00 SAR to BDT ================');

    final walletBefore = await client.from('wallets').select().single();
    final double balanceBefore = double.parse(walletBefore['balance_bdt'].toString());
    expect(balanceBefore, 98420.12);

    const double sourceAmount = 100.0;
    const String sourceCurrency = 'SAR';
    const double exchangeRate = 31.85;
    const double amountBdt = sourceAmount * exchangeRate; // 3,185.00 BDT
    const double incentiveBdt = amountBdt * 0.025; // 79.625 BDT (2.5%)

    final repo = SupabasePaymentRepository(client: client);
    final result = await repo.executeSendMoney(
      cardId: 'card_wps',
      beneficiary: {
        'name': 'Fatima Begum',
        'phone': '+8801711223344',
        'country_code': 'BD',
      },
      sourceAmount: sourceAmount,
      sourceCurrency: sourceCurrency,
      exchangeRate: exchangeRate,
      amountBdt: amountBdt,
      incentiveBdt: incentiveBdt,
    );

    expect(result['id'] != null, true);

    final txRecords = await client
        .from('transactions')
        .select()
        .order('created_at', ascending: false)
        .limit(1);

    final tx = txRecords.first;
    print('Transaction ID: ${tx['id']}');
    print('Title: ${tx['title']}');
    print('Currency: ${tx['currency']}');
    print('Converted Amount: ${tx['converted_amount']}');
    print('Exchange Rate: ${tx['exchange_rate']}');
    print('Amount BDT: ${tx['amount_bdt']}');
    print('Incentive BDT: ${tx['incentive_bdt']}');
    print('Stripe Payment ID: ${tx['stripe_payment_id']}');

    expect(tx['currency'], 'SAR');
    expect(double.parse(tx['converted_amount'].toString()), 100.0);
    expect(double.parse(tx['exchange_rate'].toString()), 31.85);
    expect(double.parse(tx['amount_bdt'].toString()), 3185.0);
    expect(double.parse(tx['incentive_bdt'].toString()), closeTo(79.625, 0.01));

    final walletAfter = await client.from('wallets').select().single();
    final double balanceAfter = double.parse(walletAfter['balance_bdt'].toString());
    print('Wallet Balance Before: ৳$balanceBefore');
    print('Wallet Balance After:  ৳$balanceAfter');
    print('Expected Balance:      ৳${balanceBefore - amountBdt}');
    print('============================================================\n');

    expect(balanceAfter, closeTo(balanceBefore - amountBdt, 0.01));
  });

  test('Combination #6: 100 USD to SAR (Non-BD Beneficiary, 0% Incentive)', () async {
    print('\n================ TEST #6: 100.00 USD to SAR ================');

    final walletBefore = await client.from('wallets').select().single();
    final double balanceBefore = double.parse(walletBefore['balance_bdt'].toString());

    const double sourceAmount = 100.0;
    const String sourceCurrency = 'USD';
    const double exchangeRate = 119.50;
    const double amountBdt = sourceAmount * exchangeRate; // 11,950.00 BDT
    const double incentiveBdt = 0.0; // Non-BD recipient

    final repo = SupabasePaymentRepository(client: client);
    final result = await repo.executeSendMoney(
      cardId: 'card_wps',
      beneficiary: {
        'name': 'William',
        'phone': '+966 55 123 4567',
        'country_code': 'SA',
      },
      sourceAmount: sourceAmount,
      sourceCurrency: sourceCurrency,
      exchangeRate: exchangeRate,
      amountBdt: amountBdt,
      incentiveBdt: incentiveBdt,
    );

    expect(result['id'] != null, true);

    final txRecords = await client
        .from('transactions')
        .select()
        .order('created_at', ascending: false)
        .limit(1);

    final tx = txRecords.first;
    print('Transaction ID: ${tx['id']}');
    print('Title: ${tx['title']}');
    print('Currency: ${tx['currency']}');
    print('Converted Amount: ${tx['converted_amount']}');
    print('Exchange Rate: ${tx['exchange_rate']}');
    print('Amount BDT: ${tx['amount_bdt']}');
    print('Incentive BDT: ${tx['incentive_bdt']}');
    print('Stripe Payment ID: ${tx['stripe_payment_id']}');

    expect(tx['currency'], 'USD');
    expect(double.parse(tx['converted_amount'].toString()), 100.0);
    expect(double.parse(tx['exchange_rate'].toString()), 119.50);
    expect(double.parse(tx['amount_bdt'].toString()), 11950.0);
    expect(double.parse(tx['incentive_bdt'].toString()), 0.0);

    final walletAfter = await client.from('wallets').select().single();
    final double balanceAfter = double.parse(walletAfter['balance_bdt'].toString());
    print('Wallet Balance Before: ৳$balanceBefore');
    print('Wallet Balance After:  ৳$balanceAfter');
    print('Expected Balance:      ৳${balanceBefore - amountBdt}');
    print('============================================================\n');

    expect(balanceAfter, closeTo(balanceBefore - amountBdt, 0.01));
  });
}
