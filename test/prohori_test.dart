import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:probashi_guard/frontend/menu/app_menu_drawer.dart';
import 'package:probashi_guard/frontend/profile/controllers/profile_controller.dart';
import 'package:probashi_guard/frontend/profile/profile_view.dart';
import 'package:probashi_guard/frontend/prohori/prohori_chat_view.dart';
import 'package:probashi_guard/frontend/prohori/prohori_repository.dart';
import 'package:probashi_guard/l10n/language_controller.dart';
import 'package:probashi_guard/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

http.Response _json(Object body, int status) => http.Response.bytes(
  utf8.encode(jsonEncode(body)),
  status,
  headers: {'content-type': 'application/json'},
);

/// Answers from a script instead of the network.
class _ScriptedRepository extends ProhoriRepository {
  final List<Object> script; // a String reply, or a ProhoriException to throw
  final List<String> asked = [];
  final List<String> languages = [];

  _ScriptedRepository(this.script) : super(baseUrl: 'http://backend.test');

  @override
  Future<String> ask(String message, {required String language}) async {
    asked.add(message);
    languages.add(language);
    final next = script.removeAt(0);
    if (next is ProhoriException) throw next;
    return next as String;
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('ProhoriRepository', () {
    test('posts the question and language, and returns the reply', () async {
      late http.Request captured;
      final repo = ProhoriRepository(
        baseUrl: 'http://backend.test',
        client: MockClient((request) async {
          captured = request;
          return _json({'reply': 'আপনার ভিসা যাচাই করুন'}, 200);
        }),
      );

      final reply = await repo.ask('ভিসা কীভাবে দেখব?', language: 'bn');

      expect(captured.method, 'POST');
      expect(captured.url.toString(), 'http://backend.test/api/chat');
      final body = jsonDecode(captured.body) as Map<String, dynamic>;
      expect(body, {'message': 'ভিসা কীভাবে দেখব?', 'language': 'bn'});
      expect(reply, 'আপনার ভিসা যাচাই করুন');
    });

    test('maps each failure to a problem the screen can word', () async {
      Future<ProhoriProblem> problemFor(MockClient client) async {
        final repo = ProhoriRepository(
          baseUrl: 'http://backend.test',
          client: client,
          timeout: const Duration(milliseconds: 30),
        );
        try {
          await repo.ask('hi', language: 'en');
        } on ProhoriException catch (e) {
          return e.problem;
        }
        fail('expected a ProhoriException');
      }

      expect(
        await problemFor(MockClient((_) async => _json({}, 404))),
        ProhoriProblem.unavailable,
      );
      expect(
        await problemFor(MockClient((_) async => _json({}, 503))),
        ProhoriProblem.unavailable,
      );
      expect(
        await problemFor(MockClient((_) async => _json({}, 401))),
        ProhoriProblem.signIn,
      );
      expect(
        await problemFor(MockClient((_) async => _json({}, 429))),
        ProhoriProblem.busy,
      );
      expect(
        await problemFor(MockClient((_) async => _json({'error': 'x'}, 500))),
        ProhoriProblem.failed,
      );
      expect(
        await problemFor(MockClient((_) async => _json({'reply': ' '}, 200))),
        ProhoriProblem.failed,
        reason: 'an empty answer is a failure, not a blank bubble',
      );
      expect(
        await problemFor(
          MockClient((_) async => throw http.ClientException('refused')),
        ),
        ProhoriProblem.unreachable,
      );
      expect(
        await problemFor(
          MockClient((_) async {
            await Future<void>.delayed(const Duration(seconds: 1));
            return _json({'reply': 'late'}, 200);
          }),
        ),
        ProhoriProblem.timeout,
      );
    });
  });

  group('ProhoriChatView', () {
    Future<void> pumpChat(WidgetTester tester, ProhoriRepository repo) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        ProbashiGuardApp(home: ProhoriChatView(repository: repo)),
      );
      await tester.pump();
    }

    testWidgets('greets, then answers a question', (tester) async {
      final repo = _ScriptedRepository(['Check it on the official portal.']);
      await pumpChat(tester, repo);

      expect(find.text('Prohori'), findsOneWidget);
      expect(find.text('AI Assistant'), findsOneWidget);
      expect(
        find.text('HI THERE !'),
        findsOneWidget,
        reason: 'no name yet: not "Guest", which is a placeholder',
      );
      expect(
        find.text('What do you want to chat about today?'),
        findsOneWidget,
      );

      await tester.enterText(find.byType(TextField), 'Is my visa real?');
      await tester.pump();
      await tester.tap(find.byIcon(Icons.send_rounded));
      await tester.pump();

      expect(find.text('Is my visa real?'), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        isEmpty,
      );

      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Check it on the official portal.'), findsOneWidget);
      expect(repo.asked, ['Is my visa real?']);
      expect(repo.languages, ['en']);
    });

    testWidgets('greets the signed-in person by first name', (tester) async {
      ProfileController.instance.updateProfile(name: 'Josh Miller');
      addTearDown(ProfileController.instance.reset);
      await pumpChat(tester, _ScriptedRepository([]));

      expect(find.text('HI JOSH !'), findsOneWidget);
      expect(find.textContaining('Miller'), findsNothing);
    });

    testWidgets('uses the name given at registration, not a test value', (
      tester,
    ) async {
      ProfileController.instance.updateProfile(name: '  Rahim Uddin ');
      addTearDown(ProfileController.instance.reset);
      await pumpChat(tester, _ScriptedRepository([]));
      expect(find.text('HI RAHIM !'), findsOneWidget);

      // The name arrives after the screen is up (sign-in finishing): it follows.
      ProfileController.instance.updateProfile(name: 'Salma Akter');
      await tester.pump();
      expect(find.text('HI SALMA !'), findsOneWidget);
      expect(find.text('HI RAHIM !'), findsNothing);
    });

    testWidgets('offers the common questions, and tapping one sends it', (
      tester,
    ) async {
      final repo = _ScriptedRepository([
        'The minimum wage depends on the country.',
      ]);
      await pumpChat(tester, repo);

      expect(find.text('Remittance & Fees'), findsOneWidget);
      expect(find.text('Legal & Contracts'), findsOneWidget);
      expect(find.text('Worker Rights'), findsOneWidget);
      expect(
        find.text('How can I send money without hidden fees?'),
        findsOneWidget,
      );
      expect(
        find.text('My employer wants a fingerprint on a blank paper.'),
        findsOneWidget,
      );

      // Something half typed is not lost to a card tap.
      await tester.enterText(find.byType(TextField), 'draft');
      await tester.pump();
      await tester.tap(find.text('What is the legal minimum wage?'));
      await tester.pump(const Duration(milliseconds: 300));

      expect(repo.asked, ['What is the legal minimum wage?']);
      expect(repo.languages, ['en']);
      expect(
        find.text('What is the legal minimum wage?'),
        findsOneWidget,
        reason: 'now the person\'s message, no longer a card',
      );
      expect(
        find.text('The minimum wage depends on the country.'),
        findsOneWidget,
      );
      expect(find.text('Remittance & Fees'), findsNothing);
      expect(find.textContaining('HI '), findsNothing);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'draft',
      );
    });

