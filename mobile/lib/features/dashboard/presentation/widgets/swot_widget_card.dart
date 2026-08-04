import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../dashboard_controller.dart';
import '../dashboard_visuals.dart';
import 'section_header.dart';
import 'widget_empty_state.dart';

/// `#swotWidgetSection` / `renderSwotWidget()`. `swot` isn't written by any
/// Flutter feature yet (the AI Coach assessment wizard is a later phase —
/// see docs/MIGRATION_INVENTORY.md §6), so this always renders the real
/// website's own empty state today; the live-data path is already wired
/// (`DashboardController.hasSwot`) so it activates automatically once that
/// field starts appearing on `users/{uid}`.
class SwotWidgetCard extends StatelessWidget {
  const SwotWidgetCard({super.key});

  @override
  Widget build(BuildContext context) {
    final hasSwot = context.watch<DashboardController>().hasSwot;

    return DashboardCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(
            emoji: '🧠',
            title: 'SWOT Analysis',
            subtitle: hasSwot ? '' : 'Take assessment to unlock',
            trailingText: 'View Full →',
            onTrailingTap: () => context.push('/assessment'),
          ),
          if (!hasSwot)
            WidgetEmptyState(
              text: 'Complete your AI assessment to unlock your SWOT analysis.',
              ctaLabel: 'Start Assessment →',
              onTap: () => context.push('/assessment'),
            ),
        ],
      ),
    );
  }
}
