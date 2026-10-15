import '../models/beneficiary_model.dart';
import '../models/transaction_model.dart';
import '../models/wallet_card_model.dart';

abstract class PaymentRepository {
  Future<List<WalletCardModel>> getCards();
  Future<List<BeneficiaryModel>> getBeneficiaries();
  Future<List<TransactionModel>> getTransactions({String? cardId});
  Future<TransactionModel> executeSendMoney({
    required String sourceCardId,
    required String recipientName,
    required String recipientPhone,
    required double sourceAmount,
    required String sourceCurrency,
    required double destinationAmount,
    required String destinationCurrency,
  });
  Future<bool> executeInterCardTransfer({
    required String fromCardId,
    required String toCardId,
    required double amount,
  });
}
