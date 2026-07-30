import 'dart:async';

import 'package:flutter/foundation.dart';

import 'data/dashboard_repository.dart';
import 'data/health_status_store.dart';
import 'models/activity_day_model.dart';
import 'models/activity_week.dart';
import 'models/daily_score.dart';
import 'models/goal_model.dart';
import 'models/health_status.dart';
import 'models/weight_entry.dart';

/// Aggregates every Dashboard data source and exposes plain fields for the
/// presentation widgets. Each fetch is isolated in its own try/catch —
/// mirrors `dashboard.js`'s `safeRun(name, fn)` wrapper, which guarantees
/// one section throwing never blocks the others from rendering (see
/// docs' §11 "dashboard states" requirement). No fake data is ever
/// substituted on failure — sections simply keep their empty/loading value.
class DashboardController extends ChangeNotifier {
  // Kept as a `repository:` named param (not a `this._repository`
  // initializing formal) so the public constructor API doesn't expose the
  // private field name it assigns to.
  DashboardController({
    required this.uid,
    required DashboardRepository repository,
    HealthStatusStore? healthStore,
  }) : _repository = repository, // ignore: prefer_initializing_formals
       _healthStore = healthStore ?? HealthStatusStore() {
    _init();
  }

  final String uid;
  final DashboardRepository _repository;
  final HealthStatusStore _healthStore;

  StreamSubscription<Map<String, dynamic>?>? _userDocSub;
  StreamSubscription<int>? _unreadSub;

  bool _disposed = false;

  // -- Live, from users/{uid} (matches cloud-sync.js's attachRealtime scope) --
  bool userDocLoading = true;
  Object? userDocError;
  GoalModel? goal;
  bool hasSwot = false;
  bool hasWorkoutPlan = false;
  bool hasDietPlan = false;
  bool isExpertPlan = false;
  String? displayName;
  String? photoUrl;
  int currentStreak = 0;
  int longestStreak = 0;

  // -- One-time reads --
  bool activityLoading = true;
  Object? activityError;
  ActivityDayModel? todayActivity;

  /// Archived day docs (today excluded) backing the Mon–Sun strip and the
  /// adaptive-goal suggestion.
  Map<String, ActivityDayModel> activityHistory = const {};

  /// The athlete's BASE daily step goal (`users/{uid}.dailyStepGoal`).
  int dailyStepGoal = 10000;

  bool weightLoading = true;
  List<WeightEntry> weightHistory = const [];

  double? mealScoreAvg;
  bool hasActiveCoaching = false;

  // -- Health Status / Recovery Mode (health-status.js) --
  HealthAdjustment? healthToday;
  bool healthTodayGreat = false;
  List<HealthHistoryEntry> healthHistory = const [];

  /// `baseStepsGoal()` — `zitlas_calculations.daily_steps_goal`, default 7000.
  int healthBaseStepsGoal = 7000;

  /// From `zitlas_precautions` — gate inputs for the safety rules.
  bool hasCriticalCondition = false;
  bool hasAsthma = false;

  // -- Live notification bell --
  int unreadNotifications = 0;

  /// `available(getWallet())` in wallet.js — spendable balance
  /// (`balance - reserved`) from `users/{uid}.wallet`. Backend-written only;
  /// the client never writes it (FIRESTORE_SECURITY_AUDIT.md V2).
  num walletAvailable = 0;

  DailyScoreResult? get dailyScore {
    final activity = todayActivity;
    if (activity == null) return null;
    return DailyScoreResult.compute(
      DailyScoreInputs(
        steps: activity.steps,
        stepsGoal: activity.goal,
        waterMl: activity.waterMl,
        waterGoalMl: activity.waterGoalMl,
        sleepHours: activity.sleepHours,
        mealScoreAvg: mealScoreAvg,
        workoutCompleted: activity.workoutCompleted,
      ),
    );
  }

