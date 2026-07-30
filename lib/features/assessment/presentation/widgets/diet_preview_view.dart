import 'package:flutter/material.dart';

import '../../../../core/theme/zitlas_tokens.dart';
import '../../../diet/models/diet_day.dart';
import '../../../diet/models/diet_plan_content.dart';
import '../../models/assessment_calculations.dart';

/// `#s-diet` / `renderDiet()` — read-only preview of the just-generated plan
/// (targets row, summary, an accordion of days/meals, key rules) before the
/// athlete lands on the dashboard. This is NOT the full Diet feature (no
/// swap, no expert review) — it's the one-time onboarding preview the
/// website itself shows here; the real Diet tab is `features/diet`.
class DietPreviewView extends StatefulWidget {
  const DietPreviewView({
    super.key,
    required this.plan,
    required this.calculations,
    required this.isMuscleGain,
    required this.isTransformation,
    required this.onNext,
  });

  final DietPlanContent? plan;
  final AssessmentCalculations? calculations;
  final bool isMuscleGain;
  final bool isTransformation;
  final VoidCallback onNext;

  @override
  State<DietPreviewView> createState() => _DietPreviewViewState();
}

class _DietPreviewViewState extends State<DietPreviewView> {
  int? _openDay;

  @override
  Widget build(BuildContext context) {
    final plan = widget.plan;
    final calc = widget.calculations;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text.rich(
            TextSpan(
              children: [
                const TextSpan(text: 'Your '),
                TextSpan(text: 'Diet Plan', style: TextStyle(color: ZitlasTokens.primary)),
              ],
            ),
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: ZitlasTokens.textPrimary),
          ),
          const SizedBox(height: 4),
          Text(
            plan?.planName ?? 'Personalised 7-Day Diet Plan',
            style: const TextStyle(fontSize: 13, color: ZitlasTokens.textSecondary),
          ),
          const SizedBox(height: 16),
          if (plan == null || !plan.hasDays)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Text(
                'Diet plan could not be loaded.',
                textAlign: TextAlign.center,
                style: TextStyle(color: ZitlasTokens.textMuted, fontSize: 13),
              ),
            )
          else ...[
            if (calc != null) _buildTargets(calc),
            if (plan.summary != null) ...[
              const SizedBox(height: 14),
              Text(plan.summary!, style: const TextStyle(fontSize: 13, color: ZitlasTokens.textSecondary, height: 1.4)),
            ],
            const SizedBox(height: 16),
            ...List.generate(plan.days.length, (i) => _buildDayAccordion(plan.days[i], i)),
            if (plan.keyRules.isNotEmpty) ...[
              const SizedBox(height: 8),
              ZitlasCard(
                color: ZitlasTokens.bgCardLight,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Key Rules', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: ZitlasTokens.textPrimary)),
                    const SizedBox(height: 8),
                    ...plan.keyRules.map((r) => Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Text('• $r', style: const TextStyle(fontSize: 12.5, color: ZitlasTokens.textSecondary)),
                        )),
                  ],
                ),
              ),
            ],
          ],
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: widget.onNext,
              style: ElevatedButton.styleFrom(
                backgroundColor: ZitlasTokens.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              child: const Text('See Workout Plan →', style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTargets(AssessmentCalculations calc) {
    final deficitLabel = widget.isMuscleGain ? 'Surplus' : (widget.isTransformation ? 'Mild Deficit' : 'Deficit');
    final chips = [
      ('${calc.calorieTargetKcal.round()} kcal', 'Calories'),
      ('${calc.proteinTargetG.round()}g', 'Protein'),
      ('${calc.waterTargetLiters}L', 'Water'),
      ('${calc.calorieDeficitKcal.round()} kcal', deficitLabel),
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

  Widget _buildDayAccordion(DietDay day, int i) {
    final open = _openDay == i;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: ZitlasTokens.bgCard,
        borderRadius: BorderRadius.circular(16),
        boxShadow: kZitlasCardShadow,
      ),
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
                    child: Text(day.theme ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: ZitlasTokens.textPrimary)),
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
                children: day.meals.map((meal) {
                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(color: ZitlasTokens.bgCardLight, borderRadius: BorderRadius.circular(12)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(child: Text(meal.mealName, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: ZitlasTokens.textPrimary))),
                            if (meal.time != null) Text(meal.time!, style: const TextStyle(fontSize: 11, color: ZitlasTokens.textMuted)),
                          ],
                        ),
                        if (meal.calories != null || meal.proteinG != null)
                          Text('${meal.calories ?? 0} kcal · ${meal.proteinG ?? 0}g protein', style: const TextStyle(fontSize: 11, color: ZitlasTokens.textSecondary)),
                        const SizedBox(height: 4),
                        Text(meal.foods.join(', '), style: const TextStyle(fontSize: 12, color: ZitlasTokens.textSecondary, height: 1.3)),
                        if (meal.purpose != null) ...[
                          const SizedBox(height: 4),
                          Text('💡 ${meal.purpose}', style: const TextStyle(fontSize: 11, color: ZitlasTokens.aiAccent)),
                        ],
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
        ],
      ),
    );
  }
}
