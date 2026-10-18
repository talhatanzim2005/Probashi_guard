import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../theme/app_colors.dart';
import '../models/beneficiary_model.dart';
import '../models/currency_model.dart';
import '../models/transaction_model.dart';
import '../models/wallet_card_model.dart';
import '../repository/payment_repository.dart';
import '../repository/supabase_payment_repository.dart';

class PaymentController extends ChangeNotifier with WidgetsBindingObserver {
  static final PaymentController instance = PaymentController._internal();
  factory PaymentController() => instance;

  final PaymentRepository _repository;

  PaymentController._internal({PaymentRepository? repository})
      : _repository = repository ?? SupabasePaymentRepository() {
    // Lets us hide the balance when the app leaves the foreground.
    WidgetsFlutterBinding.ensureInitialized().addObserver(this);
    _loadInitialSync();
    init();
  }

  /// For tests and for pointing the wallet at a different backend.
  @visibleForTesting
  PaymentController.withRepository(PaymentRepository repository)
      : _repository = repository {
    _loadInitialSync();
  }

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  List<WalletCardModel> _cards = [];
  List<WalletCardModel> get cards => _cards;

  List<BeneficiaryModel> _beneficiaries = [];
  List<BeneficiaryModel> get beneficiaries => _beneficiaries;

  List<TransactionModel> _transactions = [];
  List<TransactionModel> get transactions => _transactions;

  String _walletHolderName = 'Probashi Expatriate Worker';
  String get walletHolderName => _walletHolderName;

  int _activeCardIndex = 0;
  int get activeCardIndex => _activeCardIndex;

  WalletCardModel? get activeCard {
    if (_cards.isEmpty) return null;
    return _cards[_activeCardIndex % _cards.length];
  }

  CurrencyModel _selectedCurrency = CurrencyModel.supportedCurrencies[0]; // BDT by default
  CurrencyModel get selectedCurrency => _selectedCurrency;

  /// How long a revealed balance stays on screen before hiding itself again.
  static const Duration balanceAutoHideAfter = Duration(seconds: 30);

  /// Hidden by default: the balance is only shown after the person taps to
  /// reveal it (top bar and card share this one state).
  bool _isBalanceVisible = false;
  bool get isBalanceVisible => _isBalanceVisible;

  Timer? _balanceAutoHideTimer;

  void _loadInitialSync() {
    _cards = [
      const WalletCardModel(
        id: 'card_wps',
        title: 'WPS Payroll Card',
        providerName: 'Wage Protection System (Al Rajhi)',
        cardNumberMasked: '•••• 8420',
        balance: 98420.12,
        currency: 'BDT',
        expiryDate: '08/29',
        cardType: CardType.wpsPayroll,
        primaryColor: Color(0xFF111625),
        accentColor: AppColors.emeraldGreen,
      ),
      const WalletCardModel(
        id: 'card_probashi',
        title: 'Probashi Expatriate Account',
        providerName: 'Probashi Kallyan Bank',
        cardNumberMasked: '•••• 1947',
        balance: 145000.00,
        currency: 'BDT',
        expiryDate: '12/28',
        cardType: CardType.probashiMultiCurrency,
        primaryColor: AppColors.royalBlue,
        accentColor: AppColors.cloudDancer,
      ),
      const WalletCardModel(
        id: 'card_bkash',
        title: 'bKash Remittance Direct',
        providerName: 'bKash Bangladesh',
        cardNumberMasked: '•••• 5521',
        balance: 24850.50,
        currency: 'BDT',
        expiryDate: '03/30',
        cardType: CardType.bkashDirect,
        primaryColor: Color(0xFFC4164C),
        accentColor: AppColors.cloudDancer,
      ),
    ];
  }

