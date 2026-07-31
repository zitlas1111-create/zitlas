import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../../zino/tour/zino_tour_stops.dart';

import '../../../../core/theme/zitlas_tokens.dart';
import '../../../auth/auth_state.dart';
import '../../data/diet_repository.dart';
import '../../diet_controller.dart';
import '../widgets/diet_day_focus_card.dart';
import '../widgets/diet_day_selector.dart';
import '../widgets/diet_empty_state.dart';
import '../widgets/diet_expert_review_banner.dart';
import '../widgets/diet_meal_card.dart';
import '../widgets/diet_meal_swap_sheet.dart';
import '../widgets/diet_plan_header_card.dart';
import '../widgets/diet_request_review_sheet.dart';

/// Native rebuild of `frontend/pages/diet/diet.html` + `diet.js` — the real
/// Diet screen, replacing the Phase-1 placeholder. Renders
/// `DietController.effectivePlan` (never a raw/unmodified plan), the
/// expert-review accept banner when one is pending, and wires meal swap +
/// request-review actions to the same `review_requests`/`users/{uid}`
/// records the Expert Dashboard already operates on. See
/// docs/MIGRATION_INVENTORY.md for exactly which website behaviors are
/// deferred (Personal Coaching diet mode, Snap Meal photo logging) and why.
class DietScreen extends StatelessWidget {
  const DietScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = context.watch<AuthState>().profile?.uid;
    if (uid == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return ChangeNotifierProvider<DietController>(
      key: ValueKey(uid),
      create: (_) => DietController(
        uid: uid,
        repository: DietRepository(firestore: FirebaseFirestore.instance),
      ),
      child: const _DietBody(),
    );
  }
}

class _DietBody extends StatelessWidget {
  const _DietBody();

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<DietController>();
    final userName = context.watch<AuthState>().profile?.name ?? 'Athlete';

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
                        Text('🥗', style: TextStyle(fontSize: 22)),
                        SizedBox(width: 8),
                        Text(
                          'Diet Plan',
                          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: ZitlasTokens.textPrimary),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: _DietContent(controller: controller, userName: userName),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DietContent extends StatelessWidget {
  const _DietContent({required this.controller, required this.userName});

  final DietController controller;
  final String userName;

  @override
  Widget build(BuildContext context) {
    if (controller.loading) {
      return const Center(child: CircularProgressIndicator());
    }

    final plan = controller.effectivePlan;
    if (plan == null || !plan.hasDays) {
      return DietEmptyState(onStartAssessment: () => context.push('/assessment'));
    }

    final dayIndex = controller.selectedDayIndex.clamp(0, plan.days.length - 1);
    final day = plan.days[dayIndex];
    final pendingReview = controller.pendingAcceptableReview;
    final storage = controller.dietStorage;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        if (pendingReview != null)
          DietExpertReviewBanner(
            review: pendingReview,
            onAccept: () => controller.acceptExpertReview(pendingReview),
          ),
        KeyedSubtree(
          key: ZinoTourKeys.dietFocusCard,
          child: DietPlanHeaderCard(
            plan: plan,
            calculations: controller.calculations,
            isExpertPlan: storage?.isExpertPlan ?? false,
            expertName: storage?.expertName,
            onRequestReview: () =>
                showRequestReviewSheet(context, controller: controller, userName: userName),
          ),
        ),
        const SizedBox(height: 16),
        DietDaySelector(
          days: plan.days,
          selectedIndex: dayIndex,
          onSelect: controller.selectDay,
        ),
        const SizedBox(height: 16),
        DietDayFocusCard(day: day),
        if (day.theme != null || day.nutritionTip != null) const SizedBox(height: 16),
        ...List.generate(day.meals.length, (mealIndex) {
          final meal = day.meals[mealIndex];
          return DietMealCard(
            meal: meal,
            onSwap: () => showMealSwapSheet(
              context,
              controller: controller,
              dayIndex: dayIndex,
              mealIndex: mealIndex,
              meal: meal,
            ),
          );
        }),
      ],
    );
  }
}
