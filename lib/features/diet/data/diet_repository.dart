import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/network/api_client.dart';
import '../../expert_dashboard/models/expert_models.dart' show ExpertProfile;
import '../models/diet_calculations.dart';
import '../models/diet_plan_content.dart';
import '../models/diet_review_request.dart';
import '../models/diet_storage.dart';

/// Firestore + backend access for the Diet feature. Every collection path
/// and field name here was traced from `frontend/pages/diet/diet.js`,
/// `frontend/assets/js/cloud-sync.js`, and
/// `frontend/pages/experts/modify-diet.js` — no new collections, no schema
/// changes. See docs/MIGRATION_INVENTORY.md for the full audit.
class DietRepository {
  DietRepository({required FirebaseFirestore firestore, ApiClient? apiClient})
    : _db = firestore,
      _api = apiClient ?? ApiClient();

  final FirebaseFirestore _db;
  final ApiClient _api;

  DocumentReference<Map<String, dynamic>> _userDoc(String uid) =>
      _db.collection('users').doc(uid);

  /// Live `users/{uid}` doc, narrowed to the fields Diet needs: `dietPlan`
  /// (the wrapper), `planId` (goal-identity stamp), `calculations`
  /// (targets), and `dietPlanMaster` (recovery snapshot) — all on the same
  /// doc, so one listener covers everything `cloud-sync.js`'s
  /// `attachRealtime()` would keep live for Diet.
  Stream<Map<String, dynamic>?> watchUserDoc(String uid) {
    return _userDoc(uid).snapshots().map((snap) => snap.data());
  }

  /// `saveDietStorage()` on the website (diet.js:331-334) — the single
  /// write path, always both the wrapper and a fresh `lastUpdated`.
  Future<void> saveDietStorage(String uid, DietStorage storage) {
    return _userDoc(uid).set({
      'dietPlan': storage.toMap(),
      'dietPlanUpdatedAt': DateTime.now().toIso8601String(),
    }, SetOptions(merge: true));
  }

  /// Explicit clear — mirrors `discardDietStorage()` (diet.js:280-286),
  /// used when a stored wrapper fails the `planId` fail-closed check.
  Future<void> discardDietStorage(String uid) {
    return _userDoc(uid).set({'dietPlan': null}, SetOptions(merge: true));
  }

  /// `review_requests` where `userId == uid && reviewType == 'diet'`. No
  /// `orderBy` — same reasoning as the website (diet.js/expert-dashboard.js
  /// both avoid the composite index requirement and sort client-side).
  Stream<List<DietReviewRequest>> watchDietReviews(String uid) {
    return _db
        .collection('review_requests')
        .where('userId', isEqualTo: uid)
        .where('reviewType', isEqualTo: 'diet')
        .snapshots()
        .map((snap) {
          final list =
              snap.docs.map((d) => DietReviewRequest.fromMap(d.id, d.data())).toList();
          list.sort((a, b) {
            final ad = a.createdAt, bd = b.createdAt;
            if (ad == null && bd == null) return 0;
            if (ad == null) return 1;
            if (bd == null) return -1;
            return bd.compareTo(ad);
          });
          return list;
        });
  }

  /// `submitVerifyRequest()` (diet.js:1617+) — the exact `review_requests`
  /// doc shape the Expert Dashboard's Reviews Inbox already reads.
  Future<void> submitReviewRequest({
    required String reviewId,
    required String userId,
    required String userName,
    required String expertId,
    required String expertName,
    required String expertRole,
    required DietPlanContent planData,
    required Map<String, dynamic> assessmentData,
    required Map<String, dynamic> profileBasics,
    Map<String, dynamic>? goal,
    String? planId,
    num totalPrice = 0,
    bool isPremium = false,
  }) {
    final now = DateTime.now().toIso8601String();
    return _db.collection('review_requests').doc(reviewId).set({
      'id': reviewId,
      'userId': userId,
      'athleteId': userId,
      'athleteName': userName,
      'userName': userName,
      'athlete_name': userName,
      'expertId': expertId,
      'expertName': expertName,
      'expertRole': expertRole,
      'reviewType': 'diet',
      'planData': planData.toMap(),
      'assessmentData': assessmentData,
      'profileBasics': profileBasics,
      'goal': goal,
      'planId': planId,
      'serviceType': 'verification',
      'totalPrice': totalPrice,
      'fee': totalPrice,
      'isPremium': isPremium,
      'paymentStatus': 'unpaid',
      'status': 'pending',
      'createdAt': now,
      'submittedAt': now,
      'completedAt': null,
      'serverTimestamp': FieldValue.serverTimestamp(),
    });
  }

