// ignore_for_file: avoid_print

import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:probashi_guard/frontend/payment/repository/supabase_payment_repository.dart';

void main() {
  test('Execute and verify live payment: 100 USD to SAR', () async {
    final client = SupabaseClient(
      'https://xfwxiawapksepskcevwe.supabase.co',
      'sb_publishable_j189-L73p34K9QMvj-2Msg_dTYOWhIh',
    );

    // 1. Reset baseline wallet balance to 98420.12
    await client
        .from('wallets')
        .update({'balance_bdt': 98420.12})
        .eq('phone', '+8801700000000');

    final walletBefore = await client.from('wallets').select().single();
    final double balanceBefore = double.parse(walletBefore['balance_bdt'].toString());
    expect(balanceBefore, 98420.12);

    // 2. Exact user parameters: 100 USD to SAR (William)
    const double sourceAmount = 100.0;
    const String sourceCurrency = 'USD';
    const double exchangeRate = 119.50; // USD to BDT
    const double amountBdt = sourceAmount * exchangeRate; // 11,950.00 BDT
    const double incentiveBdt = 0.0; // Non-BD recipient

    // 3. Execute send money via repository with mock HTTP client for Stripe checkout session.
    // A fresh session id per run, since a session is only ever recorded once.
    final mockSessionId = 'cs_test_mock_william_${DateTime.now().millisecondsSinceEpoch}';
    final mockClient = MockClient((request) async {
      return http.Response(
        jsonEncode({
          'success': true,
          'checkoutUrl': 'https://checkout.stripe.com/c/pay/$mockSessionId',
          'sessionId': mockSessionId,
        }),
        201,
      );
    });

    final repo = SupabasePaymentRepository(
      client: client,
      httpClient: mockClient,
    );
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

    expect(result['checkoutUrl'], 'https://checkout.stripe.com/c/pay/$mockSessionId');
    expect(result['sessionId'], mockSessionId);

    // Simulate verified return from Stripe -> complete the payment record.
    // Recording the same session twice (app watcher + webhook) must not
    // duplicate history or deduct the wallet twice.
    for (var i = 0; i < 2; i++) {
      await repo.completePaymentRecord(
        cardId: 'card_wps',
        beneficiaryName: 'William',
        beneficiaryPhone: '+966 55 123 4567',
        sourceAmount: sourceAmount,
        sourceCurrency: sourceCurrency,
        exchangeRate: exchangeRate,
        amountBdt: amountBdt,
        incentiveBdt: incentiveBdt,
        stripeSessionId: mockSessionId,
      );
    }

    // 4. Query Supabase transactions table for the inserted record
    final txRecords = await client
        .from('transactions')
        .select()
        .order('created_at', ascending: false)
        .limit(1);

    final sessionRows = await client
        .from('transactions')
        .select('id')
        .eq('stripe_payment_id', mockSessionId);
    expect(sessionRows.length, 1);

    final latestTx = txRecords.first;
    print('\n================ VERIFICATION OUTPUT ================');
    print('Transaction ID: ${latestTx['id']}');
    print('Title: ${latestTx['title']}');
    print('Currency: ${latestTx['currency']}');
    print('Converted Amount (raw input): ${latestTx['converted_amount']}');
    print('Exchange Rate: ${latestTx['exchange_rate']}');
    print('Amount BDT: ${latestTx['amount_bdt']}');
    print('Incentive BDT: ${latestTx['incentive_bdt']}');
    print('Stripe Payment ID: ${latestTx['stripe_payment_id']}');

    expect(latestTx['currency'], 'USD');
    expect(double.parse(latestTx['converted_amount'].toString()), 100.0);
    expect(double.parse(latestTx['exchange_rate'].toString()), 119.50);
    expect(double.parse(latestTx['amount_bdt'].toString()), 11950.0);
    expect(double.parse(latestTx['incentive_bdt'].toString()), 0.0);

    // 5. Query Supabase wallets table for updated balance
    final walletAfter = await client.from('wallets').select().single();
    final double balanceAfter = double.parse(walletAfter['balance_bdt'].toString());
    print('Wallet Balance Before: ৳$balanceBefore');
    print('Wallet Balance After: ৳$balanceAfter');
    print('Expected Balance: ৳${balanceBefore - amountBdt}');
    print('====================================================\n');

    expect(balanceAfter, balanceBefore - amountBdt);
  });
}
