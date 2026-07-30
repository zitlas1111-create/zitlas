import 'package:flutter/material.dart';

import '../../../../core/theme/zitlas_tokens.dart';
import '../../../workout/models/workout_day.dart';
import '../../../workout/models/workout_plan_content.dart';

/// `#s-workout` / `renderWorkout()` — read-only preview of the just-
/// generated workout plan (frequency/volume/split chips, summary, an
/// accordion of days/exercises incl. muscle-gain/transformation-only
/// `sets_volume_est`/`progression` fields), before the "Finish Setup" CTA.
class WorkoutPreviewView extends StatefulWidget {
  const WorkoutPreviewView({
    super.key,
    required this.plan,
    required this.isMuscleGain,
    required this.isTransformation,
    required this.onFinish,
  });

  final WorkoutPlanContent? plan;
  final bool isMuscleGain;
  final bool isTransformation;
  final VoidCallback onFinish;

  @override
  State<WorkoutPreviewView> createState() => _WorkoutPreviewViewState();
}

class _WorkoutPreviewViewState extends State<WorkoutPreviewView> {
  int? _openDay;

  bool get _showVolume => widget.isMuscleGain || widget.isTransformation;

  @override
  Widget build(BuildContext context) {
    final plan = widget.plan;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text.rich(
            TextSpan(
              children: [
                const TextSpan(text: 'Your '),
                TextSpan(text: 'Workout Plan', style: TextStyle(color: ZitlasTokens.primary)),
              ],
            ),
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: ZitlasTokens.textPrimary),
          ),
          const SizedBox(height: 4),
          Text(
            [
              plan?.planName ?? 'Personalised 7-Day Workout Plan',
              if (plan?.weeklyFrequency != null) plan!.weeklyFrequency!,
            ].join('  ·  '),
            style: const TextStyle(fontSize: 13, color: ZitlasTokens.textSecondary),
          ),
          const SizedBox(height: 16),
          if (plan == null || !plan.hasDays)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Text(
                'Workout plan could not be loaded.',
                textAlign: TextAlign.center,
                style: TextStyle(color: ZitlasTokens.textMuted, fontSize: 13),
              ),
            )
          else ...[
            _buildTargets(plan),
            if (plan.summary != null) ...[
              const SizedBox(height: 14),
              Text(plan.summary!, style: const TextStyle(fontSize: 13, color: ZitlasTokens.textSecondary, height: 1.4)),
            ],
            const SizedBox(height: 16),
            ...List.generate(plan.days.length, (i) => _buildDayAccordion(plan.days[i], i)),
          ],
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: widget.onFinish,
              style: ElevatedButton.styleFrom(
                backgroundColor: ZitlasTokens.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              child: const Text('Finish Setup →', style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTargets(WorkoutPlanContent plan) {
    final chips = <(String, String)>[
      (plan.weeklyFrequency ?? '5 days/week', 'Frequency'),
      _showVolume
          ? ('${plan.weeklyTrainingVolumeSets ?? '—'} sets', 'Weekly Volume')
          : ('${plan.weeklyCalorieBurnEst ?? '—'} kcal', 'Weekly Burn'),
      if (_showVolume && plan.trainingSplit != null) (plan.trainingSplit!, 'Split'),
    ];
    return Row(
      children: chips
          .map((c) => Expanded(
                child: Container(
                  margin: const EdgeInsets.only(right: 8),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(color: ZitlasTokens.bgCardLight, borderRadius: BorderRadius.circular(14)),
                  child: Column(
                    children: [
                      Text(c.$1, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: ZitlasTokens.textPrimary)),
                      Text(c.$2, style: const TextStyle(fontSize: 9.5, color: ZitlasTokens.textMuted)),
                    ],
                  ),
                ),
              ))
          .toList(),
    );
  }

  Widget _buildDayAccordion(WorkoutDay day, int i) {
    final open = _openDay == i;
    final isRest = day.isRest;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(color: ZitlasTokens.bgCard, borderRadius: BorderRadius.circular(16), boxShadow: kZitlasCardShadow),
      child: Column(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => setState(() => _openDay = open ? null : i),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(color: const Color(0x1FFF9800), borderRadius: BorderRadius.circular(8)),
                    child: Text(day.day.isEmpty ? 'Day ${i + 1}' : day.day, style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: ZitlasTokens.primaryDark)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(day.theme, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: ZitlasTokens.textPrimary)),
                  ),
                  Icon(open ? Icons.expand_less : Icons.expand_more, color: ZitlasTokens.textMuted),
                ],
              ),
            ),
          ),
          if (open)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      _typeChip(day.type ?? ''),
                      if (day.durationMinutes != null) _plainChip('${day.durationMinutes} min'),
                      if (_showVolume && day.setsVolumeEst != null)
                        _plainChip('${day.setsVolumeEst} sets')
                      else if (day.caloriesBurnedEst != null)
                        _plainChip('~${day.caloriesBurnedEst} kcal'),
                    ],
                  ),
                  const SizedBox(height: 10),
                  if (isRest)
                    const Text('Rest — no structured exercise today.', style: TextStyle(fontSize: 12.5, color: ZitlasTokens.textMuted))
                  else
                    ...day.exercises.map((ex) {
                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(color: ZitlasTokens.bgCardLight, borderRadius: BorderRadius.circular(12)),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(ex.name, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: ZitlasTokens.textPrimary)),
                            Text(
                              [
                                if (ex.sets != null) '${ex.sets} sets',
                                if (ex.repsOrDuration != null) ex.repsOrDuration!,
                                if (ex.restSeconds != null) '${ex.restSeconds}s rest',
                              ].join(' · '),
                              style: const TextStyle(fontSize: 11.5, color: ZitlasTokens.textSecondary),
                            ),
                            if (ex.tip != null) ...[
                              const SizedBox(height: 4),
                              Text('💡 ${ex.tip}', style: const TextStyle(fontSize: 11, color: ZitlasTokens.aiAccent)),
                            ],
                            if (ex.progression != null) ...[
                              const SizedBox(height: 4),
                              Text('📈 Progress: ${ex.progression}', style: const TextStyle(fontSize: 11, color: ZitlasTokens.successDark)),
                            ],
                          ],
                        ),
                      );
                    }),
                  if (day.dailyTip != null) ...[
                    const SizedBox(height: 4),
                    Text('💡 ${day.dailyTip}', style: const TextStyle(fontSize: 11.5, color: ZitlasTokens.textSecondary)),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _typeChip(String type) {
    final s = type.toLowerCase();
    final color = s.contains('rest') ? ZitlasTokens.textMuted : s.contains('recovery') ? ZitlasTokens.aiAccent : ZitlasTokens.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(10)),
      child: Text(type, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: color)),
    );
  }

  Widget _plainChip(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: ZitlasTokens.bgCardLight, borderRadius: BorderRadius.circular(10)),
      child: Text(text, style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: ZitlasTokens.textSecondary)),
    );
  }
}