  /// `ZitlasActivity.getWeeklySummary()` — the Mon–Sun strip.
  List<WeekDaySummary> get weeklySummary =>
      buildWeeklySummary(history: activityHistory, today: todayActivity);

  /// `getAdaptiveGoalSuggestion()` — suppressed during Recovery Mode, exactly
  /// like `renderStepCounterCard()` (`if (!d.recovery_mode && …)`).
  AdaptiveGoalSuggestion? get adaptiveGoalSuggestion {
    if (todayActivity?.recoveryMode ?? false) return null;
    return computeAdaptiveGoalSuggestion(history: activityHistory, goal: dailyStepGoal);
  }

  /// `getStatusMessage()` — all four branches.
  String get activityStatus => activityStatusMessage(todayActivity);

  /// Matches `expert-review-promo.js`'s `baseEligible()` +
  /// `refineWithCoachingStatus()`.
  bool get expertPromoEligible =>
      (hasDietPlan || hasWorkoutPlan) && !isExpertPlan && !hasActiveCoaching;

  void _init() {
    _userDocSub = _repository.watchUserDoc(uid).listen(
      (data) {
        userDocLoading = false;
        userDocError = null;
        _applyUserDoc(data);
        _safeNotify();
      },
      onError: (Object e) {
        userDocLoading = false;
        userDocError = e;
        _safeNotify();
      },
    );

    _unreadSub = _repository.watchUnreadNotificationCount(uid).listen(
      (count) {
        unreadNotifications = count;
        _safeNotify();
      },
      onError: (_) {
        // Bell badge just stays at its last known value — non-critical.
      },
    );

    unawaited(_loadOneTimeSections());
  }

  void _applyUserDoc(Map<String, dynamic>? data) {
    if (data == null) {
      goal = null;
      hasSwot = false;
      hasWorkoutPlan = false;
      hasDietPlan = false;
      isExpertPlan = false;
      displayName = null;
      photoUrl = null;
      currentStreak = 0;
      longestStreak = 0;
      dailyStepGoal = 10000;
      walletAvailable = 0;
      return;
    }
    goal = GoalModel.fromMap(data['goal'] as Map<String, dynamic>?);
    hasSwot = data['swot'] != null;
    final workoutPlan = data['workoutPlan'] as Map<String, dynamic>?;
    final dietPlan = data['dietPlan'] as Map<String, dynamic>?;
    hasWorkoutPlan = workoutPlan != null;
    hasDietPlan = dietPlan != null;
    isExpertPlan = (dietPlan?['isExpertPlan'] == true) || (workoutPlan?['isExpertPlan'] == true);
    final personalInfo = data['personalInfo'] as Map<String, dynamic>?;
    displayName = personalInfo?['fullName'] as String? ?? data['name'] as String?;
    photoUrl = personalInfo?['photo'] as String? ?? data['photo'] as String?;
    currentStreak = (data['currentStreak'] as num?)?.toInt() ?? 0;
    longestStreak = (data['longestStreak'] as num?)?.toInt() ?? 0;
    dailyStepGoal = (data['dailyStepGoal'] as num?)?.toInt() ?? 10000;

    // health-status.js reads these from `zitlas_calculations` /
    // `zitlas_precautions`, which cloud-sync mirrors onto the user doc.
    final calculations = data['calculations'] as Map<String, dynamic>?;
    healthBaseStepsGoal = (calculations?['daily_steps_goal'] as num?)?.toInt() ?? 7000;
    final precautions = data['precautions'] as Map<String, dynamic>?;
    hasCriticalCondition =
        (precautions?['directives'] as Map?)?['overall_severity'] == 'critical';
    final conditions = (precautions?['conditions'] as List?) ?? const [];
    hasAsthma = conditions.any((c) => c.toString().toLowerCase().contains('asthma'));

    final wallet = data['wallet'] as Map<String, dynamic>?;
    final balance = (wallet?['balance'] as num?) ?? 0;
    final reserved = (wallet?['reserved'] as num?) ?? 0;
    walletAvailable = balance - reserved < 0 ? 0 : balance - reserved;
  }

