import 'dart:async';

import 'package:flutter/foundation.dart';

import 'data/workout_repository.dart';
import 'models/coach_training_plan.dart';
import 'models/expert_workout_modification.dart';
import 'models/workout_day.dart';
import 'models/workout_plan_content.dart';
import 'models/workout_review_request.dart';
import 'models/workout_storage.dart';

/// Aggregates the Training feature's Firestore state. Mirrors
/// `weekly-plan.js`'s `loadPlan()` / `training/day.js`'s
/// `loadPlanWithSource()` load chain (minus the confirmed-dead
/// `zitlas_roadmap` sport schema and the legacy `zitlas_expert_review`
/// branch — see docs/MIGRATION_INVENTORY.md Phase 6 for why) and
/// `DashboardController`/`DietController`'s subscription pattern.
///
/// Two behaviors are load-bearing and must not be "improved":
/// - The `planId` fail-closed check, identical to the Diet feature.
/// - Training auto-applies the newest expert review the moment its
///   `workoutChangeHistory` exists — there is NO "Accept Expert Changes"
///   button on the website's Training page (unlike Diet). The explicit
///   accept surface lives on the separate athlete profile/review page
///   (`cprofile.js`), out of scope for this feature. Reproducing an accept
///   button here would be inventing a control the real Training page
///   doesn't have.
class WorkoutController extends ChangeNotifier {
  WorkoutController({required this.uid, required WorkoutRepository repository})
    : _repository = repository { // ignore: prefer_initializing_formals
    _init();
  }

  final String uid;
  final WorkoutRepository _repository;

  StreamSubscription<Map<String, dynamic>?>? _userDocSub;
  StreamSubscription<List<WorkoutReviewRequest>>? _reviewsSub;
  StreamSubscription<PersonalCoachingRelationship?>? _coachingRelSub;
  StreamSubscription<CoachTrainingPlan?>? _coachPlanSub;
  StreamSubscription<bool>? _todayCompletedSub;
  StreamSubscription<Map<String, Map<String, dynamic>>>? _checkinsSub;
  bool _disposed = false;

  bool loading = true;
  Object? error;

  WorkoutStorage? workoutStorage;
  String? livePlanId;
  List<WorkoutReviewRequest> reviews = const [];

  PersonalCoachingRelationship? coachingRelationship;
  CoachTrainingPlan? coachTrainingPlan;
  bool _coachPlanSubscribed = false;

  bool todayWorkoutCompleted = false;
  Map<String, Map<String, dynamic>> workoutCheckins = const {};

  bool sendingToCoach = false;
  Object? sendError;

  /// `_pcShowsCoachPlan() && _pcCoachPlanIsCurrent(tr)` — the coach's
  /// training plan overrides the AI plan the moment this is true.
  bool get _coachOverrideActive {
    final rel = coachingRelationship;
    final plan = coachTrainingPlan;
    if (rel == null || !rel.showsCoachTrainingPlan) return false;
    if (plan == null || !plan.hasDays) return false;
    return plan.isCurrentFor(livePlanId);
  }

  bool get isCoachManaged => _coachOverrideActive;
  bool get coachingEnded => coachingRelationship?.status == 'ended';
  String? get coachName => coachTrainingPlan == null ? null : coachingRelationship?.coachName;

  /// The plan the screens actually render — coach override wins outright
  /// when active, otherwise the (expert-modification-applied) AI plan.
  WorkoutPlanContent? get effectivePlan {
    if (_coachOverrideActive) return coachTrainingPlan!.toPlanContent();
    return workoutStorage?.buildEffectivePlan();
  }

  bool get isExpertPlan => !_coachOverrideActive && (workoutStorage?.isExpertPlan ?? false);
  String? get expertName => workoutStorage?.expertName;

  /// Whether THIS athlete has an active (non-expired) Personal Coaching
  /// relationship — the gate for showing "Send Workout to Coach" at all,
  /// mirroring `ZitlasCoachingGate.evaluate(rel).active`.
  bool get canSendToCoach => coachingRelationship?.isActiveForCheckins ?? false;

  void _init() {
    _userDocSub = _repository.watchUserDoc(uid).listen(
      _onUserDoc,
      onError: (Object e) {
        loading = false;
        error = e;
        _safeNotify();
      },
    );

    _reviewsSub = _repository.watchWorkoutReviews(uid).listen(
      (list) {
        reviews = list;
        _maybeAutoSyncReview();
        _safeNotify();
      },
      onError: (_) {},
    );

    _coachingRelSub = _repository.watchCoachingRelationship(uid).listen(
      (rel) {
        coachingRelationship = rel;
        if ((rel?.showsCoachTrainingPlan ?? false) && !_coachPlanSubscribed) {
          _coachPlanSubscribed = true;
          _coachPlanSub = _repository.watchCoachTrainingPlan(uid).listen((plan) {
            coachTrainingPlan = plan;
            _safeNotify();
          });
        }
        _safeNotify();
      },
      onError: (_) {},
    );

    _todayCompletedSub = _repository.watchTodayWorkoutCompleted(uid).listen(
      (done) {
        todayWorkoutCompleted = done;
        _safeNotify();
      },
      onError: (_) {},
    );

    _checkinsSub = _repository.watchWorkoutCheckins(uid).listen(
      (map) {
        workoutCheckins = map;
        _safeNotify();
      },
      onError: (_) {},
    );
  }

