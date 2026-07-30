import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../dashboard_controller.dart';
import '../dashboard_visuals.dart';
import 'section_header.dart';
import 'widget_empty_state.dart';

/// `#trainingWidgetSection` / `renderTrainingWidget()`. `workoutPlan` isn't
/// written by any Flutter feature yet (AI plan generation is a later
/// phase), so this always shows the real empty state today; wired to
/// `DashboardController.hasWorkoutPlan` so it activates once that field
/// exists on `users/{uid}`.
class TrainingWidgetCard extends StatelessWidget {
  const TrainingWidgetCard({super.key});

  @override
  Widget build(BuildContext context) {
    final hasPlan = context.watch<DashboardController>().hasWorkoutPlan;

    return DashboardCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(
            emoji: '💪',
            title: "Today's Training",
            subtitle: hasPlan ? '' : 'Complete assessment to unlock',
            trailingText: 'View Weekly Plan →',
            onTrailingTap: () => context.go('/training'),
          ),
          if (!hasPlan)
            WidgetEmptyState(
              text: "Generate your AI workout plan to see today's training.",
              ctaLabel: 'Get Workout Plan →',
              onTap: () => context.push('/assessment'),
            ),
        ],
      ),
    );
  }
}
