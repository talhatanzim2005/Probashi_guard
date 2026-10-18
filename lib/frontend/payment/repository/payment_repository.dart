import '../models/beneficiary_model.dart';
import '../models/transaction_model.dart';
import '../models/wallet_card_model.dart';

/// The contract every payment backend implements.
///
/// A remittance is a two-phase operation, because the money moves on Stripe's
/// hosted Checkout page and not inside the app:
///
///   1. [executeSendMoney] creates the Checkout session and returns its
///      `checkoutUrl`. Nothing has been paid yet.
///   2. The app opens that URL. Once [verifyCheckoutSession] reports the session
///      paid, [completePaymentRecord] writes the settled row and debits the
///      wallet.
///
/// Implementations must never invent a `checkoutUrl`; they throw when the
/// gateway is unreachable, so a failed transfer can never look like a paid one.
abstract class PaymentRepository {
  Future<List<WalletCardModel>> getCards();
  Future<List<BeneficiaryModel>> getBeneficiaries();
  Future<List<TransactionModel>> getTransactions({String? cardId});

  /// Opens a remittance with the gateway and returns the raw session payload,
  /// including `checkoutUrl` and `sessionId`.
  ///
  /// Throws when the gateway cannot be reached or returns no usable Checkout
  /// URL. [beneficiary] accepts a [BeneficiaryModel] or a plain map.
  Future<Map<String, dynamic>> executeSendMoney({
    required String cardId,
    required dynamic beneficiary,
    required double sourceAmount,
    required String sourceCurrency,
    required double exchangeRate,
    required double amountBdt,
    required double incentiveBdt,
    String? connectedAccountId,
  });

  /// Whether the Checkout session has actually been paid.
  Future<bool> verifyCheckoutSession(String sessionId);

  /// Records the settled remittance and debits the source wallet. Safe to call
  /// more than once for the same [stripeSessionId].
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
  });

  Future<bool> executeInterCardTransfer({
    required String fromCardId,
    required String toCardId,
    required double amount,
  });

  /// Name shown on the wallet card deck.
  Future<String> getWalletHolderName();

  /// Live rates keyed by currency code, or null when none are available and the
  /// bundled [CurrencyModel] rates should stand.
  Future<Map<String, double>?> fetchExchangeRates();
}