  /// `POST /api/ai/swap-meal` — exact payload shape from `callSwapMealApi()`
  /// (diet.js:903-1036). Returns the raw `swap` object
  /// (`{foods, calories?, protein_g?}` at minimum).
  Future<Map<String, dynamic>> swapMeal({
    required String mealName,
    required String? mealTime,
    required List<String> currentFoods,
    required String reason,
    required Map<String, dynamic> userProfile,
    required Map<String, dynamic> lifestyleData,
    required List<String> rejectedFoods,
    required List<Map<String, dynamic>> previousSuggestions,
    required String fitnessGoal,
  }) async {
    // `previous_suggestions` on the backend is `list[list[str]]` (a plain
    // food-name list per prior suggestion), NOT the full suggestion object
    // Flutter accumulates for its own "Try Again" bookkeeping — sending the
    // raw maps would fail FastAPI's Pydantic validation (422) the moment a
    // second attempt includes one. Reshape to match the real contract.
    final previousSuggestionNames = previousSuggestions
        .map((s) => (s['foods'] is List ? (s['foods'] as List).map((e) => e.toString()).toList() : <String>[]))
        .toList();

    // The RAG lookup + LLM call this endpoint makes (1 retrieval + 1
    // generation, with a Groq -> Gemini -> OpenRouter fallback chain) can
    // occasionally run past the app's default 30s budget under provider
    // load — matches `generate-plan`'s same reasoning for its own longer
    // timeout. A slow swap is still a real answer; a plain 30s cutoff isn't.
    final res = await _api.post(
      '/api/ai/swap-meal',
      timeout: const Duration(seconds: 60),
      body: {
        'meal_name': mealName,
        'meal_time': mealTime,
        'current_foods': currentFoods,
        'reason': reason,
        'user_profile': userProfile,
        'lifestyle_data': lifestyleData,
        'rejected_foods': rejectedFoods,
        'previous_suggestions': previousSuggestionNames,
        'fitness_goal': fitnessGoal,
      },
    );

    if (res is Map) {
      final structured = res['structured'];
      if (structured is Map && structured['swap'] is Map) {
        return (structured['swap'] as Map).cast<String, dynamic>();
      }
      if (res['swap'] is Map) {
        return (res['swap'] as Map).cast<String, dynamic>();
      }
    }
    throw FormatException('Unexpected swap-meal response shape: ${res.runtimeType}');
  }

  /// Sourced directly from the `experts` collection (approved-only) rather
  /// than the website's `zitlas_nutritionists` localStorage cache — that
  /// cache is only populated by browsing the Experts marketplace page,
  /// which is still a placeholder in this app. Reading the same
  /// authoritative collection the marketplace itself reads from is more
  /// robust, not a schema change.
  Future<List<ExpertProfile>> fetchApprovedExperts({int limit = 10}) async {
    final snap = await _db
        .collection('experts')
        .where('approved', isEqualTo: true)
        .limit(limit)
        .get();
    return snap.docs.map((d) => ExpertProfile.fromMap(d.id, d.data())).toList();
  }

  /// Fresh Firestore-generated id for a new `review_requests` doc — mirrors
  /// the website's `crypto.randomUUID()`-style client-generated id, just
  /// sourced from the SDK instead.
  String newReviewRequestId() => _db.collection('review_requests').doc().id;

  /// Stamps `athleteAccepted: true` on the review doc once the athlete has
  /// applied its changes locally (`acceptExpertPlan()` does the same on
  /// the website) — suppresses the accept banner on future renders.
  Future<void> markReviewAccepted(String reviewId) {
    return _db.collection('review_requests').doc(reviewId).update({'athleteAccepted': true});
  }

  DietCalculations parseCalculations(Map<String, dynamic>? userDoc) {
    return DietCalculations.fromMap(
      (userDoc?['calculations'] as Map?)?.cast<String, dynamic>(),
    );
  }
}
