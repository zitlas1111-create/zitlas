import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/network/api_exception.dart';
import 'models/diet_profile.dart';
import 'models/swap_result.dart';
import '../expert_dashboard/models/expert_models.dart' show ExpertProfile;
import 'data/diet_repository.dart';
import 'models/diet_calculations.dart';
import 'models/diet_day.dart';
import 'models/diet_meal.dart';
import 'models/diet_plan_content.dart';
import 'models/diet_review_request.dart';
import 'models/diet_storage.dart';
import 'models/expert_meal_modification.dart';

const _weekdayNames = [
  'monday',
  'tuesday',
  'wednesday',
  'thursday',
  'friday',
  'saturday',
  'sunday',
];

/// Aggregates the Diet feature's Firestore state and exposes the actions the
/// screen can take. Mirrors `diet.js`'s `init()`/`loadDietStorage()` load
/// chain and `DashboardController`'s subscription pattern — one live
/// listener on `users/{uid}` (which carries `dietPlan`, `planId`,
/// `calculations`, `dietPlanMaster`), one live listener on this athlete's
/// diet `review_requests`.
///
/// The `planId` fail-closed check (`_validateAndMaybeAdopt`) is the single
/// most important piece of behavior here: it is what stops a stale plan
/// (left over from before a goal reset) from ever being rendered or
/// silently kept, matching `validateDietStorage()` on the website exactly.
class DietController extends ChangeNotifier {
  DietController({required this.uid, required DietRepository repository})
    : _repository = repository { // ignore: prefer_initializing_formals
    _init();
  }

  final String uid;
  final DietRepository _repository;

  StreamSubscription<Map<String, dynamic>?>? _userDocSub;
  StreamSubscription<List<DietReviewRequest>>? _reviewsSub;
  bool _disposed = false;
  bool _dayAutoSelected = false;
  Map<String, dynamic>? _lastUserDoc;

  /// The athlete's permanent food profile. Read from the same live user-doc
  /// snapshot as everything else, so it can never drift from what's stored.
  DietProfile dietProfile = const DietProfile();

  /// True when the intake has never been completed — the Diet screen uses
  /// this to offer it once, and only once.
  bool get needsDietProfile => !dietProfile.isComplete;

  bool loading = true;
  Object? error;

  DietStorage? dietStorage;
  DietCalculations calculations = const DietCalculations();
  String? livePlanId;
  List<DietReviewRequest> reviews = const [];

  int selectedDayIndex = 0;

  bool swapping = false;
  Object? swapError;

  /// `NETWORK_ERROR | AUTH_ERROR | VALIDATION_ERROR | BACKEND_ERROR |
  /// AI_PROVIDER_ERROR | INVALID_RESPONSE` — debug-only classification of
  /// [swapError]; the UI stays the same friendly message regardless.
  String? swapErrorCategory;

  bool submittingReview = false;
  Object? reviewError;

  bool loadingExperts = false;
  List<ExpertProfile> approvedExperts = const [];

  /// `buildEffectivePlan()` applied on top of the validated wrapper — this,
  /// never `currentDietPlan` raw, is what the screen renders.
  DietPlanContent? get effectivePlan => dietStorage?.buildEffectivePlan();

  /// The most recent completed-but-not-yet-accepted review for THIS athlete
  /// whose `planId` doesn't contradict the live goal — matches the
  /// `planIdMismatch` guard from `getCompletedPlanReview()`: only excluded
  /// when both ids are present and differ, never on a missing id.
  DietReviewRequest? get pendingAcceptableReview {
    for (final r in reviews) {
      if (!r.isCompleted || r.athleteAccepted) continue;
      if (r.planId != null && livePlanId != null && r.planId != livePlanId) continue;
      return r;
    }
    return null;
  }

  void _init() {
    _userDocSub = _repository.watchUserDoc(uid).listen(
      _onUserDoc,
      onError: (Object e) {
        loading = false;
        error = e;
        _safeNotify();
      },
    );

    _reviewsSub = _repository.watchDietReviews(uid).listen(
      (list) {
        reviews = list;
        _safeNotify();
      },
      onError: (_) {
        // Review banner just stays hidden — non-critical for the core screen.
      },
    );
  }

