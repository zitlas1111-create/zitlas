import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../auth/auth_state.dart';
import '../../dashboard_controller.dart';
import '../dashboard_visuals.dart';

/// `.dash-header` on `dashboard.html`: avatar (-> profile), centered logo,
/// notification bell with a live unread-count badge from
/// `notification-center.js`'s `listenUnreadCount`.
class DashboardHeader extends StatelessWidget {
  const DashboardHeader({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<DashboardController>();
    final authProfile = context.watch<AuthState>().profile;
    // Matches `getCurrentUserProfileImage()`'s priority chain: personalInfo/
    // users-doc fields first, falling back to the Firebase Auth profile
    // (covers the Google sign-in photoURL case the users-doc fields don't).
    final photoUrl = controller.photoUrl ?? authProfile?.photoUrl;
    final displayName = controller.displayName ?? authProfile?.name;

    return Container(
      height: 65,
      padding: const EdgeInsets.symmetric(horizontal: 18),
      decoration: const BoxDecoration(
        color: Color(0xD9F4F7ED), // rgba(244,247,237,0.85) frosted header
        border: Border(bottom: BorderSide(color: DashboardColors.borderSub)),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => context.go('/profile'),
            child: CircleAvatar(
              radius: 19,
              backgroundColor: DashboardColors.bgCardLight,
              foregroundImage: photoUrl != null
                  ? CachedNetworkImageProvider(photoUrl)
                  : null,
              child: photoUrl == null
                  ? Text(
                      _initials(displayName),
                      style: const TextStyle(
                        color: DashboardColors.primary,
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                      ),
                    )
                  : null,
            ),
          ),
          const Spacer(),
          Image.asset('assets/images/logo.png', height: 42),
          const Spacer(),
          // wallet.js injects its balance button immediately before the
          // header's right-side button, wrapped with it in a flex group.
          _WalletButton(available: controller.walletAvailable),
          const SizedBox(width: 4),
          GestureDetector(
            onTap: () => context.push('/notifications'),
            child: SizedBox(
              width: 40,
              height: 40,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: DashboardColors.bgCard,
                    ),
                    child: const Icon(
                      Icons.notifications_none_rounded,
                      color: DashboardColors.textPrimary,
                      size: 20,
                    ),
                  ),
                  if (controller.unreadNotifications > 0)
                    Positioned(
                      top: 6,
                      right: 6,
                      child: Container(
                        width: 9,
                        height: 9,
                        decoration: BoxDecoration(
                          color: DashboardColors.primary,
                          shape: BoxShape.circle,
                          border: Border.all(color: DashboardColors.bgStart, width: 2),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _initials(String? name) {
    if (name == null || name.trim().isEmpty) return 'ZT';
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length == 1) return parts[0].substring(0, 1).toUpperCase();
    return (parts[0].substring(0, 1) + parts[1].substring(0, 1)).toUpperCase();
  }
}

/// `.zw-btn` (`buildButton()` in components/wallet.js) — shows the SPENDABLE
/// balance (`balance - reserved`), not the raw balance, and opens the wallet.
class _WalletButton extends StatelessWidget {
  const _WalletButton({required this.available});

  final num available;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => context.push('/wallet'),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
        decoration: BoxDecoration(
          color: DashboardColors.bgCard,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: DashboardColors.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.account_balance_wallet_outlined,
              size: 15,
              color: DashboardColors.primary,
            ),
            const SizedBox(width: 4),
            Text(
              _fmtAmt(available),
              style: const TextStyle(
                color: DashboardColors.textPrimary,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// `fmtAmt()` — ₹ with no decimals for whole amounts.
  static String _fmtAmt(num v) {
    final n = v.round();
    final s = n.toString();
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
      buf.write(s[i]);
    }
    return '₹$buf';
  }
}
