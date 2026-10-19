enum TransactionType { send, receive, subscription, transfer }

/// Where a remittance stands with the gateway. A transfer is [pending] from the
/// moment the Stripe Checkout session is created until the session reports paid,
/// so the history row appears immediately and then settles.
enum TransactionStatus { pending, completed, failed }

class TransactionModel {
  final String id;
  final String title;
  final String subtitle;

  /// Amount in [currency] — what the history row shows.
  final double amount;

  /// The same transfer expressed in the BDT baseline, when the gateway
  /// reported one. Null for rows that were never cross-border.
  final double? amountBdt;

  /// The amount actually debited in the source currency, when it differs
  /// from [amount] (e.g. 100 SAR debited to deliver 3,264 BDT).
  final double? convertedAmount;

  final String currency;
  final DateTime timestamp;
  final TransactionType type;
  final TransactionStatus status;
  final String? cardId;
  final String? avatarUrl;
  final String? iconCategory; // google, person, netflix, bank, etc.

  /// The Stripe Checkout session this row was created from, so a resumed or
  /// replayed payment updates the existing row instead of adding a second one.
  final String? stripeSessionId;

  /// What actually left the sender's bank, and in which currency. Shown on the
  /// history row beside [creditedAmount] so both sides of the transfer are
  /// visible without opening it.
  final double? debitedAmount;
  final String? debitedCurrency;

  /// What the recipient's bank was credited, and in which currency.
  final double? creditedAmount;
  final String? creditedCurrency;

  /// True when the row carries both sides of the transfer.
  bool get hasBothLegs => debitedAmount != null && creditedAmount != null;

  /// Links the debit row and the credit row written for one transfer, so the
  /// two halves can be shown or reconciled together.
  final String? transferGroup;

  /// The two rows every transfer produces: what left the sender's card, and
  /// what reached the destination. Both carry the same [groupId].
  ///
  /// Each row is one-sided on purpose — the debit shows only what was taken and
  /// the credit only what arrived — so history reads as a real ledger rather
  /// than one row trying to say both things at once.
  static List<TransactionModel> transferPair({
    required String groupId,
    required DateTime timestamp,
    required String debitTitle,
    required String debitSubtitle,
    required double debitAmount,
    required String debitCurrency,
    required String debitCardId,
    required String creditTitle,
    required String creditSubtitle,
    required double creditAmount,
    required String creditCurrency,
    String? creditCardId,
    double? amountBdt,
    String? stripeSessionId,
    String? iconCategory,
    TransactionType type = TransactionType.send,
    TransactionStatus status = TransactionStatus.completed,
  }) {
    final stamp = timestamp.millisecondsSinceEpoch;
    return [
      // Newest first: the credit is listed above the debit it came from.
      TransactionModel(
        id: '${groupId}_credit_$stamp',
        title: creditTitle,
        subtitle: creditSubtitle,
        amount: creditAmount,
        amountBdt: amountBdt,
        currency: creditCurrency,
        timestamp: timestamp,
        type: TransactionType.receive,
        status: status,
        cardId: creditCardId,
        iconCategory: iconCategory,
        stripeSessionId: stripeSessionId,
        transferGroup: groupId,
        creditedAmount: creditAmount,
        creditedCurrency: creditCurrency,
      ),
      TransactionModel(
        id: '${groupId}_debit_$stamp',
        title: debitTitle,
        subtitle: debitSubtitle,
        amount: debitAmount,
        amountBdt: amountBdt,
        convertedAmount: debitAmount,
        currency: debitCurrency,
        timestamp: timestamp,
        type: type,
        status: status,
        cardId: debitCardId,
        iconCategory: iconCategory,
        stripeSessionId: stripeSessionId,
        transferGroup: groupId,
        debitedAmount: debitAmount,
        debitedCurrency: debitCurrency,
      ),
    ];
  }

  const TransactionModel({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.amount,
    required this.currency,
    required this.timestamp,
    required this.type,
    this.status = TransactionStatus.completed,
    this.amountBdt,
    this.convertedAmount,
    this.cardId,
    this.avatarUrl,
    this.iconCategory,
    this.stripeSessionId,
    this.debitedAmount,
    this.debitedCurrency,
    this.creditedAmount,
    this.creditedCurrency,
    this.transferGroup,
  });

  bool get isIncoming => type == TransactionType.receive;

  bool get isPending => status == TransactionStatus.pending;

  bool get isFailed => status == TransactionStatus.failed;