  void _onUserDoc(Map<String, dynamic>? data) {
    _lastUserDoc = data;
    dietProfile = DietProfile.fromMap(
      (data?['dietProfile'] as Map?)?.cast<String, dynamic>(),
    );
    calculations = _repository.parseCalculations(data);
    livePlanId = data?['planId'] as String?;

    final rawPlan = (data?['dietPlan'] as Map?)?.cast<String, dynamic>();
    DietStorage? candidate;
    if (rawPlan != null) {
      if (DietStorage.isNewSchema(rawPlan)) {
        candidate = DietStorage.fromMap(rawPlan);
      } else if (rawPlan['days'] != null) {
        candidate = DietStorage.fromLegacyFlatPlan(
          DietPlanContent.fromMap(rawPlan),
          planId: livePlanId,
        );
      }
    }

    dietStorage = _validateAndMaybeAdopt(candidate);
    loading = false;
    error = null;
    _maybeAutoSelectDay();
    _safeNotify();

    if (dietStorage == null) {
      unawaited(_recoverFromMaster(data));
    }
  }

  /// `validateDietStorage()` on the website — fail-closed against the live
  /// `planId` goal-identity stamp:
  /// - stamped + matches live id (or live id not yet set) -> valid
  /// - stamped + contradicts live id -> stale, discard
  /// - unstamped + carries an expert layer -> untrustworthy, discard
  /// - unstamped + no expert layer + live id known -> adopt (stamp + persist)
  /// - unstamped + no expert layer + live id unknown -> keep as-is for now
  DietStorage? _validateAndMaybeAdopt(DietStorage? storage) {
    if (storage == null) return null;

    final storedId = storage.planId;
    final hasExpertLayer =
        storage.isExpertPlan || storage.expertModifications.values.any((m) => m.isNotEmpty);

    if (storedId != null) {
      if (livePlanId != null && storedId != livePlanId) {
        unawaited(_repository.discardDietStorage(uid).catchError((_) {}));
        return null;
      }
      return storage;
    }

    if (hasExpertLayer) {
      unawaited(_repository.discardDietStorage(uid).catchError((_) {}));
      return null;
    }

    if (livePlanId == null) return storage;

    final adopted = storage.copyWith(planId: livePlanId);
    unawaited(_repository.saveDietStorage(uid, adopted).catchError((_) {}));
    return adopted;
  }

  /// `_recoverFromMaster()` — one-time fallback to the immutable
  /// `dietPlanMaster` snapshot when no valid `dietPlan` wrapper survives
  /// validation. Only accepted when the master's own `planId` doesn't
  /// contradict the live goal (a master predating the `planId` feature has
  /// no such field and is accepted).
  Future<void> _recoverFromMaster(Map<String, dynamic>? data) async {
    try {
      final master = (data?['dietPlanMaster'] as Map?)?.cast<String, dynamic>();
      if (master == null) return;
      final masterPlanId = master['planId'] as String?;
      if (masterPlanId != null && livePlanId != null && masterPlanId != livePlanId) return;

      final plan = DietPlanContent.fromMap(master);
      if (!plan.hasDays) return;

      final recovered = DietStorage.fromLegacyFlatPlan(plan, planId: livePlanId ?? masterPlanId);
      await _repository.saveDietStorage(uid, recovered);
      if (_disposed) return;
      dietStorage = recovered;
      _maybeAutoSelectDay();
      _safeNotify();
    } catch (_) {
      // Recovery is best-effort; the empty state is the safe fallback.
    }
  }

  /// Defaults the day selector to today's weekday, matching the website's
  /// auto-select — but only the first time a plan becomes available, so it
  /// never yanks the athlete back to "today" after they've picked a day.
  void _maybeAutoSelectDay() {
    if (_dayAutoSelected) return;
    final days = effectivePlan?.days;
    if (days == null || days.isEmpty) return;
    _dayAutoSelected = true;
    final todayName = _weekdayNames[(DateTime.now().weekday - 1) % 7];
    final idx = days.indexWhere((d) => d.day.toLowerCase() == todayName);
    selectedDayIndex = idx >= 0 ? idx : 0;
  }

  void selectDay(int index) {
    selectedDayIndex = index;
    notifyListeners();
  }