  // Initialize data
  Future<void> init() async {
    _isLoading = true;
    notifyListeners();

    try {
      final results = await Future.wait([
        _repository.getCards(),
        _repository.getBeneficiaries(),
        _repository.getTransactions(),
        _repository.getWalletHolderName(),
      ]);

      _cards = results[0] as List<WalletCardModel>;
      _beneficiaries = results[1] as List<BeneficiaryModel>;
      _transactions = results[2] as List<TransactionModel>;
      _walletHolderName = results[3] as String;
    } catch (e) {
      debugPrint('Error loading payment data: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void addBeneficiary(BeneficiaryModel beneficiary) {
    _beneficiaries.insert(0, beneficiary);
    notifyListeners();
  }

  void setActiveCardIndex(int index) {
    if (_cards.isEmpty) return;
    _activeCardIndex = index % _cards.length;
    notifyListeners();
  }

  void cycleCardToFront() {
    if (_cards.length <= 1) return;
    _activeCardIndex = (_activeCardIndex + 1) % _cards.length;
    notifyListeners();
  }

  void setSelectedCurrency(CurrencyModel currency) {
    _selectedCurrency = currency;
    notifyListeners();
  }

  void toggleBalanceVisibility() {
    if (_isBalanceVisible) {
      hideBalance();
    } else {
      showBalance();
    }
  }

  /// Reveals the balance, then hides it again after [balanceAutoHideAfter].
  void showBalance() {
    if (_isBalanceVisible) return;
    _isBalanceVisible = true;
    HapticFeedback.selectionClick();
    _balanceAutoHideTimer?.cancel();
    _balanceAutoHideTimer = Timer(balanceAutoHideAfter, hideBalance);
    notifyListeners();
  }

  void hideBalance() {
    _balanceAutoHideTimer?.cancel();
    _balanceAutoHideTimer = null;
    if (!_isBalanceVisible) return;
    _isBalanceVisible = false;
    notifyListeners();
  }

  /// Hide the balance whenever the app is not in the foreground (home button,
  /// app switcher, lock screen, notification shade), so it never appears in
  /// the recent-apps preview.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) hideBalance();
  }

  @override
  void dispose() {
    _balanceAutoHideTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Calculates and formats the balance for the active card converted to the chosen currency.
  String get formattedActiveBalance {
    if (!_isBalanceVisible) {
      return '••••••••';
    }
    return unmaskedActiveBalance;
  }

  /// Always returns the formatted active balance without masking (useful for headers/app bars)
  String get unmaskedActiveBalance {
    final card = activeCard;
    if (card == null) return '${_selectedCurrency.symbol} 0.00';

    final converted = _selectedCurrency.convertFromBdt(card.balance);
    return '${_selectedCurrency.symbol} ${_formatNumber(converted)}';
  }

  /// Aggregated balance across all cards converted to active currency.
  String get formattedTotalBalance {
    if (!_isBalanceVisible) {
      return '••••••••';
    }
    return unmaskedTotalBalance;
  }

  /// Always returns the aggregated total balance without masking
  String get unmaskedTotalBalance {
    double totalBdt = 0;
    for (final card in _cards) {
      totalBdt += card.balance;
    }
    final converted = _selectedCurrency.convertFromBdt(totalBdt);
    return '${_selectedCurrency.symbol} ${_formatNumber(converted)}';
  }

  String formatAmountInActiveCurrency(double bdtAmount) {
    final converted = _selectedCurrency.convertFromBdt(bdtAmount);
    return '${_selectedCurrency.symbol}${_formatNumber(converted)}';
  }

  String _formatNumber(double amount) {
    final parts = amount.toStringAsFixed(2).split('.');
    final integerPart = parts[0];
    final decimalPart = parts[1];

    final reg = RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))');
    final formattedInt = integerPart.replaceAllMapped(reg, (Match m) => '${m[1]},');
    return '$formattedInt.$decimalPart';
  }

  // ---------------------------------------------------------------------------
  // Remittance. Stripe Checkout is a hosted page, so sending money is a
  // three-phase sequence rather than a single call. See [PaymentRepository].
  // ---------------------------------------------------------------------------

  /// Phase 1 — opens a Checkout session and returns its payload, which carries
  /// the `checkoutUrl` the caller opens in the browser.
  ///
  /// A pending row goes into [transactions] straight away, so the transfer is
  /// visible while the person is still on Stripe's page. Throws a
  /// `Payment Gateway Error` when no session could be created; nothing has been
  /// charged in that case.
  Future<Map<String, dynamic>?> sendMoneyWithResult({
    required BeneficiaryModel recipient,
    required double sourceAmount,
    required String sourceCurrency,
    required double exchangeRate,
    required double amountBdt,
    required double incentiveBdt,
    String? connectedAccountId,
    String? pendingSubtitle,
  }) async {
    final card = activeCard;
    if (card == null) {
      throw Exception('Payment Gateway Error: No source card is selected.');
    }

    final session = await _repository.executeSendMoney(
      cardId: card.id,
      beneficiary: recipient,
      sourceAmount: sourceAmount,
      sourceCurrency: sourceCurrency,
      exchangeRate: exchangeRate,
      amountBdt: amountBdt,
      incentiveBdt: incentiveBdt,
      connectedAccountId: connectedAccountId,
    );

    final sessionId = session['sessionId']?.toString() ?? '';
    if (sessionId.isNotEmpty) {
      _transactions = [
        TransactionModel(
          id: sessionId,
          title: recipient.name,
          subtitle: pendingSubtitle ??
              'Awaiting payment • ${recipient.providerType}',
          amount: amountBdt + incentiveBdt,
          amountBdt: amountBdt,
          convertedAmount: sourceAmount,
          currency: 'BDT',
          timestamp: DateTime.now(),
          type: TransactionType.send,
          status: TransactionStatus.pending,
          cardId: card.id,
          iconCategory: 'remittance',
          stripeSessionId: sessionId,
        ),
        ..._transactions,
      ];
      notifyListeners();
    }

    return session;
  }

