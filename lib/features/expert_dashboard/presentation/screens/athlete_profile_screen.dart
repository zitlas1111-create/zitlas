import 'package:flutter/material.dart';

import '../../../../core/theme/zitlas_tokens.dart';
import '../../../diet/models/diet_plan_content.dart';
import '../../../workout/models/workout_plan_content.dart';
import '../../data/expert_repository.dart';

/// Expert-facing "View Athlete Profile" — the gap the previous phase left
/// (`_openAthlete()` used to just open the chat thread as a stand-in).
/// Reads `users/{athleteId}` narrowed to goal, assessment survey, SWOT, and
/// the current Diet/Training plans — the same data `buildContextPackage()`
/// already sends TO the expert on every review/chat request, just surfaced
/// as a standing profile view rather than a one-time snapshot. Read-only:
/// editing happens through the dedicated review editors, not here.
class AthleteProfileScreen extends StatelessWidget {
  const AthleteProfileScreen({super.key, required this.repository, required this.athleteId, required this.athleteName});

  final ExpertRepository repository;
  final String athleteId;
  final String athleteName;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ZitlasTokens.bgStart,
      appBar: AppBar(
        backgroundColor: ZitlasTokens.bgCard,
        title: Text(athleteName, style: const TextStyle(color: ZitlasTokens.textPrimary, fontSize: 15, fontWeight: FontWeight.w800)),
      ),
      body: SafeArea(
        child: StreamBuilder<Map<String, dynamic>?>(
          stream: repository.watchAthleteProfile(athleteId),
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator(color: ZitlasTokens.primary));
            }
            final data = snap.data;
            if (data == null) {
              return const Center(child: Text('No profile data found for this athlete.', style: TextStyle(color: ZitlasTokens.textSecondary)));
            }

            final goal = (data['goal'] as Map?)?.cast<String, dynamic>();
            final assessment = (data['assessment'] as Map?)?.cast<String, dynamic>();
            final calc = (data['calculations'] as Map?)?.cast<String, dynamic>();
            final swot = (data['swot'] as Map?)?.cast<String, dynamic>();

            DietPlanContent? diet;
            final dietWrapper = data['dietPlan'] as Map?;
            if (dietWrapper != null) {
              final current = dietWrapper['currentDietPlan'] ?? dietWrapper['originalDietPlan'];
              if (current is Map) diet = DietPlanContent.fromMap(current.cast<String, dynamic>());
            }
            WorkoutPlanContent? workout;
            final workoutWrapper = data['workoutPlan'] as Map?;
            if (workoutWrapper != null) {
              final current = workoutWrapper['currentWorkoutPlan'] ?? workoutWrapper['originalWorkoutPlan'];
              if (current is Map) workout = WorkoutPlanContent.fromMap(current.cast<String, dynamic>());
            }

            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
              children: [
                if (goal != null) _card('Goal', [
                  _row('Type', '${goal['type'] ?? '—'}'),
                  _row('Target', '${goal['target_value'] ?? '—'}'),
                  _row('By', '${goal['end_date'] ?? '—'}'),
                ]),
                if (calc != null) _card('Fitness Snapshot', [
                  _row('BMI', '${calc['bmi'] ?? '—'} (${calc['bmi_category'] ?? '—'})'),
                  _row('TDEE', '${calc['tdee_kcal'] ?? '—'} kcal'),
                  _row('Calorie Target', '${calc['weight_loss_calories_kcal'] ?? calc['calorie_target_kcal'] ?? '—'} kcal'),
                  _row('Protein Target', '${calc['protein_target_g'] ?? '—'} g'),
                  _row('Steps Goal', '${calc['daily_steps_goal'] ?? '—'}'),
                ]),
                if (assessment != null) _card('Assessment', [
                  _row('Age', '${assessment['age'] ?? '—'}'),
                  _row('Gender', '${assessment['gender'] ?? '—'}'),
                  _row('Activity Level', '${assessment['activity_level'] ?? '—'}'),
                  _row('Diet Preference', '${assessment['diet_preference'] ?? '—'}'),
                ]),
                if (swot != null) _card('SWOT', [
                  _row('Archetype', '${swot['user_archetype'] ?? '—'}'),
                  _row('Summary', '${swot['summary'] ?? '—'}'),
                  _row('Priority Action', '${swot['priority_action'] ?? '—'}'),
                ]),
                if (diet != null && diet.hasDays)
                  _card('Diet Plan', [_row('Days', '${diet.days.length}'), _row('Daily Target', '${diet.dailyCaloriesTarget ?? '—'} kcal')]),
                if (workout != null && workout.hasDays)
                  _card('Training Plan', [_row('Days', '${workout.days.length}'), _row('Split', '${workout.trainingSplit ?? '—'}')]),
                if (goal == null && calc == null && assessment == null)
                  const Padding(
                    padding: EdgeInsets.only(top: 40),
                    child: Center(child: Text('This athlete hasn\'t completed their assessment yet.', style: TextStyle(color: ZitlasTokens.textSecondary))),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _card(String title, List<Widget> rows) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: ZitlasTokens.bgCard, borderRadius: BorderRadius.circular(14), border: Border.all(color: ZitlasTokens.borderSub)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: ZitlasTokens.textPrimary)),
          const SizedBox(height: 8),
          ...rows,
        ],
      ),
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 120, child: Text(label, style: const TextStyle(fontSize: 12, color: ZitlasTokens.textMuted))),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 12.5, color: ZitlasTokens.textPrimary))),
        ],
      ),
    );
  }
}
