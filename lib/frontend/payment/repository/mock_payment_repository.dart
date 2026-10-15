import 'dart:async';
import 'package:flutter/material.dart';
import '../../../theme/app_colors.dart';
import '../models/beneficiary_model.dart';
import '../models/transaction_model.dart';
import '../models/wallet_card_model.dart';
import 'payment_repository.dart';

class MockPaymentRepository implements PaymentRepository {
  final List<WalletCardModel> _cards = [
    const WalletCardModel(
      id: 'card_wps',
      title: 'WPS Payroll Card',
      providerName: 'Wage Protection System (Al Rajhi)',
      cardNumberMasked: '•••• 8420',
      balance: 98420.12, // in base BDT representation
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

  final List<BeneficiaryModel> _beneficiaries = [
    const BeneficiaryModel(
      id: 'ben_1',
      name: 'Elizabeth',
      phoneOrAccount: '+880 1712-345678',
      providerType: 'bKash',
      avatarUrl: '',
      initials: 'EL',
      isRecent: true,
      countryCode: 'BD',
      countryFlag: '🇧🇩',
      countryName: 'Bangladesh',
      countryDialCode: '+880',
      currency: 'BDT',
      currencySymbol: '৳',
    ),
    const BeneficiaryModel(
      id: 'ben_2',
      name: 'William',
      phoneOrAccount: '+966 55 123 4567',
      providerType: 'STC Pay',
      avatarUrl: '',
      initials: 'WI',
      isRecent: true,
      countryCode: 'SA',
      countryFlag: '🇸🇦',
      countryName: 'Saudi Arabia',
      countryDialCode: '+966',
      currency: 'SAR',
      currencySymbol: '﷼',
    ),
    const BeneficiaryModel(
      id: 'ben_3',
      name: 'Adam',
      phoneOrAccount: '+971 50 987 6543',
      providerType: 'Careem Pay',
      avatarUrl: '',
      initials: 'AD',
      isRecent: true,
      countryCode: 'AE',
      countryFlag: '🇦🇪',
      countryName: 'United Arab Emirates',
      countryDialCode: '+971',
      currency: 'AED',
      currencySymbol: 'د.إ',
    ),
    const BeneficiaryModel(
      id: 'ben_4',
      name: 'Tony',
      phoneOrAccount: '+974 33 112 233',
      providerType: 'Ooredoo Money',
      avatarUrl: '',
      initials: 'TO',
      isRecent: true,
      countryCode: 'QA',
      countryFlag: '🇶🇦',
      countryName: 'Qatar',
      countryDialCode: '+974',
      currency: 'QAR',
      currencySymbol: 'ر.ق',
    ),
    const BeneficiaryModel(
      id: 'ben_5',
      name: 'Emma',
      phoneOrAccount: '+60 12-345 6789',
      providerType: 'Touch n Go',
      avatarUrl: '',
      initials: 'EM',
      isRecent: true,
      countryCode: 'MY',
      countryFlag: '🇲🇾',
      countryName: 'Malaysia',
      countryDialCode: '+60',
      currency: 'MYR',
      currencySymbol: 'RM',
    ),
    const BeneficiaryModel(
      id: 'ben_6',
      name: 'Sarah',
      phoneOrAccount: '+1 (415) 555-0199',
      providerType: 'Zelle',
      avatarUrl: '',
      initials: 'SA',
      isRecent: true,
      countryCode: 'US',
      countryFlag: '🇺🇸',
      countryName: 'United States',
      countryDialCode: '+1',
      currency: 'USD',
      currencySymbol: '\$',
    ),
    const BeneficiaryModel(
      id: 'ben_7',
      name: 'Tariq Rahman',
      phoneOrAccount: '+880 1819-876543',
      providerType: 'Nagad',
      avatarUrl: '',
      initials: 'TR',
      isRecent: false,
      countryCode: 'BD',
      countryFlag: '🇧🇩',
      countryName: 'Bangladesh',
      countryDialCode: '+880',
      currency: 'BDT',
      currencySymbol: '৳',
    ),
    const BeneficiaryModel(
      id: 'ben_8',
      name: 'Khalid Al-Mansoor',
      phoneOrAccount: '+966 50 765 4321',
      providerType: 'Al Rajhi Bank',
      avatarUrl: '',
      initials: 'KM',
      isRecent: false,
      countryCode: 'SA',
      countryFlag: '🇸🇦',
      countryName: 'Saudi Arabia',
      countryDialCode: '+966',
      currency: 'SAR',
      currencySymbol: '﷼',
    ),
  ];

  List<TransactionModel> _transactions = [
    TransactionModel(
      id: 'tx_1',
      title: 'Google',
      subtitle: 'Subscription',
      amount: 60.00,
      currency: 'USD',
      timestamp: DateTime.now().subtract(const Duration(minutes: 42)),
      type: TransactionType.subscription,
      cardId: 'card_wps',
      iconCategory: 'google',
    ),
    TransactionModel(
      id: 'tx_2',
      title: 'Elizabeth',
      subtitle: 'Received Money',
      amount: 420.00,
      currency: 'USD',
      timestamp: DateTime.now().subtract(const Duration(hours: 3, minutes: 12)),
      type: TransactionType.receive,
      cardId: 'card_wps',
      iconCategory: 'person',
    ),
    TransactionModel(
      id: 'tx_3',
      title: 'WPS Wage Credit',
      subtitle: 'Monthly Employer Salary',
      amount: 3250.00,
      currency: 'SAR',
      timestamp: DateTime.now().subtract(const Duration(days: 2)),
      type: TransactionType.receive,
      cardId: 'card_wps',
      iconCategory: 'salary',
    ),
    TransactionModel(
      id: 'tx_4',
      title: 'Family Remittance',
      subtitle: 'bKash Bangladesh Transfer',
      amount: 35000.00,
      currency: 'BDT',
      timestamp: DateTime.now().subtract(const Duration(days: 4)),
      type: TransactionType.send,
      cardId: 'card_bkash',
      iconCategory: 'remittance',
    ),
    TransactionModel(
      id: 'tx_5',
      title: 'Netflix MENA',
      subtitle: 'Entertainment Stream',
      amount: 15.00,
      currency: 'USD',
      timestamp: DateTime.now().subtract(const Duration(days: 6)),
      type: TransactionType.subscription,
      cardId: 'card_wps',
      iconCategory: 'netflix',
    ),
  ];

  @override
  Future<List<WalletCardModel>> getCards() async {
    await Future.delayed(const Duration(milliseconds: 150));
    return List.unmodifiable(_cards);
  }

  @override
  Future<List<BeneficiaryModel>> getBeneficiaries() async {
    await Future.delayed(const Duration(milliseconds: 120));
    return List.unmodifiable(_beneficiaries);
  }

  @override
  Future<List<TransactionModel>> getTransactions({String? cardId}) async {
    await Future.delayed(const Duration(milliseconds: 180));
    if (cardId == null) {
      return List.unmodifiable(_transactions);
    }
    return _transactions.where((tx) => tx.cardId == cardId).toList();
  }

  @override
  Future<TransactionModel> executeSendMoney({
    required String sourceCardId,
    required String recipientName,
    required String recipientPhone,
    required double sourceAmount,
    required String sourceCurrency,
    required double destinationAmount,
    required String destinationCurrency,
  }) async {
    await Future.delayed(const Duration(milliseconds: 300));

    // Deduct from card balance in BDT baseline
    final cardIndex = _cards.indexWhere((c) => c.id == sourceCardId);
    if (cardIndex != -1) {
      final currentCard = _cards[cardIndex];
      final newBalance = (currentCard.balance - destinationAmount).clamp(0.0, double.infinity);
      _cards[cardIndex] = currentCard.copyWith(balance: newBalance);
    }

    final newTx = TransactionModel(
      id: 'tx_${DateTime.now().millisecondsSinceEpoch}',
      title: recipientName,
      subtitle: 'Remittance to $recipientPhone',
      amount: destinationAmount,
      currency: destinationCurrency,
      timestamp: DateTime.now(),
      type: TransactionType.send,
      cardId: sourceCardId,
      iconCategory: 'person',
    );

    _transactions = [newTx, ..._transactions];
    return newTx;
  }

  @override
  Future<bool> executeInterCardTransfer({
    required String fromCardId,
    required String toCardId,
    required double amount,
  }) async {
    await Future.delayed(const Duration(milliseconds: 250));

    final fromIndex = _cards.indexWhere((c) => c.id == fromCardId);
    final toIndex = _cards.indexWhere((c) => c.id == toCardId);

    if (fromIndex == -1 || toIndex == -1) return false;
    if (_cards[fromIndex].balance < amount) return false;

    _cards[fromIndex] = _cards[fromIndex].copyWith(
      balance: _cards[fromIndex].balance - amount,
    );
    _cards[toIndex] = _cards[toIndex].copyWith(
      balance: _cards[toIndex].balance + amount,
    );

    final transferTx = TransactionModel(
      id: 'tx_${DateTime.now().millisecondsSinceEpoch}',
      title: 'Inter-Card Swap',
      subtitle: '${_cards[fromIndex].title} → ${_cards[toIndex].title}',
      amount: amount,
      currency: 'BDT',
      timestamp: DateTime.now(),
      type: TransactionType.transfer,
      cardId: fromCardId,
      iconCategory: 'transfer',
    );

    _transactions = [transferTx, ..._transactions];
    return true;
  }
}