  /// `callSwapMealApi()` — asks the backend for a replacement suggestion.
  /// Returns the raw `{foods, calories?, protein_g?}` swap so the caller can
  /// show a preview before committing via [acceptSwap]; never writes
  /// anything itself.
  Future<SwapResult?> requestMealSwap({
    required int dayIndex,
    required int mealIndex,
    required String reason,
    List<String> rejectedFoods = const [],
    List<Map<String, dynamic>> previousSuggestions = const [],
  }) async {
    final plan = effectivePlan;
    if (plan == null || dayIndex >= plan.days.length) return null;
    final day = plan.days[dayIndex];
    if (mealIndex >= day.meals.length) return null;
    final meal = day.meals[mealIndex];

    final assessment = (_lastUserDoc?['assessment'] as Map?)?.cast<String, dynamic>() ?? const {};
    final goal = (_lastUserDoc?['goal'] as Map?)?.cast<String, dynamic>();
    // The CONFIRMED `preferredDietRegion` (never live GPS) — the same field
    // Assessment generation reads, so a swap and a fresh plan always agree
    // on region. `assessment['location']` was a dead reference (Assessment
    // persists location under its own top-level `location` field, not
    // inside `assessment`) — this is the actual fix for "Swap Meal doesn't
    // receive region".
    final preferredRegion = _lastUserDoc?['preferredDietRegion'] as String?;
    final locationPayload = (preferredRegion == null || preferredRegion.isEmpty) ? null : {'state': preferredRegion};
    if (kDebugMode) debugPrint('[SWAP] requesting alternatives with region = ${preferredRegion ?? '(none)'}');

    swapping = true;
    swapError = null;
    swapErrorCategory = null;
    _safeNotify();
    try {
      final result = await _repository.swapMeal(
        mealName: meal.mealName,
        // Backend `meal_time: str = Field(default="")` is NOT optional —
        // sending JSON `null` here fails Pydantic validation with a 422
        // ("Could not get a suggestion" with zero detail visible to the
        // athlete). `meal.time` legitimately IS null for some plan entries,
        // so this must never be passed through raw.
        mealTime: meal.time ?? '',
        currentFoods: meal.foods,
        reason: reason,
        userProfile: {
          'fitness_goal': goal?['type'] ?? assessment['fitness_goal'],
          'uses_supplements': assessment['uses_supplements'],
          'location': locationPayload,
        },
        // The athlete's permanent food profile takes precedence over the
        // one-off assessment answers: it is the deliberate, editable record
        // of who cooks, what they can afford, and what they actually like,
        // and it is what makes the engine's kitchen-first ranking work.
        // Assessment values remain the fallback for athletes who predate it.
        lifestyleData: {
          'diet_preference': assessment['diet_preference'],
          'living_situation': assessment['living_situation'],
          'daily_budget': assessment['budget'],
          'disliked_foods': assessment['disliked_foods'],
          ...dietProfile.toLifestyleData(),
        },
        rejectedFoods: rejectedFoods,
        previousSuggestions: previousSuggestions,
        fitnessGoal: (goal?['type'] as String?) ?? (assessment['fitness_goal'] as String?) ?? 'general_fitness',
      );
      if (kDebugMode) {
        // Logged verbatim from the response so backend output and UI can be
        // compared line-for-line — the whole point of removing the LLM was
        // that what the engine ranked is what the athlete sees.
        debugPrint('[SWAP] current   = ${meal.foods.join(", ")}');
        debugPrint('[SWAP] returned  = ${result.options.length} options '
            'in ${result.elapsedMs}ms (llm=${result.llmUsed})');
        for (var i = 0; i < result.options.length; i++) {
          final o = result.options[i];
          debugPrint('[SWAP]   ${i + 1}. ${o.name} — ${o.calories}kcal '
              '${o.proteinG}P ${o.carbsG}C ${o.fatG}F | ${o.budgetLevel}');
          debugPrint('[SWAP]      reason: ${o.reason}');
        }
        debugPrint('[SWAP] match     = ${result.matchNote}');
      }
      return result;
    } catch (e) {
      swapError = e;
      swapErrorCategory = _classifySwapError(e);
      if (kDebugMode) {
        debugPrint('[SWAP] FAILED — category=$swapErrorCategory');
        if (e is ApiException) {
          debugPrint('[SWAP] status = ${e.statusCode ?? '(no response — transport failure)'}');
          debugPrint('[SWAP] message = ${e.message}');
          if (e.body != null) debugPrint('[SWAP] body = ${e.body}');
        } else {
          debugPrint('[SWAP] error = ${e.runtimeType}: $e');
        }
      }
      return null;
    } finally {
      swapping = false;
      _safeNotify();
    }
  }

