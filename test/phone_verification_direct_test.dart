import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:probashi_guard/frontend/auth/firebase_phone_verifier.dart';
import 'package:probashi_guard/frontend/auth/phone_country.dart';
import 'package:probashi_guard/frontend/auth/phone_verifier.dart';

void main() {
  group('PhoneCountry', () {
    test('a Bangladeshi number is exactly 11 digits starting with 0', () {
      final bd = PhoneCountry.bangladesh;
      expect(bd.toE164('01700000000'), '+8801700000000');
      expect(bd.toE164('01343555114'), '+8801343555114');
      expect(bd.toE164('0170000000'), isNull, reason: '10 digits');
      expect(bd.toE164('017000000000'), isNull, reason: '12 digits');
      expect(bd.toE164('11700000000'), isNull, reason: 'no trunk 0');
    });

    test('countries without a trunk 0 keep every digit', () {
      final qatar = PhoneCountry.all.firstWhere((c) => c.iso == 'QA');
      expect(qatar.toE164('33123456'), '+97433123456');
      expect(qatar.lengthLabel, '8');
    });

    test('Malaysia accepts both 10- and 11-digit mobiles', () {
      final my = PhoneCountry.all.firstWhere((c) => c.iso == 'MY');
      expect(my.toE164('0123456789'), '+60123456789');
      expect(my.toE164('01123456789'), '+601123456789');
      expect(my.lengthLabel, '10-11');
    });
  });

  group('FirebasePhoneVerifier direct route (test numbers)', () {
    /// Answers like Firebase Auth's REST API and records what it was sent.
    MockClient firebase(
      List<http.Request> seen, {
      Map<String, Object> send = const {'sessionInfo': 'session-1'},
      int sendStatus = 200,
      Map<String, Object> confirm = const {'idToken': 'token-1'},
      int confirmStatus = 200,
    }) {
      return MockClient((request) async {
        seen.add(request);
        if (request.url.path.endsWith(':sendVerificationCode')) {
          return http.Response(jsonEncode(send), sendStatus);
        }
        return http.Response(jsonEncode(confirm), confirmStatus);
      });
    }

    FirebasePhoneVerifier verifier(MockClient client) => FirebasePhoneVerifier(
          httpClient: client,
          directForTestNumbers: true,
          apiKey: 'test-key',
        );

    test('sends the number in E.164 with the API key', () async {
      final seen = <http.Request>[];
      await verifier(firebase(seen)).sendCode('+8801700000000');

      expect(seen, hasLength(1));
      expect(seen.single.url.queryParameters['key'], 'test-key');
      final body = jsonDecode(seen.single.body) as Map<String, dynamic>;
      expect(body['phoneNumber'], '+8801700000000');
    });

    test('a wrong code is reported as wrongCode and nothing is bound',
        () async {
      final seen = <http.Request>[];
      final v = verifier(firebase(
        seen,
        confirm: {
          'error': {'message': 'INVALID_CODE'},
        },
        confirmStatus: 400,
      ));

      await v.sendCode('+8801700000000');
      await expectLater(
        v.confirmCode('000000'),
        throwsA(isA<PhoneVerificationException>().having(
          (e) => e.reason,
          'reason',
          PhoneVerificationFailure.wrongCode,
        )),
      );

      // Send, then the failed check. No call to the backend's bind-phone.
      expect(seen.map((r) => r.url.path.split(':').last).toList(),
          ['sendVerificationCode', 'signInWithPhoneNumber']);
      final confirmBody = jsonDecode(seen.last.body) as Map<String, dynamic>;
      expect(confirmBody, {'sessionInfo': 'session-1', 'code': '000000'});
    });

    test('a real number without billing is smsUnavailable, not notConfigured',
        () async {
      final v = verifier(firebase(
        [],
        send: {
          'error': {'message': 'BILLING_NOT_ENABLED'},
        },
        sendStatus: 400,
      ));

      await expectLater(
        v.sendCode('+8801911223344'),
        throwsA(isA<PhoneVerificationException>().having(
          (e) => e.reason,
          'reason',
          PhoneVerificationFailure.smsUnavailable,
        )),
      );
    });

    test('a region block is smsUnavailable too', () async {
      final v = verifier(firebase(
        [],
        send: {
          'error': {
            'message': 'OPERATION_NOT_ALLOWED : SMS unable to be sent until '
                'this region enabled by the app developer.',
          },
        },
        sendStatus: 400,
      ));

      await expectLater(
        v.sendCode('+8801700000000'),
        throwsA(isA<PhoneVerificationException>().having(
          (e) => e.reason,
          'reason',
          PhoneVerificationFailure.smsUnavailable,
        )),
      );
    });
  });
}