    testWidgets('suggestions are asked in Bangla in Bangla', (tester) async {
      final repo = _ScriptedRepository(['উত্তর']);
      LanguageController.instance.setLanguageCode('bn');
      addTearDown(() => LanguageController.instance.setLanguageCode('en'));
      await pumpChat(tester, repo);

      expect(find.text('আইনি ন্যূনতম মজুরি কত?'), findsOneWidget);
      await tester.tap(find.text('আইনি ন্যূনতম মজুরি কত?'));
      await tester.pump(const Duration(milliseconds: 300));

      expect(repo.asked, ['আইনি ন্যূনতম মজুরি কত?']);
      expect(repo.languages, ['bn']);
    });

    testWidgets('an empty question cannot be sent', (tester) async {
      final repo = _ScriptedRepository([]);
      await pumpChat(tester, repo);

      await tester.tap(find.byIcon(Icons.send_rounded));
      await tester.pump();
      await tester.enterText(find.byType(TextField), '   ');
      await tester.pump();
      await tester.tap(find.byIcon(Icons.send_rounded));
      await tester.pump();

      expect(repo.asked, isEmpty);
    });

    testWidgets('a failure shows a message and Try again resends', (
      tester,
    ) async {
      final repo = _ScriptedRepository([
        const ProhoriException(ProhoriProblem.unavailable),
        'Here is the answer.',
      ]);
      await pumpChat(tester, repo);

      await tester.enterText(find.byType(TextField), 'Hello');
      await tester.pump();
      await tester.tap(find.byIcon(Icons.send_rounded));
      await tester.pump(const Duration(milliseconds: 300));

      expect(
        find.text('Prohori is not available yet. Please try again later.'),
        findsOneWidget,
      );

      await tester.tap(find.text('Try again'));
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Here is the answer.'), findsOneWidget);
      expect(find.textContaining('not available yet'), findsNothing);
      expect(repo.asked, ['Hello', 'Hello'], reason: 'the same question');
      expect(find.text('Hello'), findsOneWidget, reason: 'not shown twice');
    });

