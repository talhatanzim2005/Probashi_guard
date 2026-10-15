enum TransactionType {
  send,
  receive,
  subscription,
  transfer,
}

class TransactionModel {
  final String id;
  final String title;
  final String subtitle;
  final double amount;
  final String currency;
  final DateTime timestamp;
  final TransactionType type;
  final String? cardId;
  final String? avatarUrl;
  final String? iconCategory; // google, person, netflix, bank, etc.

  const TransactionModel({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.amount,
    required this.currency,
    required this.timestamp,
    required this.type,
    this.cardId,
    this.avatarUrl,
    this.iconCategory,
  });

  bool get isIncoming => type == TransactionType.receive;

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'subtitle': subtitle,
      'amount': amount,
      'currency': currency,
      'timestamp': timestamp.toIso8601String(),
      'type': type.name,
      'card_id': cardId,
      'avatar_url': avatarUrl,
      'icon_category': iconCategory,
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
      currency: map['currency'] ?? 'BDT',
      timestamp: map['timestamp'] != null
          ? DateTime.tryParse(map['timestamp']) ?? DateTime.now()
          : DateTime.now(),
      type: type,
      cardId: map['card_id'],
      avatarUrl: map['avatar_url'],
      iconCategory: map['icon_category'],
    );
  }
}
