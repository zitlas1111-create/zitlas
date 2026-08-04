import 'package:flutter/foundation.dart';

/// What moved the money.
///
/// The backend writes only `credit` and `debit` today (see
/// `backend/routes/payment.py` and `coaching.py`). The rest are recognised so a
/// future server-side reward/refund/referral entry renders correctly the day it
/// appears, instead of falling through to a generic row — and anything genuinely
/// unrecognised still renders rather than being dropped.
enum WalletTransactionType {
  credit('credit', '⬆️', 'Money in'),
  debit('debit', '⬇️', 'Money out'),
  reward('reward', '🎁', 'Reward'),
  refund('refund', '↩️', 'Refund'),
  referral('referral', '🤝', 'Referral'),
  cashback('cashback', '💸', 'Cashback'),

  /// A type the server introduced that this build doesn't know yet.
  unknown('unknown', '•', 'Transaction');

  const WalletTransactionType(this.id, this.icon, this.label);

  final String id, icon, label;

  /// Whether this type ADDS to the balance.
  ///
  /// Drives the sign and colour of every row, so it is derived from the type
  /// rather than from the amount's sign — the backend writes positive amounts
  /// for both directions, and a debit rendered as "+₹500" is the kind of thing
  /// that makes an athlete think they've been credited when they've been
  /// charged.
  bool get isCredit => switch (this) {
        credit || reward || refund || referral || cashback => true,
        debit => false,
        // An unknown type is not assumed to be money in — that would overstate
        // a balance. It renders unsigned.
        unknown => false,
      };

  bool get isDebit => this == debit;

  static WalletTransactionType fromId(String? raw) {
    if (raw == null) return unknown;
    final id = raw.trim().toLowerCase();
    for (final t in values) {
      if (t.id == id) return t;
    }
    return unknown;
  }
}

/// One line of the wallet ledger, as stored in `users/{uid}.wallet.transactions`.
@immutable
class WalletTransaction {
  const WalletTransaction({
    required this.id,
    required this.type,
    required this.amount,
    required this.description,
    required this.date,
  });

  final String id;
  final WalletTransactionType type;

  /// Always POSITIVE — direction comes from [type], matching what the backend
  /// writes. Stored as an absolute value so no row can render a double negative.
  final double amount;

  final String description;

  /// Null when the stored `date` was missing or unparseable. Kept nullable
  /// rather than defaulted to "now": a transaction from last month suddenly
  /// dated today would sort to the top and read as a fresh charge.
  final DateTime? date;

  /// Signed contribution to the balance — the basis for the credits/debits
  /// reconciliation shown in [Wallet].
  double get signedAmount => type.isCredit ? amount : -amount;

  static WalletTransaction? fromMap(Map<String, dynamic> map, {required int index}) {
    final rawAmount = map['amount'];
    if (rawAmount is! num) return null;
    return WalletTransaction(
      // Older entries predate the `id` field; the array index keeps the key
      // unique and stable for the list, which is all it is used for.
      id: (map['id'] as String?)?.trim().isNotEmpty == true
          ? map['id'] as String
          : 'txn_$index',
      type: WalletTransactionType.fromId(map['type'] as String?),
      amount: rawAmount.toDouble().abs(),
      description: (map['description'] as String?)?.trim().isNotEmpty == true
          ? map['description'] as String
          : 'ZITLAS transaction',
      date: DateTime.tryParse(map['date'] as String? ?? '')?.toLocal(),
    );
  }
}

/// `users/{uid}.wallet` — the athlete's real balance.
///
/// BACKEND-WRITTEN ONLY. `firestore.rules` blocks the client from ever writing
/// `users/{uid}.wallet` (`updateKeeps(['wallet', ...])`), and money only moves
/// through `POST /api/payment/verify` (credit) and `POST /api/payment/charge`
/// (debit), both inside Firestore transactions. Nothing in the app may
/// optimistically adjust a balance — it reads what the server says.
@immutable
class Wallet {
  const Wallet({
    this.balance = 0,
    this.reserved = 0,
    this.totalAdded = 0,
    this.totalSpent = 0,
    this.transactions = const [],
    this.exists = true,
  });

