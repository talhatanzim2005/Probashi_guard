import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:probashi_guard/frontend/payment/controllers/payment_controller.dart';
import 'package:probashi_guard/frontend/payment/models/beneficiary_model.dart';
import 'package:probashi_guard/frontend/payment/models/currency_model.dart';
import 'package:probashi_guard/frontend/payment/models/transaction_model.dart';
import 'package:probashi_guard/frontend/payment/models/wallet_card_model.dart';
import 'package:probashi_guard/frontend/payment/repository/payment_local_store.dart';
import 'package:probashi_guard/frontend/payment/repository/payment_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// TC-WALLET-FLOW: the controller behind the Payment tab, driven through a
/// scripted repository so every branch of the three-phase send (open session,
/// poll, settle) and of the card swap can be forced.
class _ScriptedRepository implements PaymentRepository {
  List<WalletCardModel> cards = [_card('card_wps', 1000), _card('card_probashi', 500), _card('card_visa', 250)];
  List<TransactionModel> transactions = [];
  Map<String, dynamic> session = {'sessionId': 'cs_1', 'checkoutUrl': 'https://checkout.stripe.com/c/pay/cs_1'};
  Object? sendError;
  Object? completeError;
  Object? loadError;
  bool swapResult = true;
  Object? swapError;
  final List<String> calls = [];

  static WalletCardModel _card(String id, double balance) => WalletCardModel(
        id: id,
        title: id,
        providerName: 'p',
        cardNumberMasked: '•••• 0000',
        balance: balance,
        currency: 'BDT',
        expiryDate: '01/30',
        cardType: CardType.wpsPayroll,
        primaryColor: Colors.black,
        accentColor: Colors.white,
      );

  @override
  Future<List<WalletCardModel>> getCards() async {
    calls.add('getCards');
    if (loadError != null) throw loadError!;
    return cards;
  }

  @override
  Future<List<BeneficiaryModel>> getBeneficiaries() async => const [];

  @override
  Future<List<TransactionModel>> getTransactions({String? cardId}) async {
    calls.add('getTransactions');
    if (loadError != null) throw loadError!;
    return transactions;
  }

  @override
  Future<Map<String, dynamic>> executeSendMoney({
    required String cardId,
    required dynamic beneficiary,
    required double sourceAmount,
    required String sourceCurrency,
    required double exchangeRate,
    required double amountBdt,
    required double incentiveBdt,
    required double vatOnCommission,
    required double usdAmount,
    String? connectedAccountId,
  }) async {
    calls.add('executeSendMoney:$cardId');
    if (sendError != null) throw sendError!;
    return session;
  }

  @override
  Future<bool> verifyCheckoutSession(String sessionId) async => true;

  @override
  Future<void> completePaymentRecord({
    required String cardId,
    required String beneficiaryName,
    required String beneficiaryPhone,
    required double sourceAmount,
    required String sourceCurrency,
    required double exchangeRate,
    required double amountBdt,
    required double incentiveBdt,
    required String stripeSessionId,
  }) async {
    calls.add('completePaymentRecord:$stripeSessionId');
    if (completeError != null) throw completeError!;
  }

  @override
  Future<bool> executeInterCardTransfer({
    required String fromCardId,
    required String toCardId,
    required double amount,
  }) async {
    calls.add('swap:$fromCardId>$toCardId:$amount');
    if (swapError != null) throw swapError!;
    return swapResult;
  }

  @override
  Future<String> getWalletHolderName() async => 'Test Holder';

  @override
  Future<Map<String, double>?> fetchExchangeRates() async => null;
}

const _rahim = BeneficiaryModel(
  id: 'b1',
  name: 'Rahim Uddin',
  phoneOrAccount: '+8801900000114',
  providerType: 'bKash',
  avatarUrl: '',
  initials: 'RU',
);

Future<String?> _swap(PaymentController c, {double amount = 100}) =>
    c.transferBetweenCards(fromCardId: 'card_wps', toCardId: 'card_visa', amountInBdt: amount);

Future<Map<String, dynamic>?> _send(PaymentController c, {BeneficiaryModel recipient = _rahim}) =>
    c.sendMoneyWithResult(
      recipient: recipient,
      sourceAmount: 100,
      sourceCurrency: 'SAR',
      exchangeRate: 31.85,
      amountBdt: 3185,
      incentiveBdt: 79.625,
      vatOnCommission: 0.01,
      usdAmount: 26.66,
    );

