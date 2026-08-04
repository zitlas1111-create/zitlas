import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/coach_training_plan.dart';
import '../models/workout_review_request.dart';
import '../models/workout_storage.dart';

String _todayKey([DateTime? now]) {
  final d = now ?? DateTime.now();
  return '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

/// Firestore access for the Training feature. Every collection path and
/// field name here was traced from `frontend/pages/dashboard/weekly-plan/
/// weekly-plan.js`, `frontend/pages/dashboard/training/day.js`, and
/// `frontend/assets/js/coaching-gate.js` — no new collections, no schema
/// changes. See docs/MIGRATION_INVENTORY.md for the full audit.
class WorkoutRepository {
  WorkoutRepository(this._firestore);

  final FirebaseFirestore _firestore;

  DocumentReference<Map<String, dynamic>> _userDoc(String uid) =>
      _firestore.collection('users').doc(uid);

  /// Live `users/{uid}` doc, narrowed to `workoutPlan` (the wrapper) and
  /// `planId` (goal-identity stamp) — same doc `cloud-sync.js`'s
  /// `attachRealtime()` keeps live for the Training page.
  Stream<Map<String, dynamic>?> watchUserDoc(String uid) {
    return _userDoc(uid).snapshots().map((snap) => snap.data());
  }

  /// `saveGoal`-style merge write — persists the wrapper, matching the
  /// website's several `localStorage.setItem('zitlas_workout_plan', ...)`
  /// call sites (normalization persistence, planId adoption, swap-equivalent
  /// edits) but onto the real Firestore doc.
  Future<void> saveWorkoutStorage(String uid, WorkoutStorage storage) {
    return _userDoc(uid).set({
      'workoutPlan': storage.toMap(),
      'workoutPlanUpdatedAt': DateTime.now().toIso8601String(),
    }, SetOptions(merge: true));
  }

  Future<void> discardWorkoutStorage(String uid) {
    return _userDoc(uid).set({'workoutPlan': null}, SetOptions(merge: true));
  }

  /// `review_requests` where `userId == uid && reviewType == 'workout'`. No
  /// `orderBy` — same reasoning as the Diet feature (avoids the composite
  /// index requirement, sorts client-side).
  Stream<List<WorkoutReviewRequest>> watchWorkoutReviews(String uid) {
    return _firestore
        .collection('review_requests')
        .where('userId', isEqualTo: uid)
        .where('reviewType', isEqualTo: 'workout')
        .snapshots()
        .map((snap) {
          final list = snap.docs
              .map((d) => WorkoutReviewRequest.fromMap(d.id, d.data()))
              .toList();
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

  Future<void> markReviewAccepted(String reviewId) {
    return _firestore
        .collection('review_requests')
        .doc(reviewId)
        .update({'athleteAccepted': true});
  }

  /// `initCoachTrainingMode()`'s `personal_coaching/{uid}` listener.
  Stream<PersonalCoachingRelationship?> watchCoachingRelationship(String uid) {
    return _firestore.collection('personal_coaching').doc(uid).snapshots().map(
      (snap) => snap.exists ? PersonalCoachingRelationship.fromMap(snap.data()!) : null,
    );
  }

  /// `coaching_plans/{uid}` listener, attached only once the relationship
  /// shows a coach training plan — mirrors `initCoachTrainingMode()`'s
  /// lazy-attach behavior (the controller decides when to subscribe).
  Stream<CoachTrainingPlan?> watchCoachTrainingPlan(String uid) {
    return _firestore.collection('coaching_plans').doc(uid).snapshots().map((snap) {
      final training = snap.data()?['training'];
      if (training is! Map) return null;
      return CoachTrainingPlan.fromMap(training.cast<String, dynamic>());
    });
  }

  /// Live `workoutCompleted` flag for today — `day.js`'s
  /// `users/{uid}/activity/{today}` listener.
  Stream<bool> watchTodayWorkoutCompleted(String uid, {DateTime? now}) {
    return _userDoc(uid)
        .collection('activity')
        .doc(_todayKey(now))
        .snapshots()
        .map((snap) => snap.data()?['workoutCompleted'] == true);
  }

  /// `_dtCompleteWorkout()` — extends the SAME daily activity doc
  /// activity-service.js already owns, rather than a new collection.
  Future<void> completeWorkout(String uid, {DateTime? now}) {
    final key = _todayKey(now);
    return _userDoc(uid).collection('activity').doc(key).set({
      'date': key,
      'workoutCompleted': true,
      'workoutCompletedAt': DateTime.now().toIso8601String(),
    }, SetOptions(merge: true));
  }

  /// Live `workout_checkins` for this athlete, keyed by day label to the
  /// LATEST check-in for that day (by timestamp) — mirrors `_dtCheckins`.
  Stream<Map<String, Map<String, dynamic>>> watchWorkoutCheckins(String uid) {
    return _firestore
        .collection('workout_checkins')
        .where('athleteId', isEqualTo: uid)
        .snapshots()
        .map((snap) {
          final out = <String, Map<String, dynamic>>{};
          for (final doc in snap.docs) {
            final c = doc.data();
            final day = c['day'] as String?;
            if (day == null) continue;
            final existing = out[day];
            if (existing == null ||
                (c['timestamp'] as String? ?? '').compareTo(existing['timestamp'] as String? ?? '') > 0) {
              out[day] = c;
            }
          }
          return out;
        });
  }

  /// `_dtSendWorkoutToCoach(day)` — writes the check-in, a coaching
  /// notification, and a push notification to the coach. Requires an
  /// active (non-expired) Personal Coaching relationship; the controller
  /// gates the call via `PersonalCoachingRelationship.isActiveForCheckins`.
  Future<void> sendWorkoutToCoach({
    required String uid,
    required String coachId,
    required String athleteName,
    required String dayLabel,
    required String focus,
    required List<Map<String, dynamic>> exercises,
  }) async {
    final id = 'WCI_${DateTime.now().millisecondsSinceEpoch}_${_randomSuffix()}';
    final now = DateTime.now().toIso8601String();
    await _firestore.collection('workout_checkins').doc(id).set({
      'checkinId': id,
      'athleteId': uid,
      'coachId': coachId,
      'day': dayLabel,
      'focus': focus,
      'exercises': exercises,
      'timestamp': now,
      'status': 'pending',
      'reaction': null,
      'score': null,
      'comment': null,
      'reviewedAt': null,
      'reviewedBy': null,
    });

    final nid = 'CN_${DateTime.now().millisecondsSinceEpoch}_${_randomSuffix()}';
    await _firestore.collection('coaching_notifications').doc(nid).set({
      'id': nid,
      'toId': coachId,
      'fromId': uid,
      'fromName': athleteName,
      'text': '💪 $athleteName sent $dayLabel\'s workout for review.',
      'type': 'workout_checkin',
      'createdAt': now,
      'read': false,
    });
  }

  static String _randomSuffix() {
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    final r = DateTime.now().microsecondsSinceEpoch;
    return List.generate(4, (i) => chars[(r ~/ (i + 1)) % chars.length]).join();
  }
}
