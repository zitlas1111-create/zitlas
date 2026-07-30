import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/util/json_coerce.dart';
import 'diet_plan_content.dart';

DateTime? _asDate(dynamic v) {
  if (v is Timestamp) return v.toDate();
  if (v is String) return DateTime.tryParse(v);
  return null;
}

/// One entry in a review's `mealChangeHistory` — the diff record an expert
/// leaves behind when editing a meal (`buildMealChangeHistory()` /
/// `buildHistory()` on the website). Used both to build the effective
/// `expertModifications` map on accept, and to show a "what changed"
/// summary to the athlete.
class MealChangeEntry {
  const MealChangeEntry({
    required this.dayIndex,
    required this.mealName,
    this.dayLabel,
    this.oldFoods = const [],
    this.newFoods = const [],
    this.oldCalories,
    this.newCalories,
    this.oldProtein,
    this.newProtein,
    this.reason,
    this.modifiedBy,
    this.modifiedAt,
  });

  final int dayIndex;
  final String mealName;
  final String? dayLabel;
  final List<String> oldFoods;
  final List<String> newFoods;
  final num? oldCalories;
  final num? newCalories;
  final num? oldProtein;
  final num? newProtein;
  final String? reason;
  final String? modifiedBy;
  final String? modifiedAt;

  String get mealKey => mealName.toLowerCase().trim().replaceAll(RegExp(r'[^a-z0-9]+'), '_');

  factory MealChangeEntry.fromMap(Map<String, dynamic> m) {
    return MealChangeEntry(
      dayIndex: asInt(m['dayIndex']) ?? 0,
      mealName: asText(m['mealName']) ?? 'Meal',
      dayLabel: asText(m['dayLabel']),
      oldFoods: asStringList(m['oldFoods']),
      newFoods: asStringList(m['newFoods']),
      oldCalories: asNum(m['oldCalories']),
      newCalories: asNum(m['newCalories']),
      oldProtein: asNum(m['oldProtein']),
      newProtein: asNum(m['newProtein']),
      reason: asText(m['reason']),
      modifiedBy: asText(m['modifiedBy']),
      modifiedAt: asText(m['modifiedAt']),
    );
  }
}

/// A `review_requests` doc where `reviewType == 'diet'`. Same collection,
/// same fields the Expert Dashboard's Reviews Inbox already reads/writes
/// (`lib/features/expert_dashboard/models/expert_models.dart`'s
/// `ReviewRequest`) — this is a diet-specific view over the identical
/// Firestore records, not a parallel schema.
class DietReviewRequest {
  const DietReviewRequest({
    required this.id,
    required this.status,
    this.userId,
    this.expertId,
    this.expertName,
    this.planId,
    this.isPremium = false,
    this.totalPrice,
    this.createdAt,
    this.reviewedAt,
    this.expertNotes,
    this.athleteAccepted = false,
    this.mealChangeHistory = const [],
    this.reviewedDietPlan,
    this.originalPlanData,
  });

  final String id;

  /// `pending | in_progress|expert_reviewing | review_completed|completed | rejected`
  final String status;
  final String? userId;
  final String? expertId;
  final String? expertName;
  final String? planId;
  final bool isPremium;
  final num? totalPrice;
  final DateTime? createdAt;
  final DateTime? reviewedAt;
  final String? expertNotes;
  final bool athleteAccepted;
  final List<MealChangeEntry> mealChangeHistory;

  /// The expert-edited plan, present once the review is complete. Its
  /// individual meals may carry `_edited: true` — scanned as a supplement/
  /// override to `mealChangeHistory` when building the accepted wrapper,
  /// exactly like `_buildDietStorageFromReview()`/`acceptExpertPlan()`.
  final DietPlanContent? reviewedDietPlan;

  /// `planData` on the raw doc — the plan snapshot as it was when the
  /// review was requested (used as `originalDietPlan` fallback on accept).
  final DietPlanContent? originalPlanData;

  bool get isCompleted => status == 'review_completed' || status == 'completed';
  bool get isPending => status == 'pending';
  bool get isInProgress => status == 'in_progress' || status == 'expert_reviewing';
  bool get isRejected => status == 'rejected';

  factory DietReviewRequest.fromMap(String id, Map<String, dynamic> m) {
    final rawHistory = m['mealChangeHistory'] as List?;
    Map<String, dynamic>? asMap(dynamic v) => v is Map ? v.cast<String, dynamic>() : null;

    // `planData` may itself be wrapper-shaped (originalDietPlan/currentDietPlan)
    // per cprofile.js's unwrap logic — handle both.
    Map<String, dynamic>? planData = asMap(m['planData']);
    if (planData != null &&
        (planData['originalDietPlan'] != null || planData['currentDietPlan'] != null)) {
      planData = asMap(planData['currentDietPlan']) ?? asMap(planData['originalDietPlan']);
    }

    return DietReviewRequest(
      id: id,
      status: (m['status'] as String?) ?? 'pending',
      userId: m['userId'] as String?,
      expertId: m['expertId'] as String?,
      expertName: m['expertName'] as String?,
      planId: m['planId'] as String?,
      isPremium: m['isPremium'] == true,
      totalPrice: asNum(m['totalPrice']),
      createdAt: _asDate(m['createdAt']) ?? _asDate(m['submittedAt']),
      reviewedAt: _asDate(m['reviewedAt']),
      expertNotes: m['expertNotes'] as String?,
      athleteAccepted: m['athleteAccepted'] == true,
      mealChangeHistory: rawHistory
              ?.whereType<Map>()
              .map((e) => MealChangeEntry.fromMap(e.cast<String, dynamic>()))
              .toList() ??
          const [],
      reviewedDietPlan: DietPlanContent.fromMap(asMap(m['reviewedDietPlan'])),
      originalPlanData: planData != null ? DietPlanContent.fromMap(planData) : null,
    );
  }
}