    testWidgets('sending is blocked while an answer is on its way', (
      tester,
    ) async {
      final gate = Completer<String>();
      final repo = _HeldRepository(gate);
      await pumpChat(tester, repo);

      await tester.enterText(find.byType(TextField), 'First');
      await tester.pump();
      await tester.tap(find.byIcon(Icons.send_rounded));
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'Second');
      await tester.pump();
      await tester.tap(find.byIcon(Icons.send_rounded));
      await tester.pump();
      expect(repo.asked, ['First']);

      gate.complete('Done');
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Done'), findsOneWidget);
    });

    testWidgets('speaks Bangla and asks in Bangla when the app does', (
      tester,
    ) async {
      final repo = _ScriptedRepository(['উত্তর']);
      LanguageController.instance.setLanguageCode('bn');
      addTearDown(() => LanguageController.instance.setLanguageCode('en'));
      await pumpChat(tester, repo);

      expect(find.text('প্রহরী'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'প্রশ্ন');
      await tester.pump();
      await tester.tap(find.byIcon(Icons.send_rounded));
      await tester.pump(const Duration(milliseconds: 300));

      expect(repo.languages, ['bn']);
      expect(find.text('উত্তর'), findsOneWidget);
    });
  });

  group('side menu', () {
    testWidgets('Prohori replaces the profile card and opens the chat', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        const ProbashiGuardApp(home: MainNavigationShell()),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.menu_rounded));
      await tester.pumpAndSettle();

      final drawer = find.byType(AppMenuDrawer);
      expect(
        find.descendant(of: drawer, matching: find.text('Prohori')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: drawer, matching: find.text('Profile')),
        findsNothing,
        reason: 'the profile card is gone from the menu',
      );
      expect(
        find.descendant(of: drawer, matching: find.text('+880 1XXX-XXXXXX')),
        findsNothing,
      );

      await tester.tap(
        find.descendant(of: drawer, matching: find.text('Prohori')),
      );
      await tester.pumpAndSettle();

      expect(find.byType(ProhoriChatView), findsOneWidget);
    });

    testWidgets('the profile is still reachable from the top bar', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        const ProbashiGuardApp(home: MainNavigationShell()),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.person_rounded));
      await tester.pumpAndSettle();

      expect(find.byType(ProfileView), findsOneWidget);
    });
  });
}

/// Holds its answer until the test lets go of it.
class _HeldRepository extends ProhoriRepository {
  final Completer<String> gate;
  final List<String> asked = [];

  _HeldRepository(this.gate) : super(baseUrl: 'http://backend.test');

  @override
  Future<String> ask(String message, {required String language}) {
    asked.add(message);
    return gate.future;
  }
}
