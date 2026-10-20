import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:probashi_guard/frontend/payment/models/transaction_model.dart';
import 'package:probashi_guard/frontend/payment/repository/supabase_payment_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// TC-WALLET-REPO: SupabasePaymentRepository against a fake PostgREST.
///
/// A real SupabaseClient is built over an in-memory HTTP client and given a
/// signed-in session, so the repository runs its real query code. Nothing
/// reaches the network, and nothing here touches the live project (unlike
/// verify_payment_run_test.dart, which writes to it).
const _userId = '11111111-1111-4111-8111-111111111111';

String _b64(Map<String, Object?> m) => base64Url.encode(utf8.encode(jsonEncode(m))).replaceAll('=', '');

String _jwt() {
  final exp = DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch ~/ 1000;
  return '${_b64({'alg': 'HS256', 'typ': 'JWT'})}.${_b64({'sub': _userId, 'role': 'authenticated', 'exp': exp})}.sig';
}

class _Server {
  final List<http.Request> seen = [];
  Map<String, Object?> Function(String path, http.Request r)? override;

  /// What the fake database holds.
  List<Map<String, Object?>> wallets = [
    {'card_id': 'card_wps', 'balance': 50000},
    {'card_id': 'card_probashi', 'balance': 32500.5},
    {'card_id': 'card_visa', 'balance': '11000.00'}, // numeric arrives as a string from some drivers
  ];
  List<Map<String, Object?>> transactions = [];
  List<Map<String, Object?>> beneficiaries = [];
  List<Map<String, Object?>> profiles = [];
  int walletsStatus = 200;
  int rpcStatus = 200;
  Map<String, Object?> rpcBody = {'reference': 'r1'};

  Future<http.Response> handle(http.Request r) async {
    seen.add(r);
    // The request must be attached: PostgREST reads it back from the response.
    http.Response json(Object body, [int status = 200]) => http.Response(
      jsonEncode(body),
      status,
      request: r,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );
    final path = r.url.path;
    if (path == '/rest/v1/wallets') return walletsStatus == 200 ? json(wallets) : json({'message': 'down'}, walletsStatus);
    if (path == '/rest/v1/transactions') return json(transactions);
    if (path == '/rest/v1/beneficiaries') return json(beneficiaries);
    if (path == '/rest/v1/profiles') return json(profiles);
    if (path.startsWith('/rest/v1/rpc/')) {
      return rpcStatus == 200
          ? json(rpcBody)
          : json({'code': '22023', 'message': 'That card does not have enough balance'}, rpcStatus);
    }
    return json({'message': 'no route $path'}, 404);
  }

  http.Request? last(String path) => seen.lastWhere((r) => r.url.path == path, orElse: () => http.Request('GET', Uri()));
}

Future<(SupabasePaymentRepository, _Server)> _signedIn({
  bool signedIn = true,
  String? fullName,
}) async {
  final server = _Server();
  final mock = MockClient(server.handle);
  final client = SupabaseClient(
    'http://sb.test',
    'anon-key',
    httpClient: mock,
    authOptions: const AuthClientOptions(autoRefreshToken: false),
  );
  if (signedIn) {
    await client.auth.recoverSession(
      jsonEncode({
        'access_token': _jwt(),
        'token_type': 'bearer',
        'expires_in': 3600,
        'expires_at': DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch ~/ 1000,
        'refresh_token': 'r',
        'user': {
          'id': _userId,
          'aud': 'authenticated',
          'app_metadata': <String, Object?>{},
          'user_metadata': {'full_name': ?fullName},
          'created_at': '2026-10-20T00:00:00Z',
        },
      }),
    );
  }
  return (SupabasePaymentRepository(client: client, httpClient: mock, backendBaseUrl: 'http://backend.test'), server);
}

