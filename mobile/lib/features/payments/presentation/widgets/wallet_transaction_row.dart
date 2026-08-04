import 'package:flutter/material.dart';

import '../../../dashboard/presentation/dashboard_visuals.dart';
import '../../models/wallet.dart';
import '../screens/wallet_screen.dart' show formatIndianAmount;

/// One ledger line — `txnRow()` in `components/wallet.js`.
///
/// Sign and colour come from the transaction TYPE, never from the amount's
/// sign: the backend stores positive amounts in both directions, so keying off
/// the number would render every debit as money in.
class WalletTransactionRow extends StatelessWidget {
  const WalletTransactionRow({
    super.key,
    required this.transaction,
    this.onLongPress,
  });

  final WalletTransaction transaction;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final credit = transaction.type.isCredit;
    final tint = credit ? DashboardColors.success : DashboardColors.error;

    return InkWell(
      onLongPress: onLongPress,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: tint.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(11),
              ),
              child: Text(transaction.type.icon, style: const TextStyle(fontSize: 15)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    transaction.description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: DashboardColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _subtitle(),
                    style: const TextStyle(fontSize: 11, color: DashboardColors.textMuted),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              // An unrecognised type gets no sign at all rather than a guessed
              // one — claiming a direction we don't know is worse than omitting it.
              '${transaction.type == WalletTransactionType.unknown ? '' : (credit ? '+' : '−')}'
              '₹${formatIndianAmount(transaction.amount)}',
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w800,
                color: transaction.type == WalletTransactionType.unknown
                    ? DashboardColors.textSecondary
                    : tint,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _subtitle() {
    final date = transaction.date;
    // "Unknown date" rather than a fabricated one — see WalletTransaction.date.
    if (date == null) return transaction.type.label;
    return '${transaction.type.label} · ${_formatDate(date)}';
  }

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  static String _formatDate(DateTime d) {
    final hour12 = d.hour % 12 == 0 ? 12 : d.hour % 12;
    final minute = d.minute.toString().padLeft(2, '0');
    final meridiem = d.hour < 12 ? 'AM' : 'PM';
    return '${d.day} ${_months[d.month - 1]} ${d.year}, $hour12:$minute $meridiem';
  }
}