  void _onUserDoc(Map<String, dynamic>? data) {
    livePlanId = data?['planId'] as String?;

    final rawPlan = (data?['workoutPlan'] as Map?)?.cast<String, dynamic>();
    WorkoutStorage? candidate;
    if (rawPlan != null) {
      if (WorkoutStorage.isNewSchema(rawPlan)) {
        candidate = WorkoutStorage.fromMap(rawPlan);
      } else if (rawPlan['weekly_plan'] != null ||
          rawPlan['days'] != null ||
          rawPlan['weekly_schedule'] != null ||
          rawPlan['workout_days'] != null) {
        candidate = WorkoutStorage.fromLegacyFlatPlan(
          WorkoutPlanContent.fromMap(rawPlan),
          planId: livePlanId,
        );
      }
    }

    workoutStorage = _validateAndMaybeAdopt(candidate);
    loading = false;
    error = null;
    _maybeAutoSyncReview();
    _safeNotify();
  }

  /// `loadPlan()`'s goal-identity gate — identical policy to the Diet
  /// feature's `_validateAndMaybeAdopt`, applied to workouts.
  WorkoutStorage? _validateAndMaybeAdopt(WorkoutStorage? storage) {
    if (storage == null) return null;

    final storedId = storage.planId;
    final hasExpertLayer = storage.isExpertPlan || storage.workoutModifications.isNotEmpty;

    if (storedId != null) {
      if (livePlanId != null && storedId != livePlanId) {
        unawaited(_repository.discardWorkoutStorage(uid).catchError((_) {}));
        return null;
      }
      return storage;
    }

    if (hasExpertLayer) {
      unawaited(_repository.discardWorkoutStorage(uid).catchError((_) {}));
      return null;
    }

    if (livePlanId == null) return storage;

    final adopted = storage.copyWith(planId: livePlanId);
    unawaited(_repository.saveWorkoutStorage(uid, adopted).catchError((_) {}));
    return adopted;
  }

  /// Ports `loadPlan()`'s "Sync workoutModifications to the NEWEST expert
  /// review" block (weekly-plan.js:330-376) exactly: runs whenever storage
  /// has no mods yet OR a newer review exists than what's stored, with NO
  /// status/athleteAccepted filter — any review carrying
  /// `workoutChangeHistory` for the current plan auto-applies. This is the
  /// Training page's actual behavior; it has no accept button of its own.
  void _maybeAutoSyncReview() {
    final storage = workoutStorage;
    if (storage == null) return;

    WorkoutReviewRequest? latest;
    for (final r in reviews) {
      if (r.workoutChangeHistory.isEmpty) continue;
      if (r.planId == null || livePlanId == null || r.planId != livePlanId) continue;
      if (latest == null) {
        latest = r;
        continue;
      }
      final a = r.reviewedAt ?? r.createdAt;
      final b = latest.reviewedAt ?? latest.createdAt;
      if (a != null && (b == null || a.isAfter(b))) latest = r;
    }
    if (latest == null) return;

    final storedTs = DateTime.tryParse(storage.reviewedAt ?? '');
    final reviewTs = latest.reviewedAt ?? latest.createdAt;
    final noMods = storage.workoutModifications.isEmpty;
    final isNewer = reviewTs != null && (storedTs == null || reviewTs.isAfter(storedTs));
    if (!noMods && !isNewer) return;

    final mods = <String, ExpertWorkoutModification>{};
    for (final change in latest.workoutChangeHistory) {
      mods[change.dayIndex.toString()] = ExpertWorkoutModification(
        modified: true,
        modifiedBy: change.modifiedBy ?? latest.expertName ?? 'Expert',
        modifiedAt: change.modifiedAt ?? latest.reviewedAt?.toIso8601String() ?? DateTime.now().toIso8601String(),
        oldWorkout: change.oldWorkout,
        newWorkout: change.newWorkout,
      );
    }

    final updated = storage.copyWith(
      workoutModifications: mods,
      isExpertPlan: true,
      expertName: latest.expertName ?? 'Expert',
      reviewedAt: latest.reviewedAt?.toIso8601String() ?? DateTime.now().toIso8601String(),
    );
    workoutStorage = updated;
    unawaited(_repository.saveWorkoutStorage(uid, updated).catchError((_) {}));
  }

  /// `_dtCompleteWorkout()`.
  Future<void> completeWorkout() => _repository.completeWorkout(uid);

  /// `_dtSendWorkoutToCoach(day)` — gated on [canSendToCoach]; callers
  /// should check that first (mirrors the button only rendering when the
  /// gate is active).
  Future<void> sendWorkoutToCoach({required WorkoutDay day, required String athleteName}) async {
    final rel = coachingRelationship;
    if (rel?.coachId == null || !canSendToCoach) return;

    sendingToCoach = true;
    sendError = null;
    _safeNotify();
    try {
      await _repository.sendWorkoutToCoach(
        uid: uid,
        coachId: rel!.coachId!,
        athleteName: athleteName,
        dayLabel: day.day,
        focus: day.theme,
        exercises: day.exercises
            .map((e) => {'name': e.name, 'sets': e.sets, 'reps': e.repsOrDuration})
            .toList(),
      );
    } catch (e) {
      sendError = e;
    } finally {
      sendingToCoach = false;
      _safeNotify();
    }
  }

  void _safeNotify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _userDocSub?.cancel();
    _reviewsSub?.cancel();
    _coachingRelSub?.cancel();
    _coachPlanSub?.cancel();
    _todayCompletedSub?.cancel();
    _checkinsSub?.cancel();
    super.dispose();
  }
}
