import 'package:flutter/material.dart';

import '../../../../core/theme/zitlas_tokens.dart';
import '../../models/workout_plan_content.dart';
import '../workout_visuals.dart';

/// `#wpWeekProgress` / `renderWeekProgress()`. `weekly_plan` days never
/// carry a `date`, so — exactly like the website — `completedCount` is
/// always 0 (`d.date && d.date < today` can never be true) and the percent
/// stays at 0% with no "done" dots; only the day matching today's weekday
/// name gets the active dot. This looks incomplete but is the real,
/// confirmed behavior of the live schema, not a bug introduced here.
class WorkoutWeekProgress extends StatelessWidget {
  const WorkoutWeekProgress({super.key, required this.plan});

  final WorkoutPlanContent plan;

  @override
  Widget build(BuildContext context) {
    final days = plan.days;
    final todayName = todaysWeekdayName();
    final goalLabel = plan.planName ?? 'Training Plan';

    var currentIdx = days.indexWhere((d) => d.day.toLowerCase() == todayName.toLowerCase());
    if (currentIdx == -1) currentIdx = 0;
    final currentDay = currentIdx < days.length ? days[currentIdx] : null;
    final currentLabel =
        currentDay == null ? 'Week Complete' : 'Day ${currentIdx + 1} — ${currentDay.theme}';

    return ZitlasCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('📊 ', style: TextStyle(fontSize: 14)),
              const Expanded(
                child: Text(
                  'Week Progress',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: ZitlasTokens.textPrimary),
                ),
              ),
              const Text(
                '0% complete',
                style: TextStyle(fontSize: 11.5, color: ZitlasTokens.textMuted, fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: const LinearProgressIndicator(
              value: 0,
              minHeight: 6,
              backgroundColor: ZitlasTokens.bgCardLight,
              valueColor: AlwaysStoppedAnimation(ZitlasTokens.primary),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: List.generate(days.length, (i) {
              final isToday = days[i].day.toLowerCase() == todayName.toLowerCase();
              return Padding(
                padding: const EdgeInsets.only(right: 6),
                child: Container(
                  width: 9,
                  height: 9,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isToday ? ZitlasTokens.primary : ZitlasTokens.border,
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 12),
          _MetaRow(label: 'Selected Goal', value: goalLabel),
          const SizedBox(height: 6),
          _MetaRow(label: 'Current Session', value: currentLabel),
        ],
      ),
    );
  }
}

class _MetaRow extends StatelessWidget {
  const _MetaRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(fontSize: 12, color: ZitlasTokens.textMuted)),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.right,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: ZitlasTokens.textPrimary),
          ),
        ),
      ],
    );
  }
}
