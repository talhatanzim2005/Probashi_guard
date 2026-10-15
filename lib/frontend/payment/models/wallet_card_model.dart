import 'package:flutter/material.dart';
import '../../../theme/app_colors.dart';

enum CardType {
  wpsPayroll,
  probashiMultiCurrency,
  bkashDirect,
}

class WalletCardModel {
  final String id;
  final String title;
  final String providerName;
  final String cardNumberMasked;
  final double balance;
  final String currency;
  final String expiryDate;
  final CardType cardType;
  final Color primaryColor;
  final Color accentColor;

  const WalletCardModel({
    required this.id,
    required this.title,
    required this.providerName,
    required this.cardNumberMasked,
    required this.balance,
    required this.currency,
    required this.expiryDate,
    required this.cardType,
    required this.primaryColor,
    required this.accentColor,
  });

  WalletCardModel copyWith({
    String? id,
    String? title,
    String? providerName,
    String? cardNumberMasked,
    double? balance,
    String? currency,
    String? expiryDate,
    CardType? cardType,
    Color? primaryColor,
    Color? accentColor,
  }) {
    return WalletCardModel(
      id: id ?? this.id,
      title: title ?? this.title,
      providerName: providerName ?? this.providerName,
      cardNumberMasked: cardNumberMasked ?? this.cardNumberMasked,
      balance: balance ?? this.balance,
      currency: currency ?? this.currency,
      expiryDate: expiryDate ?? this.expiryDate,
      cardType: cardType ?? this.cardType,
      primaryColor: primaryColor ?? this.primaryColor,
      accentColor: accentColor ?? this.accentColor,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'provider_name': providerName,
      'card_number_masked': cardNumberMasked,
      'balance': balance,
      'currency': currency,
      'expiry_date': expiryDate,
      'card_type': cardType.name,
    };
  }

  factory WalletCardModel.fromMap(Map<String, dynamic> map) {
    CardType type;
    switch (map['card_type']) {
      case 'wpsPayroll':
        type = CardType.wpsPayroll;
        break;
      case 'bkashDirect':
        type = CardType.bkashDirect;
        break;
      default:
        type = CardType.probashiMultiCurrency;
    }

    return WalletCardModel(
      id: map['id'] ?? '',
      title: map['title'] ?? '',
      providerName: map['provider_name'] ?? '',
      cardNumberMasked: map['card_number_masked'] ?? '',
      balance: (map['balance'] as num?)?.toDouble() ?? 0.0,
      currency: map['currency'] ?? 'BDT',
      expiryDate: map['expiry_date'] ?? '12/28',
      cardType: type,
      primaryColor: type == CardType.wpsPayroll
          ? const Color(0xFF141A29)
          : type == CardType.probashiMultiCurrency
              ? AppColors.royalBlue
              : const Color(0xFFD12053),
      accentColor: type == CardType.wpsPayroll
          ? AppColors.emeraldGreen
          : AppColors.cloudDancer,
    );
  }
}
