import 'package:flutter/material.dart';
import '../../../theme/app_colors.dart';
import '../models/beneficiary_model.dart';
import '../models/currency_model.dart';
import '../models/transaction_model.dart';
import '../models/wallet_card_model.dart';
import '../repository/mock_payment_repository.dart';
import '../repository/payment_repository.dart';

class PaymentController extends ChangeNotifier {
  static final PaymentController instance = PaymentController._internal();
  factory PaymentController() => instance;

  final PaymentRepository _repository;

  PaymentController._internal({PaymentRepository? repository})
      : _repository = repository ?? MockPaymentRepository() {
    _loadInitialSync();
    init();
  }

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  List<WalletCardModel> _cards = [];
  List<WalletCardModel> get cards => _cards;

  List<BeneficiaryModel> _beneficiaries = [];
  List<BeneficiaryModel> get beneficiaries => _beneficiaries;

  List<TransactionModel> _transactions = [];
  List<TransactionModel> get transactions => _transactions;

  int _activeCardIndex = 0;
  int get activeCardIndex => _activeCardIndex;

  WalletCardModel? get activeCard {
    if (_cards.isEmpty) return null;
    return _cards[_activeCardIndex % _cards.length];
  }

  CurrencyModel _selectedCurrency = CurrencyModel.supportedCurrencies[0]; // BDT by default
  CurrencyModel get selectedCurrency => _selectedCurrency;

  bool _isBalanceVisible = true;
  bool get isBalanceVisible => _isBalanceVisible;

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
      ]);

      _cards = results[0] as List<WalletCardModel>;
      _beneficiaries = results[1] as List<BeneficiaryModel>;
      _transactions = results[2] as List<TransactionModel>;
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
    _isBalanceVisible = !_isBalanceVisible;
    notifyListeners();
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

  Future<bool> sendMoney({
    required BeneficiaryModel recipient,
    required double sourceAmount,
    required String sourceCurrency,
    required double destinationAmount,
    required String destinationCurrency,
  }) async {
    final card = activeCard;
    if (card == null) return false;

    try {
      final newTx = await _repository.executeSendMoney(
        sourceCardId: card.id,
        recipientName: recipient.name,
        recipientPhone: recipient.phoneOrAccount,
        sourceAmount: sourceAmount,
        sourceCurrency: sourceCurrency,
        destinationAmount: destinationAmount,
        destinationCurrency: destinationCurrency,
      );

      // Refresh card balances and transactions
      _cards = await _repository.getCards();
      _transactions = [newTx, ..._transactions];
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('Error sending money: $e');
      return false;
    }
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
