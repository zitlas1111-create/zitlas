import 'package:flutter/material.dart';

import '../../../../core/theme/zitlas_tokens.dart';
import '../../models/workout_plan_content.dart';

/// `#wpContextBar` / `renderContextBar()` — "Your Plan Profile". For the
/// live AI `weekly_plan` schema, `weeklyFocus` always falls back to the same
/// `goalLabel`, and `expectedImprovement`/`ambition` are never set (so those
/// two rows never appear) — `transformWorkoutPlan()` never populates them.
/// The resulting duplicate Goal/Weekly Focus rows are the real website's
/// behavior for this schema, reproduced as-is rather than "fixed".
class WorkoutContextBar extends StatelessWidget {
  const WorkoutContextBar({super.key, required this.plan});

  final WorkoutPlanContent plan;

  @override
  Widget build(BuildContext context) {
    final goalLabel = plan.planName ?? 'Training Plan';

    return ZitlasCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(color: ZitlasTokens.primary, shape: BoxShape.circle),
              ),
              const SizedBox(width: 8),
              const Text(
                'Your Plan Profile',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: ZitlasTokens.textPrimary),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _Item(icon: '🎯', label: 'Goal', value: goalLabel)),
              const SizedBox(width: 12),
              Expanded(child: _Item(icon: '🔍', label: 'Weekly Focus', value: goalLabel)),
            ],
          ),
        ],
      ),
    );
  }
}

class _Item extends StatelessWidget {
  const _Item({required this.icon, required this.label, required this.value});
  final String icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(icon, style: const TextStyle(fontSize: 13)),
            const SizedBox(width: 5),
            Text(label, style: const TextStyle(fontSize: 11, color: ZitlasTokens.textMuted, fontWeight: FontWeight.w600)),
          ],
        ),
        const SizedBox(height: 3),
        Text(
          value,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: ZitlasTokens.textPrimary),
        ),
      ],
    );
  }
}
