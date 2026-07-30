import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../core/theme/zitlas_tokens.dart';
import '../../../auth/auth_state.dart';
import '../../data/workout_repository.dart';
import '../../workout_controller.dart';
import '../widgets/workout_coach_banner.dart';
import '../widgets/workout_context_bar.dart';
import '../widgets/workout_day_card.dart';
import '../widgets/workout_empty_state.dart';
import '../widgets/workout_hero.dart';
import '../widgets/workout_week_progress.dart';
import 'workout_day_screen.dart';

/// Native rebuild of `frontend/pages/dashboard/weekly-plan/weekly-plan.html`
/// + `weekly-plan.js` — the real Training (Weekly Plan) screen, replacing
/// the Phase-1 placeholder. Renders `WorkoutController.effectivePlan`
/// (coach override, else the expert-modification-applied AI plan) — never
/// a raw/unmodified plan. See docs/MIGRATION_INVENTORY.md for exactly which
/// website behaviors are confirmed dead code on the live schema (AI
/// Analysis strip, Weekly Review section, date-based day status/progress)
/// and therefore not built as permanently-unreachable UI.
class WorkoutScreen extends StatelessWidget {
  const WorkoutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = context.watch<AuthState>().profile?.uid;
    if (uid == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return ChangeNotifierProvider<WorkoutController>(
      key: ValueKey(uid),
      create: (_) => WorkoutController(
        uid: uid,
        repository: WorkoutRepository(FirebaseFirestore.instance),
      ),
      child: const _WorkoutBody(),
    );
  }
}

class _WorkoutBody extends StatelessWidget {
  const _WorkoutBody();

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<WorkoutController>();

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarIconBrightness: Brightness.dark,
        systemNavigationBarContrastEnforced: false,
        systemStatusBarContrastEnforced: false,
      ),
      child: Scaffold(
        backgroundColor: ZitlasTokens.bgStart,
        body: Stack(
          children: [
            const ZitlasPremiumBackground(),
            SafeArea(
              bottom: false,
              child: Column(
                children: [
                  const Padding(
                    padding: EdgeInsets.fromLTRB(20, 12, 20, 4),
                    child: Row(
                      children: [
                        Text('💪', style: TextStyle(fontSize: 22)),
                        SizedBox(width: 8),
                        Text(
                          'WEEKLY PLAN',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.4,
                            color: ZitlasTokens.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(child: _WorkoutContent(controller: controller)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WorkoutContent extends StatelessWidget {
  const _WorkoutContent({required this.controller});

  final WorkoutController controller;

  @override
  Widget build(BuildContext context) {
    if (controller.loading) {
      return const Center(child: CircularProgressIndicator());
    }

    final plan = controller.effectivePlan;
    if (plan == null || !plan.hasDays) {
      return WorkoutEmptyState(
        onStartAssessment: () => context.push('/assessment'),
        onBack: () => context.go('/dashboard'),
      );
    }

    final original = controller.workoutStorage?.originalWorkoutPlan;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        if (controller.isCoachManaged)
          WorkoutCoachBanner(
            coachName: controller.coachName ?? 'your coach',
            ended: controller.coachingEnded,
          ),
        WorkoutHero(plan: plan),
        const SizedBox(height: 16),
        WorkoutContextBar(plan: plan),
        const SizedBox(height: 16),
        WorkoutWeekProgress(plan: plan),
        const SizedBox(height: 16),
        const Row(
          children: [
            Text('📅 ', style: TextStyle(fontSize: 16)),
            Text(
              '7-Day Schedule',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: ZitlasTokens.textPrimary),
            ),
          ],
        ),
        const SizedBox(height: 10),
        ...List.generate(plan.days.length, (i) {
          final originalDay =
              (original != null && i < original.days.length) ? original.days[i] : null;
          return WorkoutDayCard(
            day: plan.days[i],
            index: i,
            originalDay: originalDay,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => WorkoutDayScreen(controller: controller, dayIndex: i),
              ),
            ),
          );
        }),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            onPressed: () => context.go('/dashboard'),
            style: OutlinedButton.styleFrom(
              foregroundColor: ZitlasTokens.textSecondary,
              padding: const EdgeInsets.symmetric(vertical: 13),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            child: const Text('← Back to Dashboard'),
          ),
        ),
      ],
    );
  }
}