void main() {
  group('getCards', () {
    test('lays the real balances over the three cards, whatever type the number arrives as', () async {
      final (repo, _) = await _signedIn();
      final cards = {for (final c in await repo.getCards()) c.id: c.balance};
      expect(cards, {'card_wps': 50000.0, 'card_probashi': 32500.5, 'card_visa': 11000.0});
    });

    test('asks only for the two columns it needs, signed with the person\'s token', () async {
      final (repo, server) = await _signedIn();
      await repo.getCards();
      final request = server.last('/rest/v1/wallets')!;
      expect(request.url.queryParameters['select'], 'card_id,balance');
      expect(request.headers['Authorization'], startsWith('Bearer '));
      expect(request.headers['apikey'], 'anon-key');
    });

    test('an account that predates the card wallets has them opened once, then re-read', () async {
      final (repo, server) = await _signedIn();
      server.wallets = [
        {'card_id': 'card_wps', 'balance': 10},
      ];
      await repo.getCards();
      expect(server.seen.where((r) => r.url.path == '/rest/v1/rpc/ensure_my_wallet'), hasLength(1));
      expect(server.seen.where((r) => r.url.path == '/rest/v1/wallets'), hasLength(2));
    });

    test('a brand-new account shows three cards at exactly 0.00', () async {
      final (repo, server) = await _signedIn();
      server.wallets = [
        {'card_id': 'card_wps', 'balance': 0},
        {'card_id': 'card_probashi', 'balance': 0},
        {'card_id': 'card_visa', 'balance': 0},
      ];
      expect((await repo.getCards()).map((c) => c.balance), [0.0, 0.0, 0.0]);
    });

    test('signed out, it reads nothing from the database', () async {
      final (repo, server) = await _signedIn(signedIn: false);
      await repo.getCards();
      expect(server.seen.where((r) => r.url.path == '/rest/v1/wallets'), isEmpty);
    });

    test('SEC-03: when the wallet cannot be read the app must not invent balances', () async {
      final (repo, server) = await _signedIn();
      server.walletsStatus = 500;
      final cards = await repo.getCards();
      // Today this returns the bundled 50,000 / 25,000 / 10,000 BDT.
      expect(cards.map((c) => c.balance), everyElement(0.0));
    }, skip: 'SEC-03: SupabasePaymentRepository falls back to MockPaymentRepository (fake money) on any read error');
  });

  group('getTransactions maps ledger legs to history rows', () {
    Map<String, Object?> leg({
      required String id,
      required String direction,
      required String purpose,
      Object? amount = 100,
      String? counterpartyId,
      String counterpartyName = '',
      String? counterpartyPhone,
      String description = '',
      String card = 'card_wps',
      String status = 'completed',
    }) =>
        {
          'id': id,
          'reference': 'ref-$id',
          'user_id': _userId,
          'direction': direction,
          'purpose': purpose,
          'amount': amount,
          'currency': 'BDT',
          'counterparty_id': counterpartyId,
          'counterparty_name': counterpartyName,
          'counterparty_phone': counterpartyPhone,
          'description': description,
          'card_id': card,
          'status': status,
          'created_at': '2026-10-20T08:00:00Z',
        };

    test('deposit = money received, withdrawal = money sent', () async {
      final (repo, server) = await _signedIn();
      server.transactions = [
        leg(id: 'w', direction: 'debit', purpose: 'withdrawal', counterpartyName: 'Rahim', counterpartyPhone: '+8801900000114', description: 'Sent to Rahim'),
        leg(id: 'd', direction: 'credit', purpose: 'deposit', description: 'Added from your card'),
      ];
      final rows = {for (final t in await repo.getTransactions()) t.id: t};
      expect(rows['w']!.type, TransactionType.send);
      expect(rows['w']!.title, 'Rahim');
      expect(rows['d']!.type, TransactionType.receive);
      expect(rows['d']!.title, 'Added from your card');
    });

    test('a person-to-person transfer reads by direction; a swap between own cards is a "transfer"', () async {
      final (repo, server) = await _signedIn();
      server.transactions = [
        leg(id: 'out', direction: 'debit', purpose: 'transfer', counterpartyId: 'u2', counterpartyName: 'Bob', counterpartyPhone: '+8801900000044'),
        leg(id: 'in', direction: 'credit', purpose: 'transfer', counterpartyId: 'u2', counterpartyName: 'Bob'),
        leg(id: 'swap', direction: 'debit', purpose: 'transfer', description: 'Transfer to card_visa', card: 'card_wps'),
      ];
      final rows = {for (final t in await repo.getTransactions()) t.id: t};
      expect(rows['out']!.type, TransactionType.send);
      expect(rows['in']!.type, TransactionType.receive);
      expect(rows['swap']!.type, TransactionType.transfer);
      expect(rows['swap']!.title, 'Transfer to card_visa');
    });

    test('amount (number or string), status, card and group survive', () async {
      final (repo, server) = await _signedIn();
      server.transactions = [
        leg(id: 'a', direction: 'credit', purpose: 'deposit', amount: '3185.50', card: 'card_visa', status: 'pending'),
        leg(id: 'b', direction: 'credit', purpose: 'deposit', amount: null),
      ];
      final rows = {for (final t in await repo.getTransactions()) t.id: t};
      expect(rows['a']!.amount, 3185.5);
      expect(rows['a']!.status, TransactionStatus.pending);
      expect(rows['a']!.cardId, 'card_visa');
      expect(rows['a']!.transferGroup, 'ref-a');
      expect(rows['b']!.amount, 0.0, reason: 'a missing amount is 0, not a crash');
    });

    test('newest first, capped at 100, and filtered by card on request', () async {
      final (repo, server) = await _signedIn();
      server.transactions = [leg(id: 'x', direction: 'credit', purpose: 'deposit')];
      await repo.getTransactions(cardId: 'card_visa');
      final q = server.last('/rest/v1/transactions')!.url.queryParameters;
      expect(q['order'], startsWith('created_at.desc'));
      expect(q['limit'], '100');
      expect(q['card_id'], 'eq.card_visa');
    });

    test('SEC-03: an account with no history must show an empty list, not invented transactions', () async {
      final (repo, server) = await _signedIn();
      server.transactions = [];
      expect(await repo.getTransactions(), isEmpty);
    }, skip: 'SEC-03: an empty ledger falls through to MockPaymentRepository\'s seeded history (README: "no history")');
  });

  group('getBeneficiaries', () {
    test('maps a saved recipient, resolving the country from its code', () async {
      final (repo, server) = await _signedIn();
      server.beneficiaries = [
        {'id': 'b1', 'name': 'Rahim Uddin', 'phone_number': '+8801900000114', 'provider': 'Nagad', 'country_code': 'SA'},
      ];
      final b = (await repo.getBeneficiaries()).single;
      expect(b.name, 'Rahim Uddin');
      expect(b.phoneOrAccount, '+8801900000114');
      expect(b.providerType, 'Nagad');
      expect(b.initials, 'RU');
      expect(b.currency, 'SAR');
      expect(b.countryDialCode, '+966');
    });

    test('SEC-03: an account with no saved recipients must show none, not Elizabeth and William', () async {
      final (repo, server) = await _signedIn();
      server.beneficiaries = [];
      expect(await repo.getBeneficiaries(), isEmpty);
    }, skip: 'SEC-03: an empty list falls through to the seeded demo recipients');
  });

  group('executeInterCardTransfer', () {
    test('calls internal_transfer with the cards, the amount and a fresh idempotency key', () async {
      final (repo, server) = await _signedIn();
      expect(await repo.executeInterCardTransfer(fromCardId: 'card_wps', toCardId: 'card_visa', amount: 250.5), isTrue);
      final body = jsonDecode(server.last('/rest/v1/rpc/internal_transfer')!.body) as Map<String, Object?>;
      expect(body['p_from_card'], 'card_wps');
      expect(body['p_to_card'], 'card_visa');
      expect(body['p_amount'], 250.5);
      expect(body['p_idempotency_key'], startsWith('swap-'));
    });

    test('each attempt gets its own key, so two real swaps are never merged', () async {
      final (repo, server) = await _signedIn();
      await repo.executeInterCardTransfer(fromCardId: 'card_wps', toCardId: 'card_visa', amount: 1);
      await Future<void>.delayed(const Duration(milliseconds: 2));
      await repo.executeInterCardTransfer(fromCardId: 'card_wps', toCardId: 'card_visa', amount: 1);
      final keys = server.seen
          .where((r) => r.url.path == '/rest/v1/rpc/internal_transfer')
          .map((r) => (jsonDecode(r.body) as Map)['p_idempotency_key'])
          .toList();
      expect(keys.toSet(), hasLength(2));
    });

    test('the database\'s own refusal text is shown as it is', () async {
      final (repo, server) = await _signedIn();
      server.rpcStatus = 400;
      await expectLater(
        repo.executeInterCardTransfer(fromCardId: 'card_visa', toCardId: 'card_wps', amount: 999999),
        throwsA(predicate((e) => e.toString() == 'Exception: That card does not have enough balance')),
      );
    });

    test('signed out, it refuses before sending anything', () async {
      final (repo, server) = await _signedIn(signedIn: false);
      await expectLater(
        repo.executeInterCardTransfer(fromCardId: 'card_wps', toCardId: 'card_visa', amount: 1),
        throwsA(predicate((e) => e.toString().contains('Sign in'))),
      );
      expect(server.seen, isEmpty);
    });
  });

  group('getWalletHolderName', () {
    test('the name given at sign-up wins', () async {
      final (repo, _) = await _signedIn(fullName: 'Nasima Begum');
      expect(await repo.getWalletHolderName(), 'Nasima Begum');
    });

    test('otherwise the name on the profile row', () async {
      final (repo, server) = await _signedIn();
      server.profiles = [
        {'full_name': 'Karim Mia'},
      ];
      expect(await repo.getWalletHolderName(), 'Karim Mia');
    });

    test('with no name anywhere it is the neutral role title', () async {
      final (repo, server) = await _signedIn();
      server.profiles = [
        {'full_name': ''},
      ];
      expect(await repo.getWalletHolderName(), 'Probashi Expatriate Worker');
      final (signedOut, _) = await _signedIn(signedIn: false);
      expect(await signedOut.getWalletHolderName(), 'Probashi Expatriate Worker');
    });

    test('SEC-03: a profile that really is named "Talha Tanzim" is shown like any other name', () async {
      final (repo, server) = await _signedIn();
      server.profiles = [
        {'full_name': 'Talha Tanzim'},
      ];
      expect(await repo.getWalletHolderName(), 'Talha Tanzim');
    }, skip: 'SEC-03: a developer\'s name is hard-coded as "ignore this" in supabase_payment_repository.dart');
  });
}