  /// Total held, INCLUDING anything locked by a reservation.
  final double balance;

  /// Locked by an open Personal Coaching request (`backend/routes/coaching.py`)
  /// until the expert accepts (debited), rejects, or it expires (released).
  final double reserved;

  final double totalAdded;
  final double totalSpent;

  /// Newest first — the stored array is append-order, and this is reversed once
  /// at parse time so no view has to remember to do it.
  final List<WalletTransaction> transactions;

  /// False when the user document has no `wallet` field at all.
  ///
  /// A brand-new account genuinely has no wallet until the backend writes one,
  /// so this is a normal state, NOT an error — see [WalletRepository] for why
  /// the app must not create the document itself.
  final bool exists;

  /// A wallet that has never been funded. Distinct from [exists]: an athlete
  /// who added ₹500 and spent all of it has a wallet, at zero.
  static const empty = Wallet(exists: false);

  /// What can actually be spent — `available()` in `components/wallet.js`.
  ///
  /// Clamped at zero: a reservation can never make the spendable figure
  /// negative, and showing "-₹200 available" would be nonsense.
  double get available {
    final spendable = balance - reserved;
    return spendable < 0 ? 0 : spendable;
  }

  bool get hasTransactions => transactions.isNotEmpty;

  bool canAfford(num amount) => available >= amount;

  /// Sum of every crediting entry in the ledger.
  double get totalCredits => transactions
      .where((t) => t.type.isCredit)
      .fold(0.0, (sum, t) => sum + t.amount);

  /// Sum of every debiting entry in the ledger.
  double get totalDebits => transactions
      .where((t) => t.type.isDebit)
      .fold(0.0, (sum, t) => sum + t.amount);

  /// The balance the ledger implies: credits − debits.
  double get ledgerBalance => totalCredits - totalDebits;

  /// True when the stored balance and the ledger disagree by more than a
  /// rounding cent.
  ///
  /// The two are maintained independently by the backend (the balance is
  /// incremented in place; the array is appended to), so a divergence means a
  /// write landed on one and not the other. The app REPORTS this rather than
  /// "correcting" it: the stored balance is what the server will actually spend
  /// against, and a client that quietly displayed its own recomputed figure
  /// would show an athlete money they cannot use.
  ///
  /// Only meaningful once a wallet has entries — an account whose ledger
  /// predates the array field would otherwise look permanently inconsistent.
  bool get ledgerDisagrees =>
      hasTransactions && (ledgerBalance - balance).abs() > 0.01;

  static Wallet fromUserDoc(Map<String, dynamic>? data) {
    final raw = data?['wallet'];
    if (raw is! Map) return Wallet.empty;
    final map = raw.cast<String, dynamic>();

    final rawTxns = map['transactions'];
    final parsed = <WalletTransaction>[];
    if (rawTxns is List) {
      for (var i = 0; i < rawTxns.length; i++) {
        final entry = rawTxns[i];
        if (entry is! Map) continue;
        final txn = WalletTransaction.fromMap(entry.cast<String, dynamic>(), index: i);
        if (txn != null) parsed.add(txn);
      }
    }

    return Wallet(
      balance: _money(map['balance']),
      reserved: _money(map['reserved']),
      totalAdded: _money(map['total_added']),
      totalSpent: _money(map['total_spent']),
      // Newest first. `reversed` rather than a date sort: entries are appended
      // in order, and a date sort would scatter the (legitimately) undated
      // legacy rows to one end.
      transactions: parsed.reversed.toList(growable: false),
      exists: true,
    );
  }

  static double _money(Object? v) => v is num ? v.toDouble() : 0;
}
