import 'package:flutter/material.dart';

import '../../../dashboard/presentation/dashboard_visuals.dart';
import '../../models/wallet.dart';
import '../widgets/wallet_transaction_row.dart';
import 'wallet_screen.dart' show copyToClipboard, formatIndianAmount;

/// The full ledger — `renderTransactions()` in `components/wallet.js`, plus a
/// type filter the web panel doesn't have (a long list of mixed credits and
/// debits is hard to scan on a phone).
///
/// Newest first, as delivered by [Wallet]. Long-press a row to copy its
/// transaction id for a support query.
class TransactionHistoryScreen extends StatefulWidget {
  const TransactionHistoryScreen({super.key, required this.transactions});

  final List<WalletTransaction> transactions;

  @override
  State<TransactionHistoryScreen> createState() => _TransactionHistoryScreenState();
}

enum _Filter { all, credits, debits }

class _TransactionHistoryScreenState extends State<TransactionHistoryScreen> {
  _Filter _filter = _Filter.all;

  List<WalletTransaction> get _visible => switch (_filter) {
        _Filter.all => widget.transactions,
        _Filter.credits => widget.transactions.where((t) => t.type.isCredit).toList(),
        _Filter.debits => widget.transactions.where((t) => t.type.isDebit).toList(),
      };

  @override
  Widget build(BuildContext context) {
    final visible = _visible;
    final credits = widget.transactions
        .where((t) => t.type.isCredit)
        .fold<double>(0, (s, t) => s + t.amount);
    final debits = widget.transactions
        .where((t) => t.type.isDebit)
        .fold<double>(0, (s, t) => s + t.amount);

    return Scaffold(
      backgroundColor: DashboardColors.bgStart,
      appBar: AppBar(
        backgroundColor: DashboardColors.bgCard,
        elevation: 0,
        title: const Text(
          'Transaction History',
          style: TextStyle(
            color: DashboardColors.textPrimary,
            fontSize: 16,
            fontWeight: FontWeight.w800,
          ),
        ),
        iconTheme: const IconThemeData(color: DashboardColors.textPrimary),
      ),
      body: widget.transactions.isEmpty
          ? const _EmptyHistory()
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
                  child: Row(
                    children: [
                      Expanded(
                        child: _Total(
                          label: 'Total in',
                          value: '+₹${formatIndianAmount(credits)}',
                          color: DashboardColors.success,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _Total(
                          label: 'Total out',
                          value: '−₹${formatIndianAmount(debits)}',
                          color: DashboardColors.error,
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    children: [
                      for (final f in _Filter.values)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: ChoiceChip(
                            label: Text(switch (f) {
                              _Filter.all => 'All',
                              _Filter.credits => 'Money in',
                              _Filter.debits => 'Money out',
                            }),
                            selected: _filter == f,
                            onSelected: (_) => setState(() => _filter = f),
                            labelStyle: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: _filter == f ? Colors.white : DashboardColors.textSecondary,
                            ),
                            selectedColor: DashboardColors.primary,
                            backgroundColor: DashboardColors.bgCard,
                            side: const BorderSide(color: DashboardColors.borderSub),
                            showCheckmark: false,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                Expanded(
                  child: visible.isEmpty
                      // A filter that matches nothing is NOT the same as an
                      // empty wallet, and says so.
                      ? const Center(
                          child: Padding(
                            padding: EdgeInsets.all(28),
                            child: Text(
                              'No transactions of this type yet.',
                              style: TextStyle(
                                fontSize: 13,
                                color: DashboardColors.textSecondary,
                              ),
                            ),
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(12, 8, 12, 28),
                          itemCount: visible.length,
                          separatorBuilder: (_, _) => const Divider(
                            height: 1,
                            indent: 62,
                            color: DashboardColors.borderSub,
                          ),
                          itemBuilder: (context, i) {
                            final txn = visible[i];
                            return Container(
                              color: DashboardColors.bgCard,
                              child: WalletTransactionRow(
                                key: ValueKey(txn.id),
                                transaction: txn,
                                onLongPress: () async {
                                  await copyToClipboard(txn.id);
                                  if (!context.mounted) return;
                                  ScaffoldMessenger.of(context)
                                    ..hideCurrentSnackBar()
                                    ..showSnackBar(const SnackBar(
                                      content: Text('Transaction ID copied'),
                                    ));
                                },
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }
}

class _Total extends StatelessWidget {
  const _Total({required this.label, required this.value, required this.color});
  final String label, value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: DashboardColors.bgCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: DashboardColors.borderSub),
      ),
      child: Column(
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 10.5, color: DashboardColors.textSecondary),
          ),
          const SizedBox(height: 3),
          FittedBox(
            child: Text(
              value,
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: color),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyHistory extends StatelessWidget {
  const _EmptyHistory();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('📋', style: TextStyle(fontSize: 32)),
            SizedBox(height: 10),
            Text(
              'No transactions yet',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: DashboardColors.textPrimary,
              ),
            ),
            SizedBox(height: 6),
            Text(
              'Add funds to get started.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: DashboardColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}
