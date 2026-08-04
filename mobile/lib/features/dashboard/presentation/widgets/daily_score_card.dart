import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../dashboard_controller.dart';
import '../dashboard_visuals.dart';
import 'section_header.dart';

/// `#dailyScoreSection` — `style="display:none"` by default on the website
/// and only shown once `ZitlasDailyScore.compute().overall` is non-null;
/// same gating here (`DashboardController.dailyScore`). `.ds-chip`s only
/// render for non-null sub-scores, exactly like the website's `chip()`
/// helper returning `''` for `null`.
class DailyScoreCard extends StatelessWidget {
  const DailyScoreCard({super.key});

  @override
  Widget build(BuildContext context) {
    final score = context.watch<DashboardController>().dailyScore;
    if (score == null || score.overall == null) return const SizedBox.shrink();

    final chips = <(String, int?)>[
      ('Steps', score.stepsPct),
      ('Hydration', score.hydrationPct),
      ('Meal Quality', score.mealQualityPct),
      ('Workout', score.workoutPct),
      ('Sleep', score.sleepPct),
    ].where((c) => c.$2 != null).toList();

    return DashboardCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionHeader(
            emoji: '🎯',
            title: "Today's Score",
            subtitle: 'AI + Coach combined',
          ),
          const SizedBox(height: 14),
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 16,
            runSpacing: 10,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${score.overall}',
                    style: const TextStyle(
                      color: DashboardColors.primary,
                      fontSize: 40,
                      fontWeight: FontWeight.w900,
                      height: 1,
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.only(left: 2, bottom: 4),
                    child: Text(
                      '/100',
                      style: TextStyle(
                        color: DashboardColors.textSecondary,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final (label, value) in chips)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: DashboardColors.bgCardLight,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      constraints: const BoxConstraints(minWidth: 64),
                      child: Column(
                        children: [
                          Text(
                            label,
                            style: const TextStyle(
                              color: DashboardColors.textMuted,
                              fontSize: 10,
                            ),
                          ),
                          Text(
                            '$value',
                            style: const TextStyle(
                              color: DashboardColors.textPrimary,
                              fontSize: 15,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}