  /// Phase 2 — whether the hosted Checkout page was actually paid.
  Future<bool> verifyCheckoutSession(String sessionId) {
    return _repository.verifyCheckoutSession(sessionId);
  }

  /// Phase 3 — records the settled remittance, then reloads balances and
  /// history so Transaction History shows the completed transfer.
  Future<void> completeRemittance({
    required BeneficiaryModel recipient,
    required String cardId,
    required double sourceAmount,
    required String sourceCurrency,
    required double exchangeRate,
    required double amountBdt,
    required double incentiveBdt,
    required String sessionId,
    String? settledSubtitle,
  }) async {
    try {
      await _repository.completePaymentRecord(
        cardId: cardId,
        beneficiaryName: recipient.name,
        beneficiaryPhone: recipient.phoneOrAccount,
        sourceAmount: sourceAmount,
        sourceCurrency: sourceCurrency,
        exchangeRate: exchangeRate,
        amountBdt: amountBdt,
        incentiveBdt: incentiveBdt,
        stripeSessionId: sessionId,
      );
    } catch (e) {
      debugPrint('Error recording completed remittance: $e');
    }

    // Settle the pending row locally first, so history is right even when the
    // backing store is unreachable and the reload below returns nothing new.
    _transactions = _transactions
        .map(
          (tx) => tx.stripeSessionId == sessionId
              ? tx.copyWith(
                  status: TransactionStatus.completed,
                  subtitle: settledSubtitle ??
                      'Remittance to ${recipient.phoneOrAccount}',
                  iconCategory: 'person',
                )
              : tx,
        )
        .toList();
    notifyListeners();

    await refreshWallet(keepSessionId: sessionId);
  }

  /// Reloads cards and history from the repository. [keepSessionId] keeps a
  /// locally settled row visible if the store has not caught up with it yet.
  Future<void> refreshWallet({String? keepSessionId}) async {
    TransactionModel? localRow;
    if (keepSessionId != null) {
      for (final tx in _transactions) {
        if (tx.stripeSessionId == keepSessionId) {
          localRow = tx;
          break;
        }
      }
    }

    try {
      final results = await Future.wait([
        _repository.getCards(),
        _repository.getTransactions(),
      ]);

      _cards = results[0] as List<WalletCardModel>;
      final reloaded = results[1] as List<TransactionModel>;

      final row = localRow;
      final storeHasIt = row == null ||
          reloaded.any(
            (tx) => tx.stripeSessionId == keepSessionId || tx.id == row.id,
          );

      _transactions = storeHasIt ? reloaded : [row, ...reloaded];
      notifyListeners();
    } catch (e) {
      debugPrint('Error refreshing wallet: $e');
    }
  }

  /// Drops the pending row for an abandoned or failed Checkout session, so
  /// history never shows a transfer nobody paid for.
  void discardPendingTransaction(String sessionId) {
    if (sessionId.isEmpty) return;
    final before = _transactions.length;
    _transactions = _transactions
        .where((tx) =>
            tx.stripeSessionId != sessionId ||
            tx.status != TransactionStatus.pending)
        .toList();
    if (_transactions.length != before) notifyListeners();
  }

  Future<bool> interCardSwap({
    required String fromCardId,
    required String toCardId,
    required double amountInBdt,
  }) async {
    try {
      final success = await _repository.executeInterCardTransfer(
        fromCardId: fromCardId,
        toCardId: toCardId,
        amount: amountInBdt,
      );

      if (success) {
        _cards = await _repository.getCards();
        _transactions = await _repository.getTransactions();
        notifyListeners();
      }
      return success;
    } catch (e) {
      debugPrint('Error in card swap: $e');
      return false;
    }
  }
}
