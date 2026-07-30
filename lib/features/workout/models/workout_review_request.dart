import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/util/json_coerce.dart';
import 'workout_plan_content.dart';

DateTime? _asDate(dynamic v) {
  if (v is Timestamp) return v.toDate();
  if (v is String) return DateTime.tryParse(v);
  return null;
}

/// One entry in a review's `workoutChangeHistory` — the diff record an
/// expert leaves behind when editing a day (`modify-workout.js`). Mirrors
/// the Diet feature's `MealChangeEntry`.
class WorkoutChangeEntry {
  const WorkoutChangeEntry({
    required this.dayIndex,
    this.dayLabel,
    this.oldWorkout,
    this.newWorkout,
    this.reason,
    this.modifiedBy,
    this.modifiedAt,
  });

  final int dayIndex;
  final String? dayLabel;

  /// `{focus, duration_minutes, exercises}` snapshots.
  final Map<String, dynamic>? oldWorkout;
  final Map<String, dynamic>? newWorkout;
  final String? reason;
  final String? modifiedBy;
  final String? modifiedAt;

  factory WorkoutChangeEntry.fromMap(Map<String, dynamic> m) {
    return WorkoutChangeEntry(
      dayIndex: asInt(m['dayIndex']) ?? 0,
      dayLabel: asText(m['dayLabel']),
      oldWorkout: asMap(m['oldWorkout']),
      newWorkout: asMap(m['newWorkout']),
      reason: asText(m['reason']),
      modifiedBy: asText(m['modifiedBy']),
      modifiedAt: asText(m['modifiedAt']),
    );
  }
}

/// A `review_requests` doc where `reviewType == 'workout'`. Same collection,
/// same fields the Expert Dashboard's Reviews Inbox already reads/writes —
/// this is a training-specific view over the identical Firestore records,
/// not a parallel schema. Mirrors the Diet feature's `DietReviewRequest`.
class WorkoutReviewRequest {
  const WorkoutReviewRequest({
    required this.id,
    required this.status,
    this.userId,
    this.expertId,
    this.expertName,
    this.planId,
    this.createdAt,
    this.reviewedAt,
    this.expertNotes,
    this.athleteAccepted = false,
    this.workoutChangeHistory = const [],
    this.reviewedWorkoutPlan,
    this.originalPlanData,
  });

  final String id;

  /// `pending | in_progress|expert_reviewing | review_completed|completed | rejected`
  final String status;
  final String? userId;
  final String? expertId;
  final String? expertName;
  final String? planId;
  final DateTime? createdAt;
  final DateTime? reviewedAt;
  final String? expertNotes;
  final bool athleteAccepted;
  final List<WorkoutChangeEntry> workoutChangeHistory;

  /// The expert-edited plan, present once the review is complete. Its
  /// individual days may carry `_edited: true` — scanned as a supplement/
  /// override to `workoutChangeHistory` when building the accepted wrapper.
  final WorkoutPlanContent? reviewedWorkoutPlan;

  /// `planData` on the raw doc — the plan snapshot as it was when the
  /// review was requested (used as `originalWorkoutPlan` fallback on accept).
  final WorkoutPlanContent? originalPlanData;

  bool get isCompleted => status == 'review_completed' || status == 'completed';
  bool get isPending => status == 'pending';
  bool get isInProgress => status == 'in_progress' || status == 'expert_reviewing';
  bool get isRejected => status == 'rejected';

  factory WorkoutReviewRequest.fromMap(String id, Map<String, dynamic> m) {
    Map<String, dynamic>? planData = asMap(m['planData']);
    if (planData != null &&
        (planData['originalWorkoutPlan'] != null || planData['currentWorkoutPlan'] != null)) {
      planData =
          asMap(planData['currentWorkoutPlan']) ?? asMap(planData['originalWorkoutPlan']);
    }

    return WorkoutReviewRequest(
      id: id,
      status: (m['status'] as String?) ?? 'pending',
      userId: m['userId'] as String?,
      expertId: m['expertId'] as String?,
      expertName: m['expertName'] as String?,
      planId: m['planId'] as String?,
      createdAt: _asDate(m['createdAt']) ?? _asDate(m['submittedAt']),
      reviewedAt: _asDate(m['reviewedAt']),
      expertNotes: m['expertNotes'] as String?,
      athleteAccepted: m['athleteAccepted'] == true,
      workoutChangeHistory:
          asMapList(m['workoutChangeHistory']).map(WorkoutChangeEntry.fromMap).toList(),
      reviewedWorkoutPlan: WorkoutPlanContent.fromMap(asMap(m['reviewedWorkoutPlan'])),
      originalPlanData: planData != null ? WorkoutPlanContent.fromMap(planData) : null,
    );
  }
}
