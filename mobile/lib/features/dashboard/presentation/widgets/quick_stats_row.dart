import 'package:flutter/material.dart';

import '../dashboard_visuals.dart';

/// `.quick-stats-section` / `.qs-card`. Confirmed via `dashboard.js`
/// (`initStatCountUp()`, lines ~1955-1970): these 4 values are hard-coded
/// directly in the website's own markup and JS — `initStatCountUp()` only
/// re-animates the SAME literal numbers `[7, 5, 3, 4.50]`, it does not read
/// any real data source at all. This is not fake data invented for this
/// port — it's a faithful reproduction of the real production website's
/// own static placeholder section.
class QuickStatsRow extends StatelessWidget {
  const QuickStatsRow({super.key});

  static const _stats = [
    ('🔥', '7', 'Day Streak'),
    ('🥗', '5', 'Meals Tracked'),
    ('💪', '3', 'Workouts'),
    ('⭐', '4.50', 'Rating'),
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            'Quick Stats',
            style: TextStyle(
              color: DashboardColors.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            for (final (icon, value, label) in _stats) ...[
              Expanded(child: _QuickStatCard(icon: icon, value: value, label: label)),
              if (label != _stats.last.$3) const SizedBox(width: 10),
            ],
          ],
        ),
      ],
    );
  }
}

class _QuickStatCard extends StatelessWidget {
  const _QuickStatCard({required this.icon, required this.value, required this.label});
  final String icon;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return DashboardCard(
      radius: kDashboardRadiusSm,
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      child: Column(
        children: [
          Text(icon, style: const TextStyle(fontSize: 18)),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              color: DashboardColors.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 2,
            style: const TextStyle(
              color: DashboardColors.textMuted,
              fontSize: 9.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }
}
