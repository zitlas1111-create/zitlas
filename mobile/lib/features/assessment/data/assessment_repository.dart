import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../../../core/network/api_client.dart';
import '../../../core/util/json_coerce.dart';
import '../../diet/models/diet_plan_content.dart';
import '../../diet/models/diet_storage.dart';
import '../../workout/models/workout_plan_content.dart';
import '../../workout/models/workout_storage.dart';
import '../models/assessment_calculations.dart';
import '../models/assessment_swot.dart' show AssessmentSwot, SwotItem;

/// The full parsed `/api/assessment/generate-plan` response.
class AssessmentResult {
  const AssessmentResult({
    required this.assessment,
    required this.calculations,
    required this.swot,
    required this.dietPlan,
    required this.workoutPlan,
    required this.precautions,
    required this.medicalConditionsDetected,
  });

  final Map<String, dynamic> assessment;
  final AssessmentCalculations calculations;
  final AssessmentSwot swot;
  final DietPlanContent? dietPlan;
  final WorkoutPlanContent? workoutPlan;

  /// `data.precautions` — deterministic (never LLM-generated) strings from
  /// `services/medical_conditions.py`. Empty for healthy users.
  final List<String> precautions;
  final List<String> medicalConditionsDetected;

  /// The four sections are parsed **independently** so a defect in one can't
  /// destroy the others.
  ///
  /// This mirrors the backend's own orchestration: `generate_plan` wraps the
  /// diet and workout LLM steps in separate `try/except` blocks and returns
  /// `diet_plan: null` / `workout_plan: null` on failure while still
  /// returning a full `calculations` + `swot` (routes/assessment.py:1347-1375).
  /// Parsing them eagerly in one expression threw that isolation away — a
  /// single malformed exercise anywhere in the 7-day workout tree took the
  /// completed assessment, targets and SWOT down with it and surfaced as
  /// "generate-plan FAILED", which is exactly the bug that was reported.
  ///
  /// `calculations` and `swot` are required: they come from
  /// `run_assessment()`, pure Python arithmetic that either succeeds or
  /// raises 422 — so their absence in a 200 response is a genuinely
  /// malformed reply and is reported as such rather than silently defaulted.
  factory AssessmentResult.fromMap(Map<String, dynamic> m) {
    final calcMap = asMap(m['calculations']);
    final swotMap = asMap(m['swot']);
    if (calcMap == null || swotMap == null) {
      throw const FormatException(
        'generate-plan response is missing calculations/swot',
      );
    }

    return AssessmentResult(
      assessment: asMap(m['assessment']) ?? const {},
      calculations: AssessmentCalculations.fromMap(calcMap),
      swot: AssessmentSwot.fromMap(swotMap),
      dietPlan: _parseSection('diet_plan', m['diet_plan'], DietPlanContent.fromMap),
      workoutPlan: _parseSection('workout_plan', m['workout_plan'], WorkoutPlanContent.fromMap),
      precautions: asStringList(m['precautions']),
      medicalConditionsDetected: asStringList(m['medical_conditions_detected']),
    );
  }

  /// Parses one optional plan section. A `null`/absent section is a normal
  /// backend outcome (LLM step failed server-side). A section that is present
  /// but unparseable is logged and treated as absent — the athlete keeps
  /// everything else instead of losing the whole assessment. Nothing is
  /// fabricated: the section simply stays `null` and the UI shows its real
  /// "could not be loaded" state.
  static T? _parseSection<T>(
    String key,
    dynamic raw,
    T Function(Map<String, dynamic>) parse,
  ) {
    final map = asMap(raw);
    if (map == null) return null;
    try {
      return parse(map);
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('[ASSESSMENT] "$key" present but unparseable — ${e.runtimeType}: $e');
        debugPrint('[ASSESSMENT] "$key" keys: ${map.keys.toList()}');
        debugPrintStack(stackTrace: st, maxFrames: 8);
      }
      return null;
    }
  }
}

/// Backend + Firestore access for the Assessment feature. The calculation
/// engine, SWOT engine, and diet/workout generation all stay server-side
/// (`POST /api/assessment/generate-plan`) — this class only builds the
/// request payload, parses the response, and persists it to the SAME
/// `users/{uid}` fields the Dashboard/Diet/Training features already read
/// (traced from `saveToLocalStorage()` + `ZitlasCloudSync.saveBulk()` in
/// `frontend/pages/dashboard/ai-coach/ai-coach.js`). No new schema.
class AssessmentRepository {
  AssessmentRepository({required FirebaseFirestore firestore, ApiClient? apiClient})
    : _db = firestore,
      _api = apiClient ?? ApiClient();

  final FirebaseFirestore _db;
  final ApiClient _api;