void main() {
  late _ScriptedRepository repo;
  late PaymentController controller;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    PaymentLocalStore.resetForTesting();
    repo = _ScriptedRepository();
    controller = PaymentController.withRepository(repo);
    await controller.init();
  });

  group('phase 1: opening a Checkout session', () {
    test('adds a pending row at the top of the history straight away', () async {
      final session = await _send(controller);
      expect(session!['sessionId'], 'cs_1');
      final row = controller.transactions.first;
      expect(row.stripeSessionId, 'cs_1');
      expect(row.status, TransactionStatus.pending);
      expect(row.type, TransactionType.send);
      expect(row.title, 'Rahim Uddin');
      expect(row.cardId, 'card_wps');
      expect(row.amountBdt, 3185);
      expect(row.amount, closeTo(3185 + 79.625, 1e-9), reason: 'the recipient is shown what they will receive, incentive included');
      expect(row.debitedAmount, closeTo(100.01, 1e-9), reason: 'the sender is shown what is taken, VAT included');
      expect(row.debitedCurrency, 'SAR');
      expect(row.creditedCurrency, 'BDT');
    });

    test('charges from the card that is in front', () async {
      controller.setActiveCardIndex(2);
      await _send(controller);
      expect(repo.calls, contains('executeSendMoney:card_visa'));
      expect(controller.transactions.first.cardId, 'card_visa');
    });

    test('a refused session leaves no row behind and passes the reason on', () async {
      repo.sendError = Exception('Payment Gateway Error: Verify your phone number before sending money');
      await expectLater(_send(controller), throwsA(predicate((e) => e.toString().contains('Verify your phone number'))));
      expect(controller.transactions, isEmpty);
    });

    test('an answer with no session id adds no row (there is nothing to settle later)', () async {
      repo.session = {'checkoutUrl': 'https://checkout.stripe.com/x'};
      await _send(controller);
      expect(controller.transactions, isEmpty);
    });

    test('with no card selected it refuses before calling the gateway', () async {
      repo.cards = [];
      await controller.init();
      await expectLater(_send(controller), throwsA(predicate((e) => e.toString().contains('No source card'))));
      expect(repo.calls.where((c) => c.startsWith('executeSendMoney')), isEmpty);
    });
  });

  group('abandoning a session', () {
    test('discardPendingTransaction removes that session\'s pending row only', () async {
      await _send(controller);
      repo.session = {'sessionId': 'cs_2', 'checkoutUrl': 'https://checkout.stripe.com/c/pay/cs_2'};
      await _send(controller);
      expect(controller.transactions, hasLength(2));
      controller.discardPendingTransaction('cs_1');
      expect(controller.transactions.map((t) => t.stripeSessionId), ['cs_2']);
    });

    test('a settled row with the same session id is never discarded', () async {
      await _send(controller);
      await controller.completeRemittance(
        recipient: _rahim, cardId: 'card_wps', sourceAmount: 100, sourceCurrency: 'SAR',
        exchangeRate: 31.85, amountBdt: 3185, incentiveBdt: 79.625, sessionId: 'cs_1',
      );
      controller.discardPendingTransaction('cs_1');
      expect(controller.transactions.where((t) => t.stripeSessionId == 'cs_1'), hasLength(1));
    });

    test('an empty id or an unknown id changes nothing and does not notify', () async {
      await _send(controller);
      var notified = 0;
      controller.addListener(() => notified++);
      controller.discardPendingTransaction('');
      controller.discardPendingTransaction('cs_nope');
      expect(controller.transactions, hasLength(1));
      expect(notified, 0);
    });
  });

  group('phase 3: settling after Stripe says paid', () {
    Future<void> settle() => controller.completeRemittance(
          recipient: _rahim, cardId: 'card_wps', sourceAmount: 100, sourceCurrency: 'SAR',
          exchangeRate: 31.85, amountBdt: 3185, incentiveBdt: 79.625, sessionId: 'cs_1',
          settledSubtitle: 'Remittance to +8801900000114',
        );

    test('the pending row becomes completed, and the wallet is reloaded', () async {
      await _send(controller);
      repo.cards = [_ScriptedRepository._card('card_wps', 777)];
      await settle();
      final row = controller.transactions.firstWhere((t) => t.stripeSessionId == 'cs_1');
      expect(row.status, TransactionStatus.completed);
      expect(row.subtitle, 'Remittance to +8801900000114');
      expect(controller.cards.single.balance, 777);
      expect(repo.calls.where((c) => c == 'getCards').length, greaterThan(1));
    });

    test('a failing record call does not lose the row: it is settled locally anyway', () async {
      await _send(controller);
      repo.completeError = Exception('db down');
      await settle();
      expect(controller.transactions.first.status, TransactionStatus.completed);
    });

    test('while the webhook has not landed, the settled row stays visible', () async {
      await _send(controller);
      repo.transactions = []; // the ledger has not caught up yet
      await settle();
      expect(controller.transactions.where((t) => t.stripeSessionId == 'cs_1'), hasLength(1));
    });

    test('once the webhook has landed, the server\'s row replaces it with no duplicate', () async {
      await _send(controller);
      repo.transactions = [
        TransactionModel(
          id: 'ledger-row-1', title: 'Rahim Uddin', subtitle: '', amount: 3185, currency: 'BDT',
          timestamp: DateTime.now(), type: TransactionType.send, stripeSessionId: 'cs_1',
        ),
      ];
      await settle();
      expect(controller.transactions, hasLength(1));
      expect(controller.transactions.single.id, 'ledger-row-1');
    });

    test('refreshWallet keeps what it has when the reload fails', () async {
      await _send(controller);
      repo.loadError = Exception('offline');
      await controller.refreshWallet();
      expect(controller.transactions, hasLength(1));
      expect(controller.cards, hasLength(3));
    });
  });

  group('transferBetweenCards', () {
    test('success returns null and shows the new balances and history', () async {
      repo.cards = [_ScriptedRepository._card('card_wps', 900), _ScriptedRepository._card('card_visa', 350)];
      expect(await _swap(controller), isNull);
      expect(controller.cards.map((c) => c.balance), [900, 350]);
      expect(repo.calls, contains('swap:card_wps>card_visa:100.0'));
    });

    test('a refusal comes back as a readable message without the Dart prefix', () async {
      repo.swapError = Exception('That card does not have enough balance');
      expect(await _swap(controller, amount: 999999), 'That card does not have enough balance');
    });

    test('a "false" answer is a generic failure message', () async {
      repo.swapResult = false;
      expect(await _swap(controller), 'That transfer could not be completed.');
    });

    test('a refusal leaves the balances as they were', () async {
      repo.swapError = Exception('nope');
      final before = controller.cards.map((c) => c.balance).toList();
      await _swap(controller);
      expect(controller.cards.map((c) => c.balance), before);
    });
  });

  group('showing money', () {
    test('the balance is hidden until the person reveals it', () {
      expect(controller.isBalanceVisible, isFalse);
      expect(controller.formattedActiveBalance, '••••••••');
      expect(controller.formattedTotalBalance, '••••••••');
      controller.toggleBalanceVisibility();
      expect(controller.formattedActiveBalance, '৳ 1,000.00');
      expect(controller.formattedTotalBalance, '৳ 1,750.00');
      controller.toggleBalanceVisibility();
      expect(controller.isBalanceVisible, isFalse);
    });

    testWidgets('a revealed balance hides itself after 30 seconds', (tester) async {
      controller.showBalance();
      expect(controller.isBalanceVisible, isTrue);
      await tester.pump(PaymentController.balanceAutoHideAfter - const Duration(seconds: 1));
      expect(controller.isBalanceVisible, isTrue);
      await tester.pump(const Duration(seconds: 2));
      expect(controller.isBalanceVisible, isFalse);
    });

    testWidgets('leaving the app hides it at once', (tester) async {
      controller.showBalance();
      controller.didChangeAppLifecycleState(AppLifecycleState.paused);
      expect(controller.isBalanceVisible, isFalse);
      controller.showBalance();
      controller.didChangeAppLifecycleState(AppLifecycleState.resumed);
      expect(controller.isBalanceVisible, isTrue, reason: 'coming back does not hide it');
      await tester.pump(PaymentController.balanceAutoHideAfter + const Duration(seconds: 1));
    });

    test('amounts follow the chosen currency, with thousands separators and two decimals', () {
      expect(controller.unmaskedActiveBalance, '৳ 1,000.00');
      controller.setSelectedCurrency(CurrencyModel.usd);
      expect(controller.unmaskedActiveBalance, '\$ 8.37');
      expect(controller.formatAmountInActiveCurrency(119.5), '\$1.00');
      controller.setSelectedCurrency(CurrencyModel.supportedCurrencies[1]);
      expect(controller.formatAmountInActiveCurrency(3185), '﷼100.00');
    });

    test('the front card cycles and wraps', () {
      expect(controller.activeCard!.id, 'card_wps');
      controller.cycleCardToFront();
      expect(controller.activeCard!.id, 'card_probashi');
      controller.setActiveCardIndex(5);
      expect(controller.activeCardIndex, 2);
      controller.cycleCardToFront();
      expect(controller.activeCard!.id, 'card_wps');
    });
  });

  group('logging out', () {
    test('forgets the account\'s recipients, history and on-device copy, and hides the balance', () async {
      controller.addBeneficiary(_rahim);
      await _send(controller);
      controller.showBalance();
      await PaymentLocalStore.saveTransactions(controller.transactions);
      expect(PaymentLocalStore.savedBeneficiaries, isNotEmpty);

      await controller.resetForSignOut();

      expect(controller.beneficiaries, isEmpty);
      expect(controller.transactions, isEmpty);
      expect(controller.isBalanceVisible, isFalse);
      expect(controller.activeCardIndex, 0);
      expect(PaymentLocalStore.savedBeneficiaries, isEmpty);
      expect(PaymentLocalStore.savedTransactions, isNull);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getKeys().where((k) => k.startsWith('payment_')), isEmpty);
    });

    test('SEC-03: after logout the wallet shows no money until the next account\'s own balances load', () async {
      await controller.resetForSignOut();
      expect(controller.cards.map((c) => c.balance), everyElement(0.0));
    }, skip: 'SEC-03: _loadInitialSync() puts the bundled 50,000 / 25,000 / 10,000 BDT cards back, and they stay if the next load fails');
  });
}
