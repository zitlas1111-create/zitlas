import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../auth/auth_state.dart';
import '../../dashboard_controller.dart';
import '../../data/dashboard_repository.dart';
import '../dashboard_visuals.dart';
import '../widgets/activity_card.dart';
import '../widgets/daily_score_card.dart';
import '../widgets/dashboard_header.dart';
import '../widgets/expert_review_promo_card.dart';
import '../widgets/goal_card.dart';
import '../widgets/greeting_section.dart';
import '../widgets/health_status_card.dart';
import '../widgets/quick_stats_row.dart';
import '../widgets/recent_chats_card.dart';
import '../widgets/swot_widget_card.dart';
import '../widgets/training_widget_card.dart';
import '../widgets/wellness_card.dart';

/// Native rebuild of `frontend/pages/dashboard/dashboard.html` +
/// `dashboard.js` + `dashboard.css` — the real Athlete Home dashboard,
/// replacing the Phase-1 placeholder. See docs/MIGRATION_INVENTORY.md §6
/// for exactly which sections are live-wired vs. intentionally deferred
/// (health-status recovery card, Zino floating assistant, real chat,
/// native step/Health-Connect data) to a later phase.
class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = context.watch<AuthState>().profile?.uid;
    if (uid == null) {
      // Router only ever lands an authenticated athlete here, but guard
      // anyway rather than crash if profile resolution is mid-flight.
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return ChangeNotifierProvider<DashboardController>(
      key: ValueKey(uid),
      create: (_) => DashboardController(
        uid: uid,
        repository: DashboardRepository(FirebaseFirestore.instance),
      ),
      child: const _DashboardBody(),
    );
  }
}

/// `.zn-fab` — 56px circular launcher carrying the Zino avatar.
class _ZinoFab extends StatelessWidget {
  const _ZinoFab({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [DashboardColors.primary, DashboardColors.primaryHover],
          ),
          boxShadow: [
            BoxShadow(
              color: DashboardColors.primary.withValues(alpha: 0.45),
              blurRadius: 18,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: const Icon(Icons.auto_awesome, color: Colors.white, size: 26),
      ),
    );
  }
}

class _DashboardBody extends StatefulWidget {
  const _DashboardBody();

  @override
  State<_DashboardBody> createState() => _DashboardBodyState();
}

/// Stateful only to own the step-refresh lifecycle — the layout below is
/// unchanged.
///
/// Steps are re-read on Dashboard open and again on every app resume, which
/// is what makes "lock the phone, walk, come back" show the new total: both
/// step sources keep counting while this process is backgrounded or dead, so
/// resuming just needs to ask them again. No timer polls in the background.
class _DashboardBodyState extends State<_DashboardBody> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<DashboardController>().refreshSteps();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      // Also covers the midnight case: a resume after 00:00 re-reads against
      // the NEW local day, so the ring starts the new day at its real count
      // and yesterday's final total is already archived in history.
      context.read<DashboardController>().refreshSteps();
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<DashboardController>();

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
        backgroundColor: DashboardColors.bgStart,
        body: Stack(
          children: [
            // `.zitlas-premium-bg` — homebg.png + light gradient overlay,
            // full-bleed behind the status bar (decorative layer only).
            Positioned.fill(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Image.asset('assets/images/homebg.png', fit: BoxFit.cover),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          DashboardColors.bgStart.withValues(alpha: 0.45),
                          DashboardColors.bgStart.withValues(alpha: 0.55),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // `#znFab` (assets/js/zino.js) — the Ask Zino launcher, pinned
            // bottom-right above the bottom nav on every authenticated page.
            Positioned(
              right: 18,
              bottom: 18,
              child: SafeArea(
                child: _ZinoFab(onTap: () => context.push('/zino')),
              ),
            ),
            SafeArea(
              bottom: false,
              child: Column(
                children: [
                  const DashboardHeader(),
                  Expanded(
                    child: RefreshIndicator(
                      color: DashboardColors.primary,
                      onRefresh: controller.refresh,
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                        children: const [
                          GreetingSection(),
                          GoalCard(),
                          SizedBox(height: 16),
                          ExpertReviewPromoCard(),
                          SizedBox(height: 16),
                          // #healthStatusMount — sits between the expert
                          // promo and the SWOT widget on dashboard.html.
                          HealthStatusCard(),
                          SizedBox(height: 16),
                          SwotWidgetCard(),
                          SizedBox(height: 16),
                          ActivityCard(),
                          SizedBox(height: 16),
                          DailyScoreCard(),
                          SizedBox(height: 16),
                          WellnessCard(),
                          SizedBox(height: 16),
                          TrainingWidgetCard(),
                          SizedBox(height: 16),
                          RecentChatsCard(),
                          SizedBox(height: 16),
                          QuickStatsRow(),
                        ],
                      ),
                    ),
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