  Future<void> _loadOneTimeSections() async {
    await Future.wait([
      _loadActivity(),
      _loadActivityHistory(),
      _loadHealthStatus(),
      _loadWeightHistory(),
      _loadMealScore(),
      _loadCoachingStatus(),
    ]);
  }

  Future<void> _loadActivity() async {
    try {
      todayActivity = await _repository.fetchTodayActivity(uid);
      activityError = null;
    } catch (e) {
      activityError = e;
    } finally {
      activityLoading = false;
      _safeNotify();
    }
  }

  Future<void> _loadActivityHistory() async {
    try {
      activityHistory = await _repository.fetchActivityHistory(uid);
      _safeNotify();
    } catch (_) {
      // Weekly strip falls back to "missed" for unreadable days and the
      // adaptive suggestion simply doesn't appear — neither is critical.
    }
  }

  /// One-tap apply for the adaptive goal suggestion — mirrors `#sacApplyGoal`
  /// (`setDailyGoal` + re-render + toast). Never applied silently.
  Future<void> applyAdaptiveGoal(int goal) async {
    await _repository.setDailyStepGoal(uid, goal);
    dailyStepGoal = goal;
    _safeNotify();
    await _loadActivity();
  }

  Future<void> _loadWeightHistory() async {
    try {
      weightHistory = await _repository.fetchWeightHistory(uid);
    } catch (_) {
      weightHistory = const [];
    } finally {
      weightLoading = false;
      _safeNotify();
    }
  }

  Future<void> _loadMealScore() async {
    try {
      mealScoreAvg = await _repository.fetchTodayMealScoreAvg(uid);
      _safeNotify();
    } catch (_) {
      // Daily score simply omits the meal-quality input.
    }
  }

  Future<void> _loadCoachingStatus() async {
    try {
      hasActiveCoaching = await _repository.hasActiveCoaching(uid);
      _safeNotify();
    } catch (_) {
      // Defaults to false — expert promo may show when it shouldn't in the
      // rare case this read fails, which is the safer failure direction.
    }
  }

  Future<void> _loadHealthStatus() async {
    try {
      healthToday = await _healthStore.loadToday();
      healthTodayGreat = healthToday == null && await _healthStore.isTodayGreat();
      healthHistory = await _healthStore.loadHistory();
      _safeNotify();
    } catch (_) {
      // Card simply renders its neutral "how are you feeling?" state.
    }
  }

  /// `submitReport()` — computes the deterministic adjustment, persists it,
  /// mirrors the effective step goal onto today's activity doc, and fires the
  /// coach alert + self-notification. "Feeling great" clears any override
  /// instead of storing one.
  Future<void> submitHealthReport(HealthReport report) async {
    final adj = computeHealthAdjustments(
      report,
      baseStepsGoal: healthBaseStepsGoal,
      hasCriticalCondition: hasCriticalCondition,
      hasAsthma: hasAsthma,
    );

    if (adj.status == 'great') {
      await _healthStore.recordGreat();
      await _repository.applyRecoveryGoalToToday(
        uid,
        baseGoal: healthBaseStepsGoal,
        effectiveGoal: healthBaseStepsGoal,
        recoveryMode: false,
      );
    } else {
      await _healthStore.saveToday(adj);
      await _repository.applyRecoveryGoalToToday(
        uid,
        baseGoal: adj.oldStepsGoal,
        effectiveGoal: adj.effectiveStepsGoal,
        recoveryMode: true,
      );
      unawaited(_alertCoach(adj));
      unawaited(_notifySelf(adj));
    }

    await _loadHealthStatus();
    await _loadActivity();
  }

  /// `hsClearStatusChip` — clears ONLY today's override, restoring the
  /// original workout/diet/step goal.
  Future<void> clearHealthStatus() async {
    await _healthStore.clearToday();
    await _repository.applyRecoveryGoalToToday(
      uid,
      baseGoal: healthBaseStepsGoal,
      effectiveGoal: healthBaseStepsGoal,
      recoveryMode: false,
    );
    await _loadHealthStatus();
    await _loadActivity();
  }

