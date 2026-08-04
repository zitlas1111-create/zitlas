import 'package:flutter/material.dart';

import '../../../../core/theme/zitlas_tokens.dart';
import '../../models/workout_plan_content.dart';

/// `#wpHero` / `renderHero()` — role badge, title, goal/ambition tags, and
/// the 3 stat tiles. `dateRange` and the "AI Enhanced" badge are never
/// populated for the AI-generated `weekly_plan` schema (no per-day `date`,
/// no `aiEnhanced` flag anywhere in the backend response) and are therefore
/// omitted rather than built as permanently-dead conditionals — confirmed
/// via `backend/routes/assessment.py`.
class WorkoutHero extends StatelessWidget {
  const WorkoutHero({super.key, required this.plan});

  final WorkoutPlanContent plan;

  @override
  Widget build(BuildContext context) {
    final goalLabel = plan.planName ?? 'Training Plan';
    const ambitionLabel = 'Peak Performance'; // ambition is never set by the backend

    final totalMinutes = plan.days.fold<num>(0, (s, d) => s + (d.durationMinutes ?? 0));
    final totalHrs = totalMinutes > 0 ? (totalMinutes / 60).toStringAsFixed(1) : '—';

    return ZitlasCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: ZitlasTokens.bgCardLight,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: ZitlasTokens.border),
            ),
            child: const Text(
              'Member',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: ZitlasTokens.textSecondary),
            ),
          ),
          const SizedBox(height: 12),
          const Text.rich(
            TextSpan(
              children: [
                TextSpan(text: 'Your 7-Day\n'),
                TextSpan(text: 'Wellness Plan'),
              ],
            ),
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: ZitlasTokens.textPrimary, height: 1.15),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _Tag('🎯 $goalLabel'),
              _Tag('🏆 $ambitionLabel'),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _Stat(num: '7', label: 'Sessions'),
              _Stat(num: totalHrs, label: 'Hours'),
              const _Stat(num: '10', label: 'Sections/Day'),
            ],
          ),
        ],
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0x1FFF9800),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0x33FF9800)),
      ),
      child: Text(
        text,
        style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: ZitlasTokens.primaryDark),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.num, required this.label});
  final String num;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(num, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: ZitlasTokens.textPrimary)),
          const SizedBox(height: 2),
          Text(label, style: const TextStyle(fontSize: 10.5, color: ZitlasTokens.textMuted, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