  DocumentReference<Map<String, dynamic>> _userDoc(String uid) => _db.collection('users').doc(uid);

  /// `callGeneratePlan()` — the one and only place LLM/RAG/calculation logic
  /// is invoked; this is a thin pass-through. `generate-plan` runs 2 RAG
  /// retrievals + 2 LLM generations server-side, which is measurably slower
  /// than the app's default endpoint timeout, so this call gets a longer,
  /// endpoint-specific budget.
  Future<AssessmentResult> generatePlan(Map<String, dynamic> payload) async {
    final res = await _api.post(
      '/api/assessment/generate-plan',
      body: payload,
      timeout: const Duration(seconds: 90),
    );
    return AssessmentResult.fromMap((res as Map).cast<String, dynamic>());
  }

  /// `saveToLocalStorage()`'s Firestore half — one merge write covering
  /// every field `ZitlasCloudSync.saveBulk()` sent: `goal`, `survey`
  /// (raw answers), `calculations`, `swot`, `assessment`, `dietPlan`
  /// (wrapped exactly like `DietStorage.fromAiPlan`), `workoutPlan`
  /// (wrapped exactly like `WorkoutStorage.fromAiPlan`), `precautions`,
  /// `planGeneratedAt`, the fresh `planId` stamp, and the immutable
  /// `dietPlanMaster`/`workoutPlanMaster` snapshots.
  ///
  /// Stamping a NEW `planId` here is what makes the Diet/Training features'
  /// existing fail-closed `planId` gates automatically treat any prior
  /// expert review/modification as stale on next load — no separate
  /// "clear expert review keys" step is needed the way the website's
  /// localStorage-based `saveToLocalStorage()` required, because Flutter
  /// never had a local cache of those reviews to begin with; Firestore
  /// `review_requests` docs themselves are untouched (matching the website,
  /// which also never deletes the underlying `review_requests` doc — only
  /// its local mirrors).
  Future<String> saveAssessmentResult({
    required String uid,
    required Map<String, dynamic> answers,
    required Map<String, dynamic> goal,
    required AssessmentResult result,
    Map<String, dynamic>? location,
  }) async {
    final planId = 'plan_${DateTime.now().millisecondsSinceEpoch}';
    final now = DateTime.now().toIso8601String();

    final dietStorage = result.dietPlan != null
        ? DietStorage.fromAiPlan(result.dietPlan!, planId: planId)
        : null;
    final workoutStorage = result.workoutPlan != null
        ? WorkoutStorage.fromAiPlan(result.workoutPlan!, planId: planId)
        : null;

    final precautionsMap = result.precautions.isNotEmpty
        ? {
            'precautions': result.precautions,
            'conditions': result.medicalConditionsDetected,
          }
        : null;

    await _userDoc(uid).set({
      'goal': goal,
      'survey': answers,
      'calculations': result.calculations.toMap(),
      'swot': _swotToMap(result.swot),
      'assessment': result.assessment,
      // `zitlas_location` on web — cross-device region for future plan
      // regenerations, per `ZitlasCloudSync.save('location', loc)`. Never
      // overwritten with an empty/no-op value.
      if (location != null && location.isNotEmpty) 'location': location,
      if (dietStorage != null) 'dietPlan': dietStorage.toMap(),
      if (workoutStorage != null) 'workoutPlan': workoutStorage.toMap(),
      'precautions': precautionsMap,
      'planGeneratedAt': now,
      'planId': planId,
      if (result.dietPlan != null)
        'dietPlanMaster': {'plan': result.dietPlan!.toMap(), 'planId': planId, 'generatedAt': now},
      if (result.workoutPlan != null)
        'workoutPlanMaster': {'plan': result.workoutPlan!.toMap(), 'planId': planId, 'generatedAt': now},
    }, SetOptions(merge: true));

    return planId;
  }

  Map<String, dynamic> _swotToMap(AssessmentSwot swot) {
    List<Map<String, dynamic>> itemsOf(List<SwotItem> items) =>
        items.map((i) => {'title': i.title, if (i.detail != null) 'detail': i.detail}).toList();
    return {
      'user_archetype': swot.userArchetype,
      'summary': swot.summary,
      'priority_action': swot.priorityAction,
      'scores': {
        'nutrition': swot.scores.nutrition,
        'activity': swot.scores.activity,
        'sleep': swot.scores.sleep,
        'habits': swot.scores.habits,
        'mindset': swot.scores.mindset,
        'consistency': swot.scores.consistency,
      },
      'swot': {
        'strengths': itemsOf(swot.strengths),
        'weaknesses': itemsOf(swot.weaknesses),
        'opportunities': itemsOf(swot.opportunities),
        'threats': itemsOf(swot.threats),
      },
    };
  }
}