  String _healthSummary(HealthAdjustment adj) {
    final buf = StringBuffer(healthStatusLabel(adj.status));
    if (adj.symptoms.isNotEmpty) buf.write(' — ${adj.symptoms.join(', ')}');
    if (adj.bodyParts.isNotEmpty) buf.write(' — ${adj.bodyParts.join(', ')}');
    if (adj.severity != null) buf.write(' (${adj.severity})');
    if (adj.painLevel != null && adj.painLevel != 0) {
      buf.write(' (pain ${adj.painLevel}/10)');
    }
    return buf.toString();
  }

  Future<void> _alertCoach(HealthAdjustment adj) async {
    try {
      final summary = _healthSummary(adj);
      final name = displayName ?? 'Athlete';
      final body = adj.safety
          ? '⚠ Advised to seek medical attention before exercising.'
          : "Today's workout: ${adj.workout?.title ?? 'unchanged'}. "
                'Diet: ${adj.diet?.title ?? 'unchanged'}. '
                'Steps: ${adj.oldStepsGoal} → ${adj.stepsGoalLabel}.';
      final chatText =
          '🩺 Health update — $summary.\n$body${adj.note.isEmpty ? '' : '\nNote: ${adj.note}'}';

      await _repository.sendHealthAlert(
        uid: uid,
        athleteName: name,
        summary: summary,
        chatText: chatText,
        alert: {
          'status': adj.status,
          'symptoms': adj.symptoms,
          'severity': adj.severity,
          'bodyParts': adj.bodyParts,
          'painLevel': adj.painLevel,
          'sleepHours': adj.sleepHours,
          'stressLevel': adj.stressLevel,
          'notes': adj.note,
          'safety': adj.safety,
          'newWorkout': adj.workout?.toMap(),
          'newDiet': adj.diet == null
              ? null
              : {'focus': adj.diet!.title, 'items': adj.diet!.items},
          'oldStepsGoal': adj.oldStepsGoal,
          'newStepsGoal': adj.stepsGoal ?? 'Rest',
        },
      );
    } catch (_) {
      // No coach, or the write failed — the local adjustment still stands.
    }
  }

  Future<void> _notifySelf(HealthAdjustment adj) async {
    try {
      final parts = [
        if (adj.workout != null) 'Workout: ${adj.workout!.title}',
        if (adj.diet != null) 'Diet: ${adj.diet!.title}',
      ];
      await _repository.sendSelfNotification(
        uid: uid,
        title: adj.safety
            ? '⚠ Seek medical attention before exercising'
            : "${healthStatusLabel(adj.status)} — today's plan adjusted",
        message: parts.join(' · '),
        type: 'health_status_${adj.status}',
        priority: adj.safety ? 'critical' : 'medium',
      );
    } catch (_) {
      // Non-critical.
    }
  }

  /// Pull-to-refresh: re-runs every one-time read. The live streams
  /// (user doc, unread count) don't need re-subscribing.
  Future<void> refresh() async {
    activityLoading = true;
    weightLoading = true;
    _safeNotify();
    await _loadOneTimeSections();
  }

  Future<void> setGoal(GoalModel newGoal) async {
    await _repository.saveGoal(uid, newGoal);
  }

  Future<void> resetGoal() async {
    await _repository.resetGoal(uid);
  }

  Future<void> logWater(int deltaMl) async {
    await _repository.logWater(uid, deltaMl);
    await _loadActivity();
  }

  Future<void> logSleep(double hours) async {
    await _repository.logSleep(uid, hours);
    await _loadActivity();
  }

  Future<void> logWeight(double kg) async {
    await _repository.logWeight(uid, kg);
    await _loadWeightHistory();
  }

  void _safeNotify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _userDocSub?.cancel();
    _unreadSub?.cancel();
    super.dispose();
  }
}
