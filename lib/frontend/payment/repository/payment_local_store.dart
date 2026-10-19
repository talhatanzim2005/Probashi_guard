import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/beneficiary_model.dart';
import '../models/transaction_model.dart';
import '../models/wallet_card_model.dart';

/// What the wallet keeps on the device so it is still there after the app is
/// closed: card balances, the transaction ledger, and recipients the person
/// added.
///
/// Supabase still owns the WPS wallet and the remote ledger when it is
/// reachable. This is the on-device copy that everything else falls back to, so
/// a transfer between two cards, or a recipient added offline, never silently
/// vanishes on the next launch.
///
/// [load] reads it all once before `runApp`; the getters are then synchronous,
/// so repositories can restore their state in a constructor.
class PaymentLocalStore {
  PaymentLocalStore._();

  static const String _balancesKey = 'payment_card_balances_v1';
  static const String _transactionsKey = 'payment_transactions_v1';
  static const String _beneficiariesKey = 'payment_added_beneficiaries_v1';

  /// Older rows are dropped past this, so the saved ledger cannot grow forever.
  static const int maxSavedTransactions = 200;

  static Map<String, double> _balances = {};
  static List<TransactionModel>? _transactions;
  static List<BeneficiaryModel> _beneficiaries = [];

  /// Card id to the balance last saved for it.
  static Map<String, double> get savedBalances => Map.unmodifiable(_balances);

  /// The saved ledger, or null when nothing has been saved yet, so a new
  /// install still starts from the seeded history.
  static List<TransactionModel>? get savedTransactions =>
      _transactions == null ? null : List.unmodifiable(_transactions!);

  static List<BeneficiaryModel> get savedBeneficiaries =>
      List.unmodifiable(_beneficiaries);

  /// Reads everything saved on this device. A failure is not fatal: the wallet
  /// just opens with its defaults.
  static Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      final rawBalances = prefs.getString(_balancesKey);
      if (rawBalances != null) {
        final decoded = jsonDecode(rawBalances);
        if (decoded is Map) {
          _balances = {
            for (final e in decoded.entries)
              if (e.value is num) e.key.toString(): (e.value as num).toDouble(),
          };
        }
      }

      final rawTransactions = prefs.getString(_transactionsKey);
      if (rawTransactions != null) {
        final decoded = jsonDecode(rawTransactions);
        if (decoded is List) {
          _transactions = [
            for (final row in decoded)
              if (row is Map)
                TransactionModel.fromMap(Map<String, dynamic>.from(row)),
          ];
        }
      }

      final rawBeneficiaries = prefs.getString(_beneficiariesKey);
      if (rawBeneficiaries != null) {
        final decoded = jsonDecode(rawBeneficiaries);
        if (decoded is List) {
          _beneficiaries = [
            for (final row in decoded)
              if (row is Map)
                BeneficiaryModel.fromMap(Map<String, dynamic>.from(row)),
          ];
        }
      }
    } catch (e) {
      debugPrint('[PaymentLocalStore] could not read saved wallet data: $e');
    }
  }

  static Future<void> saveCards(List<WalletCardModel> cards) async {
    await _write(
      _balancesKey,
      jsonEncode({for (final c in cards) c.id: c.balance}),
    );
  }

  static Future<void> saveTransactions(List<TransactionModel> items) async {
    final newest = items.take(maxSavedTransactions);
    await _write(
      _transactionsKey,
      jsonEncode([for (final t in newest) t.toMap()]),
    );
  }

  static Future<void> saveBeneficiaries(List<BeneficiaryModel> items) async {
    _beneficiaries = List.of(items);
    await _write(
      _beneficiariesKey,
      jsonEncode([for (final b in items) b.toMap()]),
    );
  }

  /// Logout: the next person on this phone must not see this wallet.
  static Future<void> clear() async {
    _balances = {};
    _transactions = null;
    _beneficiaries = [];
    try {
      final prefs = await SharedPreferences.getInstance();
      await Future.wait([
        prefs.remove(_balancesKey),
        prefs.remove(_transactionsKey),
        prefs.remove(_beneficiariesKey),
      ]);
    } catch (e) {
      debugPrint('[PaymentLocalStore] could not clear saved wallet data: $e');
    }
  }

  static Future<void> _write(String key, String value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(key, value);
    } catch (e) {
      debugPrint('[PaymentLocalStore] could not save $key: $e');
    }
  }

  /// Forgets the in-memory copy, so a test starts from a clean slate.
  @visibleForTesting
  static void resetForTesting() {
    _balances = {};
    _transactions = null;
    _beneficiaries = [];
  }
}
