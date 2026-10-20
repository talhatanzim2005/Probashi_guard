import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:probashi_guard/frontend/crChecker/controllers/checklist_controller.dart';
import 'package:probashi_guard/frontend/documents/repository/document_analysis_repository.dart';
import 'package:probashi_guard/frontend/home/home_view.dart';
import 'package:probashi_guard/frontend/notice/controllers/notice_controller.dart';
import 'package:probashi_guard/frontend/notice/models/notice_model.dart';
import 'package:probashi_guard/frontend/notice/repository/notice_repository.dart';
import 'package:probashi_guard/frontend/payment/controllers/payment_controller.dart';
import 'package:probashi_guard/frontend/payment/models/beneficiary_model.dart';
import 'package:probashi_guard/frontend/payment/models/transaction_model.dart';
import 'package:probashi_guard/frontend/payment/repository/mock_payment_repository.dart';
import 'package:probashi_guard/frontend/payment/repository/payment_local_store.dart';
import 'package:probashi_guard/frontend/profile/controllers/profile_controller.dart';
import 'package:probashi_guard/frontend/profile/profile_view.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _NoNotices extends NoticeRepository {
  const _NoNotices();

  @override
  Future<List<NoticeModel>> getNotices({int? limit}) async => const [];
}

/// Lets queued fire-and-forget saves finish before the test reads them back.
Future<void> _settle() async {
  for (var i = 0; i < 5; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    PaymentLocalStore.resetForTesting();
  });

  group('Checklist progress is saved', () {
    test('a new install starts at 0 of 8', () {
      final c = ChecklistController.forTesting();
      expect(c.completed, 0);
      expect(c.total, 8);
    });

    test('a tick survives closing and reopening the app', () async {
      final first = ChecklistController.forTesting();
      first.toggle(3);
      first.toggle(0);
      await _settle();

      // A brand new controller stands in for the next launch.
      final reopened = ChecklistController.forTesting();
      await reopened.load();

      expect(reopened.isDone(3), true);
      expect(reopened.isDone(0), true);
      expect(reopened.completed, 2);
    });

    test('corrupt saved data is ignored rather than crashing', () async {
      SharedPreferences.setMockInitialValues({
        'predeparture_checklist_v1': 'not-a-checklist',
      });
      final c = ChecklistController.forTesting();
      await c.load();
      expect(c.completed, 0);
    });

    test('every listener hears a change', () {
      final c = ChecklistController.forTesting();
      var heard = 0;
      c
        ..addListener(() => heard++)
        ..addListener(() => heard++);
      c.toggle(5);
      expect(heard, 2);
    });
  });

  group('Profile banner, Home card and checklist screen stay in sync', () {
    setUp(() async {
      // The singleton is what every screen reads; put it back to a known state.
      final c = ChecklistController.instance;
      for (var i = 0; i < c.total; i++) {
        if (c.isDone(i) != ChecklistController.defaultState[i]) c.toggle(i);
      }
      await _settle();
    });

    testWidgets('tapping the banner opens the checklist', (tester) async {
      ProfileAction? opened;
      await tester.pumpWidget(
        MaterialApp(
          home: ProfileView(
            controller: ProfileController.instance,
            onAction: (a) => opened = a,
          ),
        ),
      );

      final banner = find.text('0 of 8 pre-departure checks completed');
      await tester.ensureVisible(banner);
      await tester.tap(banner);
      await tester.pump();

      expect(opened, ProfileAction.checklist);
    });

    testWidgets(
      'the banner shows the real checklist count, not a placeholder',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: ProfileView(controller: ProfileController.instance),
          ),
        );
        expect(
          find.text('0 of 8 pre-departure checks completed'),
          findsOneWidget,
        );

        ChecklistController.instance.toggle(3);
        ChecklistController.instance.toggle(4);
        await tester.pump();

        expect(
          find.text('2 of 8 pre-departure checks completed'),
          findsOneWidget,
        );
        expect(find.text('2/8'), findsOneWidget);
      },
    );

    testWidgets('a tick on Home shows as 1/8 on Home itself', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final notices = NoticeController.withRepository(const _NoNotices());
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: HomeView(noticeController: notices)),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('0/8 Done'), findsOneWidget);

      // Another screen ticks an item: Home repaints without being touched.
      ChecklistController.instance.toggle(3);
      await tester.pump();
      expect(find.text('1/8 Done'), findsOneWidget);
    });
  });

  group('The banner can send the person to the Home checklist', () {
    testWidgets('asking Home to show the checklist card scrolls to it', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 700);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final notices = NoticeController.withRepository(const _NoNotices());
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: HomeView(noticeController: notices)),
        ),
      );
      await tester.pumpAndSettle();

      final scrollable = tester.state<ScrollableState>(
        find
            .descendant(
              of: find.byType(HomeView),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      // Scroll away from the checklist card first.
      scrollable.position.jumpTo(scrollable.position.maxScrollExtent);
      await tester.pump();
      final scrolledAway = scrollable.position.pixels;
      expect(scrolledAway, greaterThan(0));

      ChecklistController.instance.requestFocus();
      await tester.pumpAndSettle();

      expect(scrollable.position.pixels, lessThan(scrolledAway));
    });
  });

  group('The wallet is saved', () {
    test('a card transfer survives closing and reopening the app', () async {
      final repo = MockPaymentRepository();
      final moved = await repo.executeInterCardTransfer(
        fromCardId: 'card_probashi',
        toCardId: 'card_visa',
        amount: 1000,
      );
      expect(moved, true);
      await _settle();

      // The next launch: forget memory, read the device back, start fresh.
      PaymentLocalStore.resetForTesting();
      await PaymentLocalStore.load();
      final reopened = MockPaymentRepository();

      final cards = await reopened.getCards();
      expect(
        cards.firstWhere((c) => c.id == 'card_probashi').balance,
        25000.00 - 1000,
      );
      expect(
        cards.firstWhere((c) => c.id == 'card_visa').balance,
        10000.00 + 1000,
      );
    });

    test('a transfer writes two rows: one debited, one credited', () async {
      final repo = MockPaymentRepository();
      final before = (await repo.getTransactions()).length;

      await repo.executeInterCardTransfer(
        fromCardId: 'card_probashi',
        toCardId: 'card_visa',
        amount: 250,
      );
      final history = await repo.getTransactions();
      expect(history.length, before + 2);

      final debit = history.firstWhere((t) => t.debitedAmount != null);
      final credit = history.firstWhere((t) => t.creditedAmount != null);

      // The debit leaves the source card and renders with a minus.
      expect(debit.cardId, 'card_probashi');
      expect(debit.amount, 250);
      expect(debit.isIncoming, false);
      expect(debit.type, TransactionType.transfer);

      // The credit lands on the destination card and renders with a plus.
      expect(credit.cardId, 'card_visa');
      expect(credit.amount, 250);
      expect(credit.isIncoming, true);

      // The two halves are linked, and each is one-sided.
      expect(debit.transferGroup, credit.transferGroup);
      expect(debit.transferGroup, isNotNull);
      expect(debit.creditedAmount, isNull);
      expect(credit.debitedAmount, isNull);
    });

    test('a remittance writes a debit in the source currency and a credit in '
        'the destination currency', () async {
      final repo = MockPaymentRepository();
      await repo.completePaymentRecord(
        cardId: 'card_wps',
        beneficiaryName: 'Tanzim',
        beneficiaryPhone: '+8801700000000',
        sourceAmount: 100,
        sourceCurrency: 'SAR',
        exchangeRate: 31.85,
        amountBdt: 3185,
        incentiveBdt: 79.63,
        stripeSessionId: 'cs_test_pair',
      );

      final history = await repo.getTransactions();
      final pair = history
          .where((t) => t.stripeSessionId == 'cs_test_pair')
          .toList();
      expect(pair.length, 2);

      final debit = pair.firstWhere((t) => !t.isIncoming);
      final credit = pair.firstWhere((t) => t.isIncoming);

      expect(debit.amount, 100);
      expect(debit.currency, 'SAR');
      expect(debit.cardId, 'card_wps');

      expect(credit.amount, closeTo(3185 + 79.63, 0.001));
      expect(credit.currency, 'BDT');
    });

    test('both rows of a transfer survive a restart', () async {
      final repo = MockPaymentRepository();
      await repo.executeInterCardTransfer(
        fromCardId: 'card_probashi',
        toCardId: 'card_visa',
        amount: 250,
      );
      await _settle();

      PaymentLocalStore.resetForTesting();
      await PaymentLocalStore.load();
      final history = await MockPaymentRepository().getTransactions();

      final moved = history.where((t) => t.transferGroup != null).toList();
      expect(moved.length, 2);
      expect(
        moved.map((t) => t.cardId),
        containsAll(['card_probashi', 'card_visa']),
      );
      // The seeded history is still there too.
      expect(history.any((t) => t.title == 'Netflix MENA'), true);
    });

    test(
      'a recipient added by the user is still there after a restart',
      () async {
        final controller = PaymentController.withRepository(
          MockPaymentRepository(),
        );
        await controller.init();

        const added = BeneficiaryModel(
          id: 'recipient_test_1',
          name: 'Rahim Uddin',
          phoneOrAccount: '+880 1999-000111',
          providerType: 'bKash',
          avatarUrl: '',
          initials: 'RU',
        );
        controller.addBeneficiary(added);
        await _settle();
        expect(controller.beneficiaries.first.name, 'Rahim Uddin');

        PaymentLocalStore.resetForTesting();
        await PaymentLocalStore.load();
        final reopened = PaymentController.withRepository(
          MockPaymentRepository(),
        );
        await reopened.init();

        expect(reopened.beneficiaries.first.name, 'Rahim Uddin');
        expect(
          reopened.beneficiaries
              .where((b) => b.id == 'recipient_test_1')
              .length,
          1,
        );
      },
    );

    test(
      'adding a recipient no longer throws on an unmodifiable list',
      () async {
        // The mock repository hands back an unmodifiable list; the controller
        // used to insert into it directly.
        final controller = PaymentController.withRepository(
          MockPaymentRepository(),
        );
        await controller.init();

        expect(
          () => controller.addBeneficiary(
            const BeneficiaryModel(
              id: 'r2',
              name: 'Karim',
              phoneOrAccount: '+880 1888-000222',
              providerType: 'Nagad',
              avatarUrl: '',
              initials: 'K',
            ),
          ),
          returnsNormally,
        );
      },
    );

    test('with nothing saved, a new install gets the seeded history', () async {
      final history = await MockPaymentRepository().getTransactions();
      expect(history.length, 5);
    });
  });

  group('The profile is saved', () {
    test('name, phone and biometric come back after a restart', () async {
      ProfileController.instance
        ..updateProfile(name: 'Mohammad Salim', phone: '+966 55 123 4567')
        ..setBiometric(true);
      await _settle();

      // A fresh read of the same keys, as the next launch would do.
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('profile_user_name'), 'Mohammad Salim');
      expect(prefs.getString('profile_phone_number'), '+966 55 123 4567');
      expect(prefs.getBool('profile_biometric_enabled'), true);

      ProfileController.instance
        ..updateProfile(name: 'Guest User', phone: '+880 1XXX-XXXXXX')
        ..setBiometric(false);
      await ProfileController.instance.load();
      expect(ProfileController.instance.userName, 'Guest User');
    });
  });

  group('The document vault works offline', () {
    test(
      'shows the last loaded documents when the vault is unreachable',
      () async {
        SharedPreferences.setMockInitialValues({
          'saved_documents_cache_v1':
              '[{"id":"doc-1","created_at":"2026-10-18T10:00:00.000Z",'
              '"language":"en","document_type":"Employment Contract"}]',
        });

        // No Supabase is initialised in a unit test, so the vault is unreachable.
        final docs = await DocumentAnalysisRepository().fetchSavedDocuments();

        expect(docs.length, 1);
        expect(docs.first.id, 'doc-1');
      },
    );

    test('still reports an error when there is nothing cached', () async {
      expect(
        DocumentAnalysisRepository().fetchSavedDocuments(),
        throwsA(isA<DocumentAnalysisException>()),
      );
    });
  });
}