  /// `NETWORK_ERROR | AUTH_ERROR | VALIDATION_ERROR | BACKEND_ERROR |
  /// AI_PROVIDER_ERROR | INVALID_RESPONSE` — surfaced to debug logs only;
  /// the athlete-facing message stays the same friendly copy regardless.
  static String _classifySwapError(Object e) {
    if (e is ApiException) {
      if (e.isNetworkError) return 'NETWORK_ERROR';
      if (e.isUnauthorized) return 'AUTH_ERROR';
      if (e.statusCode == 422 || e.statusCode == 400) return 'VALIDATION_ERROR';
      if (e.statusCode == 503) return 'AI_PROVIDER_ERROR';
      if (e.isServerError) return 'BACKEND_ERROR';
      return 'BACKEND_ERROR';
    }
    if (e is FormatException) return 'INVALID_RESPONSE';
    return 'NETWORK_ERROR';
  }

  /// `applySwappedMeal()` — commits a swap the athlete accepted. Always
  /// clears any prior `expertModifications` entry for THIS meal (a swap
  /// supersedes an expert edit on that meal, exactly like the website),
  /// then persists both `currentDietPlan` and the pruned modifications map.
  Future<void> acceptSwap({
    required int dayIndex,
    required int mealIndex,
    required Map<String, dynamic> swap,
  }) async {
    final storage = dietStorage;
    if (storage == null) return;
    final base = storage.currentDietPlan.hasDays ? storage.currentDietPlan : storage.originalDietPlan;
    if (dayIndex >= base.days.length) return;
    final day = base.days[dayIndex];
    if (mealIndex >= day.meals.length) return;
    final meal = day.meals[mealIndex];

    final newFoods = swap['foods'] is List
        ? (swap['foods'] as List).map((e) => e.toString()).toList()
        : meal.foods;

    final updatedMeal = meal.copyWith(
      foods: newFoods,
      calories: (swap['calories'] as num?) ?? meal.calories,
      proteinG: (swap['protein_g'] as num?) ?? meal.proteinG,
    );
    final newMeals = List<DietMeal>.from(day.meals)..[mealIndex] = updatedMeal;
    final newDay = day.copyWithMeals(newMeals);
    final newDays = List<DietDay>.from(base.days)..[dayIndex] = newDay;
    final newCurrentPlan = base.copyWithDays(newDays);

    final newMods = <String, Map<String, ExpertMealModification>>{
      for (final e in storage.expertModifications.entries) e.key: Map.of(e.value),
    };
    final dayKey = dayIndex.toString();
    newMods[dayKey]?.remove(meal.mealKey);
    if (newMods[dayKey]?.isEmpty == true) newMods.remove(dayKey);

    final newStorage = storage.copyWith(currentDietPlan: newCurrentPlan, expertModifications: newMods);
    await _repository.saveDietStorage(uid, newStorage);
  }

  Future<void> loadApprovedExperts() async {
    loadingExperts = true;
    _safeNotify();
    try {
      approvedExperts = await _repository.fetchApprovedExperts();
    } catch (_) {
      approvedExperts = const [];
    } finally {
      loadingExperts = false;
      _safeNotify();
    }
  }

  /// `submitVerifyRequest()` — sends the current effective plan (plus
  /// assessment/goal context already live from `users/{uid}`) to an expert
  /// for review. Writes to the SAME `review_requests` collection the
  /// Expert Dashboard's Reviews Inbox reads.
  Future<void> requestReview({
    required String expertId,
    required String expertName,
    required String expertRole,
    required String userName,
    num totalPrice = 0,
    bool isPremium = false,
  }) async {
    final plan = effectivePlan;
    if (plan == null) return;

    submittingReview = true;
    reviewError = null;
    _safeNotify();
    try {
      final assessment = (_lastUserDoc?['assessment'] as Map?)?.cast<String, dynamic>() ?? const {};
      final goal = (_lastUserDoc?['goal'] as Map?)?.cast<String, dynamic>();

      await _repository.submitReviewRequest(
        reviewId: _repository.newReviewRequestId(),
        userId: uid,
        userName: userName,
        expertId: expertId,
        expertName: expertName,
        expertRole: expertRole,
        planData: plan,
        assessmentData: assessment,
        profileBasics: {
          'goal_type': goal?['type'],
          'diet_preference': assessment['diet_preference'],
        },
        goal: goal,
        planId: livePlanId,
        totalPrice: totalPrice,
        isPremium: isPremium,
      );
    } catch (e) {
      reviewError = e;
    } finally {
      submittingReview = false;
      _safeNotify();
    }
  }

