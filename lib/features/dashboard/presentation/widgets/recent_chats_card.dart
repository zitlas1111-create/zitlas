import 'package:flutter/material.dart';

import '../dashboard_visuals.dart';

/// `.comms-section` / `renderChats()`. The website's own chat list is
/// backed only by a local `zitlas_chats` cache with no Firestore/backend
/// source of truth, and even on production tapping a chat card just shows
/// a "Chats — coming soon!" toast (`dashboard.js:62`) — chat isn't real
/// functionality yet on the website either. A fresh account has no local
/// chat cache, so the faithful port is this same empty state; full chat
/// migration is a later phase (see docs/MIGRATION_INVENTORY.md §6).
class RecentChatsCard extends StatelessWidget {
  const RecentChatsCard({super.key});

  @override
  Widget build(BuildContext context) {
    return DashboardCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Recent Chats',
            style: TextStyle(
              color: DashboardColors.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 16),
          Center(
            child: Column(
              children: [
                const Text('💬', style: TextStyle(fontSize: 32)),
                const SizedBox(height: 10),
                const Text(
                  'No conversations yet',
                  style: TextStyle(
                    color: DashboardColors.textPrimary,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Connect with a coach or nutritionist to start a chat',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: DashboardColors.textMuted, fontSize: 11.5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
