import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:probashi_guard/frontend/payment/models/beneficiary_model.dart';
import 'package:probashi_guard/frontend/payment/repository/supabase_payment_repository.dart';

/// TC-SEND-CONTRACT: what the app sends to POST /api/checkout/send-money and
/// GET /api/checkout/session-status/:id, and how it reads the answers.
///
/// The backend half of the same contract is tested in
/// backend_service/src/test/payments.integration.test.ts.
void main() {
  const rahim = BeneficiaryModel(
    id: 'b1',
    name: 'Rahim Uddin',
    phoneOrAccount: '+8801900000114',
    providerType: 'bKash',
    avatarUrl: '',
    initials: 'RU',
  );

  late List<http.Request> sent;

  SupabasePaymentRepository repoAnswering(
    http.Response Function(http.Request) answer, {
    bool network = false,
  }) {
    sent = [];
    return SupabasePaymentRepository(
      backendBaseUrl: 'http://backend.test',
      httpClient: MockClient((request) async {
        sent.add(request);
        if (network) throw http.ClientException('connection refused');
        return answer(request);
      }),
    );
  }

  Future<Map<String, dynamic>> send(
    SupabasePaymentRepository repo, {
    dynamic beneficiary = rahim,
    String? connectedAccountId,
  }) =>
      repo.executeSendMoney(
        cardId: 'card_wps',
        beneficiary: beneficiary,
        sourceAmount: 100,
        sourceCurrency: 'SAR',
        exchangeRate: 31.85,
        amountBdt: 3185,
        incentiveBdt: 79.625,
        vatOnCommission: 0.01,
        usdAmount: 26.66,
        connectedAccountId: connectedAccountId,
      );

  http.Response created({String url = 'https://checkout.stripe.com/c/pay/cs_test_abc', Map<String, Object?> extra = const {}}) =>
      http.Response(jsonEncode({'success': true, 'checkoutUrl': url, 'sessionId': 'cs_test_abc', ...extra}), 201);

  group('executeSendMoney: the request', () {
    test('is a JSON POST to /api/checkout/send-money', () async {
      final repo = repoAnswering((_) => created());
      await send(repo);
      expect(sent.single.method, 'POST');
      expect(sent.single.url.toString(), 'http://backend.test/api/checkout/send-money');
      expect(sent.single.headers['Content-Type'], contains('application/json'));
    });

    test('carries who, how much and from which card', () async {
      final repo = repoAnswering((_) => created());
      await send(repo);
      final body = jsonDecode(sent.single.body) as Map<String, dynamic>;
      expect(body['cardId'], 'card_wps');
      expect(body['sourceCardId'], 'card_wps');
      expect(body['recipientName'], 'Rahim Uddin');
      expect(body['recipientPhone'], '+8801900000114');
      expect(body['sourceAmount'], 100);
      expect(body['sourceCurrency'], 'SAR');
      expect(body['exchangeRate'], 31.85);
      expect(body['amountBdt'], 3185);
      expect(body['incentiveBdt'], 79.625);
      expect(body['destinationAmount'], closeTo(3185 + 79.625, 1e-9));
      expect(body['destinationCurrency'], 'BDT');
    });

    test('sends no user id: the server learns who is paying from the token alone', () async {
      final repo = repoAnswering((_) => created());
      await send(repo);
      final body = jsonDecode(sent.single.body) as Map<String, dynamic>;
      for (final key in ['userId', 'user_id', 'payerUserId', 'payer_id']) {
        expect(body.containsKey(key), isFalse, reason: key);
      }
    });

    test('signed out, no Authorization header is sent (so the server will refuse)', () async {
      final repo = repoAnswering((_) => created());
      await send(repo);
      expect(sent.single.headers.containsKey('Authorization'), isFalse);
    });

    test('a recipient may be a plain map; the phone is read from phone / phone_number / phoneOrAccount', () async {
      for (final key in ['phone', 'phone_number', 'phoneOrAccount']) {
        final repo = repoAnswering((_) => created());
        await send(repo, beneficiary: {'name': 'Amina', key: '+8801900000044'});
        expect((jsonDecode(sent.single.body) as Map)['recipientPhone'], '+8801900000044', reason: key);
      }
    });

    test('SEC-33 (pinned): an explicit connected account is passed through; none given uses the hard-coded test account', () async {
      var repo = repoAnswering((_) => created());
      await send(repo, connectedAccountId: 'acct_real');
      expect((jsonDecode(sent.single.body) as Map)['connectedAccountId'], 'acct_real');

      repo = repoAnswering((_) => created());
      await send(repo);
      expect((jsonDecode(sent.single.body) as Map)['connectedAccountId'], startsWith('acct_'));
    });

    test('SEC-33: a recipient with no phone must not be silently sent to +8801700000000', () async {
      final repo = repoAnswering((_) => created());
      await send(repo, beneficiary: {'name': 'Amina'});
      expect((jsonDecode(sent.single.body) as Map)['recipientPhone'], isNot('+8801700000000'));
    }, skip: 'SEC-33: the fallback +8801700000000 (the first Firebase test number) is hard-coded here, in checkout.ts and in webhooks.ts');
  });

  group('executeSendMoney: the answer', () {
    test('a session comes back as pending with its checkout URL and id', () async {
      final session = await send(repoAnswering((_) => created()));
      expect(session['checkoutUrl'], 'https://checkout.stripe.com/c/pay/cs_test_abc');
      expect(session['sessionId'], 'cs_test_abc');
      expect(session['status'], 'pending');
      expect(session['card_id'], 'card_wps');
    });

    test('200 and 201 are both accepted', () async {
      final repo = repoAnswering(
        (_) => http.Response(jsonEncode({'checkoutUrl': 'https://checkout.stripe.com/x', 'sessionId': 'cs_1'}), 200),
      );
      expect((await send(repo))['sessionId'], 'cs_1');
    });

    test('the URL may come from the nested transaction, and the id from its fields in order', () async {
      final repo = repoAnswering(
        (_) => http.Response(
          jsonEncode({
            'transaction': {'checkout_url': 'https://checkout.stripe.com/n', 'stripe_payment_id': 'cs_pay', 'id': 'cs_tx'},
          }),
          201,
        ),
      );
      final session = await send(repo);
      expect(session['checkoutUrl'], 'https://checkout.stripe.com/n');
      expect(session['sessionId'], 'cs_pay');
    });

    test('a URL that is not http(s) is refused, so a hostile or broken answer cannot open anything else', () async {
      for (final url in ['', '   ', 'javascript:alert(1)', 'ftp://x/y', 'checkout.stripe.com/c/pay/x', 'file:///etc/passwd', 'intent://x#Intent;end']) {
        final repo = repoAnswering((_) => created(url: url));
        await expectLater(
          send(repo),
          throwsA(predicate((e) => e.toString().contains('Malformed or missing Checkout URL'))),
          reason: '"$url"',
        );
      }
    });

    test('a missing URL is refused', () async {
      final repo = repoAnswering((_) => http.Response(jsonEncode({'success': true}), 201));
      await expectLater(send(repo), throwsA(predicate((e) => e.toString().contains('Payment Gateway Error'))));
    });

    test('the server\'s own reason is shown after "Payment Gateway Error:"', () async {
      final repo = repoAnswering(
        (_) => http.Response(jsonEncode({'error': 'Verify your phone number before sending money', 'code': 'phone_not_verified'}), 403),
      );
      await expectLater(
        send(repo),
        throwsA(predicate((e) => e.toString() == 'Exception: Payment Gateway Error: Verify your phone number before sending money')),
      );
    });

    test('a failure with no JSON body still carries the status code', () async {
      final repo = repoAnswering((_) => http.Response('<html>Bad gateway</html>', 502));
      await expectLater(send(repo), throwsA(predicate((e) => e.toString().contains('(502)'))));
    });

    test('a 200 that is not JSON is an invalid response, never a paid transfer', () async {
      final repo = repoAnswering((_) => http.Response('OK', 200));
      await expectLater(send(repo), throwsA(predicate((e) => e.toString().contains('Invalid response'))));
    });

    test('an unreachable backend says so, and nothing looks sent', () async {
      final repo = repoAnswering((_) => created(), network: true);
      await expectLater(send(repo), throwsA(predicate((e) => e.toString().contains('Unable to connect to payment server'))));
    });

    test('SEC-33 (pinned): with no session id in the answer the app invents one', () async {
      final repo = repoAnswering(
        (_) => http.Response(jsonEncode({'checkoutUrl': 'https://checkout.stripe.com/x'}), 201),
      );
      final session = await send(repo);
      // An invented id can never be found by session-status, so a payment that
      // really was made would be reported "not completed".
      expect(session['sessionId'], startsWith('cs_'));
    });
  });

  group('verifyCheckoutSession', () {
    Future<bool> verify(http.Response Function(http.Request) answer, {bool network = false}) =>
        repoAnswering(answer, network: network).verifyCheckoutSession('cs_test_abc');

    test('asks GET /api/checkout/session-status/<id>', () async {
      await verify((_) => http.Response(jsonEncode({'is_paid': true}), 200));
      expect(sent.single.method, 'GET');
      expect(sent.single.url.toString(), 'http://backend.test/api/checkout/session-status/cs_test_abc');
    });

    test('true when the server says paid, in any of its three spellings', () async {
      for (final body in [
        {'is_paid': true},
        {'payment_status': 'paid'},
        {'status': 'complete'},
      ]) {
        expect(await verify((_) => http.Response(jsonEncode(body), 200)), isTrue, reason: '$body');
      }
    });

    test('false while it is still open or unpaid', () async {
      for (final body in [
        {'is_paid': false, 'status': 'open', 'payment_status': 'unpaid'},
        <String, Object?>{},
        {'status': 'expired'},
      ]) {
        expect(await verify((_) => http.Response(jsonEncode(body), 200)), isFalse, reason: '$body');
      }
    });

    test('false on any error, never "paid by default"', () async {
      expect(await verify((_) => http.Response('{}', 404)), isFalse);
      expect(await verify((_) => http.Response('{}', 401)), isFalse);
      expect(await verify((_) => http.Response('{}', 500)), isFalse);
      expect(await verify((_) => http.Response('not json', 200)), isFalse);
      expect(await verify((_) => http.Response('[]', 200)), isFalse);
      expect(await verify((_) => http.Response('{}', 200), network: true), isFalse);
    });

    test('SEC-34: "complete" with payment_status "unpaid" (a delayed payment method) is not paid', () async {
      expect(await verify((_) => http.Response(jsonEncode({'status': 'complete', 'payment_status': 'unpaid'}), 200)), isFalse);
    }, skip: 'SEC-34: the app and the server both treat status "complete" as paid; the webhook only books payment_status "paid"');
  });
}
