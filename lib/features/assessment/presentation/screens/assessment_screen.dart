import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../core/location/diet_region_repository.dart';
import '../../../../core/location/location_service.dart';
import '../../../../core/location/presentation/location_setup_flow.dart';
import '../../../../core/theme/zitlas_tokens.dart';
import '../../../auth/auth_state.dart';
import '../../assessment_controller.dart' hide AssessmentScreen;
import '../../assessment_controller.dart' as wizard show AssessmentScreen;
import '../../data/assessment_repository.dart';
import '../widgets/diet_preview_view.dart';
import '../widgets/done_view.dart';
import '../widgets/goal_selection_view.dart';
import '../widgets/processing_view.dart';
import '../widgets/question_view.dart';
import '../widgets/snapshot_view.dart';
import '../widgets/swot_view.dart';
import '../widgets/welcome_view.dart';
import '../widgets/workout_preview_view.dart';

/// Native rebuild of `frontend/pages/dashboard/ai-coach/ai-coach.html` +
/// `ai-coach.js` — the real 9-screen Assessment wizard (Welcome → Goal →
/// Assessment → Processing → Snapshot → SWOT → Diet Plan preview →
/// Workout Plan preview → Done), replacing the Phase-1 placeholder.
///
/// Two screens the code comment ("...Diet → Workout → Sources → CTA →
/// Done") implies exist do NOT: there is no `#s-sources` or upsell-CTA `div`
/// anywhere in `ai-coach.html` — the ₹149 expert-review upsell was
/// explicitly removed from onboarding per the website's own comment
/// ("no longer interrupts onboarding — offered later on the dashboard").
/// That comment is a stale artifact, not a live feature; nothing is
/// omitted here.
class AssessmentScreen extends StatelessWidget {
  const AssessmentScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = context.watch<AuthState>().profile?.uid;
    if (uid == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return ChangeNotifierProvider<AssessmentController>(
      key: ValueKey(uid),
      create: (_) => AssessmentController(
        uid: uid,
        repository: AssessmentRepository(firestore: FirebaseFirestore.instance),
        regionRepository: DietRegionRepository(firestore: FirebaseFirestore.instance),
      ),
      child: _AssessmentBody(uid: uid),
    );
  }
}

class _AssessmentBody extends StatefulWidget {
  const _AssessmentBody({required this.uid});
  final String uid;

  @override
  State<_AssessmentBody> createState() => _AssessmentBodyState();
}

class _AssessmentBodyState extends State<_AssessmentBody> {
  bool _locationFlowStarted = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_locationFlowStarted) return;
    _locationFlowStarted = true;
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeRunLocationSetup());
  }

  /// Part N (first-run logic) — checked directly against Firestore rather
  /// than the controller's own (possibly-not-yet-loaded) state, so a region
  /// saved on a previous device/session is never re-asked here. Runs once
  /// per screen instance; a dismissed/skipped flow (`region == null`) is
  /// still a clean no-op — Diet generation is never blocked on this.
  Future<void> _maybeRunLocationSetup() async {
    final regionRepo = DietRegionRepository(firestore: FirebaseFirestore.instance);
    final existing = await regionRepo.fetchOnce(widget.uid);
    if (existing != null) {
      if (mounted) context.read<AssessmentController>().setPreferredRegion(existing);
      return;
    }
    if (!mounted) return;
    final region = await runLocationSetupFlow(
      context,
      uid: widget.uid,
      locationService: LocationService(),
      regionRepo: regionRepo,
    );
    if (mounted) context.read<AssessmentController>().setPreferredRegion(region);
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AssessmentController>();

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
      child: PopScope(
        // Android back must never silently drop an in-progress Assessment —
        // route it through the same back handlers the UI's own back button
        // uses instead of popping the whole screen.
        canPop: controller.screen == wizard.AssessmentScreen.welcome,
        onPopInvokedWithResult: (didPop, _) {
          if (didPop) return;
          _handleSystemBack(controller);
        },
        child: Scaffold(
          backgroundColor: ZitlasTokens.bgStart,
          body: Stack(
            children: [
              const ZitlasPremiumBackground(),
              SafeArea(child: _buildScreen(context, controller)),
            ],
          ),
        ),
      ),
    );
  }

  void _handleSystemBack(AssessmentController controller) {
    switch (controller.screen) {
      case wizard.AssessmentScreen.welcome:
        break;
      case wizard.AssessmentScreen.goal:
        controller.startFromWelcome();
        break;
      case wizard.AssessmentScreen.assess:
        controller.backFromQuestion();
        break;
      case wizard.AssessmentScreen.processing:
      case wizard.AssessmentScreen.snapshot:
      case wizard.AssessmentScreen.swot:
      case wizard.AssessmentScreen.diet:
      case wizard.AssessmentScreen.workout:
      case wizard.AssessmentScreen.done:
        break; // no back navigation from these — matches the website (no back button rendered)
    }
  }

  Widget _buildScreen(BuildContext context, AssessmentController controller) {
    switch (controller.screen) {
      case wizard.AssessmentScreen.welcome:
        return WelcomeView(onStart: controller.startFromWelcome);

      case wizard.AssessmentScreen.goal:
        return GoalSelectionView(
          selectedGoal: controller.selectedGoal,
          onSelect: controller.selectGoal,
          onBack: controller.startFromWelcome,
          onNext: controller.startAssessment,
        );

      case wizard.AssessmentScreen.assess:
        final q = controller.currentQuestion;
        if (q == null) return const SizedBox.shrink();
        return QuestionView(
          key: ValueKey('${controller.selectedGoal}_${controller.currentQuestionIndex}'),
          question: q,
          questionIndex: controller.currentQuestionIndex,
          totalQuestions: controller.totalQuestions,
          existingAnswer: controller.answers[q.field],
          onBack: controller.backFromQuestion,
          onAnswerAndAdvance: controller.answerAndAdvance,
          onSubmitText: controller.submitTextAnswer,
          onSubmitMultiselect: controller.submitMultiselectAnswer,
          onSetAnswer: controller.setAnswer,
        );

      case wizard.AssessmentScreen.processing:
        return const ProcessingView();

      case wizard.AssessmentScreen.snapshot:
        return SnapshotView(controller: controller, onNext: controller.goToSwot);

      case wizard.AssessmentScreen.swot:
        return SwotView(swot: controller.apiResult?.swot, onNext: controller.goToDiet);

      case wizard.AssessmentScreen.diet:
        return DietPreviewView(
          plan: controller.apiResult?.dietPlan,
          calculations: controller.apiResult?.calculations,
          isMuscleGain: controller.isMuscleGain,
          isTransformation: controller.isTransformation,
          onNext: controller.goToWorkout,
        );

      case wizard.AssessmentScreen.workout:
        return WorkoutPreviewView(
          plan: controller.apiResult?.workoutPlan,
          isMuscleGain: controller.isMuscleGain,
          isTransformation: controller.isTransformation,
          onFinish: controller.goToDone,
        );

      case wizard.AssessmentScreen.done:
        return DoneView(onDone: () => context.go('/dashboard'));
    }
  }
}
