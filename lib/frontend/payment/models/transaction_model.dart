enum TransactionType {
  send,
  receive,
  subscription,
  transfer,
}

/// Where a remittance stands with the gateway. A transfer is [pending] from the
/// moment the Stripe Checkout session is created until the session reports paid,
/// so the history row appears immediately and then settles.
enum TransactionStatus {
  pending,
  completed,
  failed,
}

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
    };
  }

  factory TransactionModel.fromMap(Map<String, dynamic> map) {
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
      amountBdt: (map['amount_bdt'] as num?)?.toDouble(),
      convertedAmount: (map['converted_amount'] as num?)?.toDouble(),
      currency: map['currency'] ?? 'BDT',
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