  TransactionModel copyWith({
    String? id,
    String? title,
    String? subtitle,
    double? amount,
    double? amountBdt,
    double? convertedAmount,
    String? currency,
    DateTime? timestamp,
    TransactionType? type,
    TransactionStatus? status,
    String? cardId,
    String? avatarUrl,
    String? iconCategory,
    String? stripeSessionId,
    double? debitedAmount,
    String? debitedCurrency,
    double? creditedAmount,
    String? creditedCurrency,
    String? transferGroup,
  }) {
    return TransactionModel(
      id: id ?? this.id,
      title: title ?? this.title,
      subtitle: subtitle ?? this.subtitle,
      amount: amount ?? this.amount,
      amountBdt: amountBdt ?? this.amountBdt,
      convertedAmount: convertedAmount ?? this.convertedAmount,
      currency: currency ?? this.currency,
      timestamp: timestamp ?? this.timestamp,
      type: type ?? this.type,
      status: status ?? this.status,
      cardId: cardId ?? this.cardId,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      iconCategory: iconCategory ?? this.iconCategory,
      stripeSessionId: stripeSessionId ?? this.stripeSessionId,
      debitedAmount: debitedAmount ?? this.debitedAmount,
      debitedCurrency: debitedCurrency ?? this.debitedCurrency,
      creditedAmount: creditedAmount ?? this.creditedAmount,
      creditedCurrency: creditedCurrency ?? this.creditedCurrency,
      transferGroup: transferGroup ?? this.transferGroup,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'subtitle': subtitle,
      'amount': amount,
      'amount_bdt': amountBdt,
      'converted_amount': convertedAmount,
      'currency': currency,
      'timestamp': timestamp.toIso8601String(),
      'type': type.name,
      'status': status.name,
      'card_id': cardId,
      'avatar_url': avatarUrl,
      'icon_category': iconCategory,
      'stripe_payment_id': stripeSessionId,
      'debited_amount': debitedAmount,
      'debited_currency': debitedCurrency,
      'credited_amount': creditedAmount,
      'credited_currency': creditedCurrency,
      'transfer_group': transferGroup,
    };
  }

  factory TransactionModel.fromMap(Map<String, dynamic> map) {
    // Older rows predate the explicit debit/credit columns, so fall back to the
    // source amount and the BDT baseline, which are the same two legs.
    final converted = (map['converted_amount'] as num?)?.toDouble();
    final bdt = (map['amount_bdt'] as num?)?.toDouble();

    TransactionType type;
    switch (map['type']) {
      case 'receive':
        type = TransactionType.receive;
        break;
      case 'subscription':
        type = TransactionType.subscription;
        break;
      case 'transfer':
        type = TransactionType.transfer;
        break;
      default:
        type = TransactionType.send;
    }

    return TransactionModel(
      id: map['id'] ?? '',
      title: map['title'] ?? '',
      subtitle: map['subtitle'] ?? '',
      amount: (map['amount'] as num?)?.toDouble() ?? 0.0,
      amountBdt: bdt,
      convertedAmount: converted,
      currency: map['currency'] ?? 'BDT',
      debitedAmount: (map['debited_amount'] as num?)?.toDouble() ?? converted,
      debitedCurrency:
          map['debited_currency']?.toString() ?? map['currency']?.toString(),
      creditedAmount: (map['credited_amount'] as num?)?.toDouble() ?? bdt,
      creditedCurrency: map['credited_currency']?.toString() ?? 'BDT',
      transferGroup: map['transfer_group']?.toString(),
      timestamp: map['timestamp'] != null
          ? DateTime.tryParse(map['timestamp']) ?? DateTime.now()
          : DateTime.now(),
      type: type,
      status: parseStatus(map['status']),
      cardId: map['card_id'],
      avatarUrl: map['avatar_url'],
      iconCategory: map['icon_category'],
      stripeSessionId: map['stripe_payment_id']?.toString(),
    );
  }

  /// Tolerant of the spellings the gateway and the database use for the same
  /// state ('paid', 'complete', 'succeeded' all mean settled).
  static TransactionStatus parseStatus(Object? raw) {
    switch (raw?.toString().toLowerCase()) {
      case 'pending':
      case 'processing':
      case 'unpaid':
      case 'open':
        return TransactionStatus.pending;
      case 'failed':
      case 'canceled':
      case 'cancelled':
      case 'expired':
        return TransactionStatus.failed;
      default:
        return TransactionStatus.completed;
    }
  }
}