  /// `acceptExpertPlan()`/`_buildDietStorageFromReview()` — rebuilds the
  /// wrapper from a completed review: `expertModifications` come primarily
  /// from `mealChangeHistory`, then a scan over `reviewedDietPlan` for any
  /// `_edited` meal missed by history (or whose `newFoods` came back empty)
  /// fills the gap. `currentDietPlan` is reset to `originalDietPlan` — the
  /// expert layer is applied on top at render time by `buildEffectivePlan()`,
  /// never baked directly into `currentDietPlan`.
  Future<void> acceptExpertReview(DietReviewRequest review) async {
    final existing = dietStorage;
    final DietPlanContent original;
    if (existing != null && existing.originalDietPlan.hasDays) {
      original = existing.originalDietPlan;
    } else if (review.originalPlanData != null && review.originalPlanData!.hasDays) {
      original = review.originalPlanData!;
    } else {
      original = review.reviewedDietPlan ?? const DietPlanContent();
    }

    final mods = <String, Map<String, ExpertMealModification>>{};
    for (final entry in review.mealChangeHistory) {
      final dayKey = entry.dayIndex.toString();
      mods.putIfAbsent(dayKey, () => {});
      mods[dayKey]![entry.mealKey] = ExpertMealModification(
        modified: true,
        modifiedBy: entry.modifiedBy ?? review.expertName,
        modifiedAt: entry.modifiedAt ?? review.reviewedAt?.toIso8601String(),
        oldMeal: {
          'foods': entry.oldFoods,
          'calories': entry.oldCalories,
          'protein_g': entry.oldProtein,
        },
        newMeal: {
          'foods': entry.newFoods,
          'calories': entry.newCalories,
          'protein_g': entry.newProtein,
        },
      );
    }

    final reviewedPlan = review.reviewedDietPlan;
    if (reviewedPlan != null) {
      for (var dayIdx = 0; dayIdx < reviewedPlan.days.length; dayIdx++) {
        final day = reviewedPlan.days[dayIdx];
        for (final meal in day.meals) {
          if (!meal.edited) continue;

          final dayKey = dayIdx.toString();
          final existingMod = mods[dayKey]?[meal.mealKey];
          final existingNewFoods = existingMod?.newMeal?['foods'];
          final hasUsableNewFoods = existingNewFoods is List && existingNewFoods.isNotEmpty;
          if (hasUsableNewFoods) continue;

          DietMeal? originalMeal;
          if (dayIdx < original.days.length) {
            for (final m in original.days[dayIdx].meals) {
              if (m.mealKey == meal.mealKey) {
                originalMeal = m;
                break;
              }
            }
          }

          mods.putIfAbsent(dayKey, () => {});
          mods[dayKey]![meal.mealKey] = ExpertMealModification(
            modified: true,
            modifiedBy: review.expertName,
            modifiedAt: review.reviewedAt?.toIso8601String() ?? DateTime.now().toIso8601String(),
            oldMeal: originalMeal?.toModificationSnapshot(),
            newMeal: meal.toModificationSnapshot(),
          );
        }
      }
    }

    final newStorage = DietStorage(
      originalDietPlan: original,
      currentDietPlan: original,
      expertModifications: mods,
      isExpertPlan: true,
      expertName: review.expertName,
      expertId: review.expertId,
      expertNotes: review.expertNotes,
      reviewedAt: review.reviewedAt?.toIso8601String() ?? DateTime.now().toIso8601String(),
      reviewStatus: 'completed',
      planSource: 'expert_reviewed',
      reviewId: review.id,
      version: (existing?.version ?? 0) + 1,
      lastUpdated: DateTime.now().toIso8601String(),
      planId: review.planId ?? livePlanId,
    );

    await _repository.saveDietStorage(uid, newStorage);
    await _repository.markReviewAccepted(review.id);
  }

  void _safeNotify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _userDocSub?.cancel();
    _reviewsSub?.cancel();
    super.dispose();
  }
}
