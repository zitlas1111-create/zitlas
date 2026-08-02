import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../../../core/util/json_coerce.dart';
import '../models/coach_diet_plan.dart';
import '../models/coach_plan_version.dart';

/// `coaching_plans/{athleteUid}` — the coach-authored plans.
///
/// THE SAME DOCUMENT THE WEBSITE USES (`components/coaching-workspace.js`),
/// field for field, so a plan written on the phone opens on the web and vice
/// versa. Nothing here writes `users/{uid}.dietPlan` or `.workoutPlan`: the
/// AI plan and the coach plan are separate documents with separate owners,
/// which is precisely why regenerating one can never overwrite the other.
///
/// Every save also appends to `versions/` — the coach plan is never
/// overwritten in place without a snapshot of what it replaced.
class CoachingPlanRepository {
  CoachingPlanRepository({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  DocumentReference<Map<String, dynamic>> _planDoc(String athleteId) =>
      _db.collection('coaching_plans').doc(athleteId);

  /// Live coach plan document.
  Stream<CoachingPlanDoc> watch(String athleteId) {
    return _planDoc(athleteId).snapshots().map((snap) {
      final doc = CoachingPlanDoc.fromMap(snap.data());
      if (kDebugMode) {
        debugPrint('[COACH PLAN] $athleteId diet=${doc.diet.days.length}d '
            'v${doc.dietVersion} training=${doc.hasTraining} v${doc.trainingVersion}');
      }
      return doc;
    });
  }

  Future<CoachingPlanDoc> fetch(String athleteId) async {
    final snap = await _planDoc(athleteId).get();
    return CoachingPlanDoc.fromMap(snap.data());
  }

  /// Publishes the coach's diet to the athlete.
  ///
  /// One `set(merge)` on the plan doc, then a version snapshot, then the
  /// athlete's notification — in that order, so the athlete is never told
  /// about a plan that failed to save. The version write and the notification
  /// are both best-effort: neither is allowed to make a successful publish
  /// look like a failure.
  ///
  /// [athletePlanId] stamps which athlete plan generation this was authored
  /// against. Pass the CURRENT `users/{uid}.planId`; consumers fail closed on
  /// a mismatch so a plan written for an abandoned goal retires itself.
  Future<void> saveDiet({
    required String athleteId,
    required String athleteName,
    required String coachId,
    required String coachName,
    required String planType,
    required CoachDietPlan diet,
    String? athletePlanId,
  }) async {
    final now = DateTime.now();
    final current = await fetch(athleteId);
    final version = current.dietVersion + 1;
    final stamped = diet.copyWith(planId: athletePlanId);

    if (kDebugMode) {
      debugPrint('[COACH PLAN] saving diet v$version for $athleteId '
          '(${stamped.days.length} days, planId=$athletePlanId)');
    }

    await _planDoc(athleteId).set({
      'athleteId': athleteId,
      'athleteName': athleteName,
      'coachId': coachId,
      'coachName': coachName,
      'planType': planType,
      'diet': stamped.toMap(),
      'dietUpdatedAt': now.toIso8601String(),
      'dietVersion': version,
    }, SetOptions(merge: true));

    await _snapshotVersion(
      athleteId: athleteId,
      type: 'diet',
      data: stamped.toMap(),
      version: version,
      savedBy: coachName,
      now: now,
    );

    await _notifyAthlete(
      athleteId: athleteId,
      title: '🥗 $coachName updated your diet plan',
      message: 'Tap to see what changed.',
      type: 'diet_update',
      action: 'diet',
    );
  }

  /// Training mirror of [saveDiet]. `training` is passed as the raw website
  /// shape (`{days: [...]}`) because `CoachTrainingPlan` already converts that
  /// into the athlete's rendering model on the read side — round-tripping it
  /// through a second representation here would risk the two drifting.
  Future<void> saveTraining({
    required String athleteId,
    required String athleteName,
    required String coachId,
    required String coachName,
    required String planType,
    required Map<String, dynamic> training,
    String? athletePlanId,
  }) async {
    final now = DateTime.now();
    final current = await fetch(athleteId);
    final version = current.trainingVersion + 1;
    final stamped = {...training, 'planId': athletePlanId};

    if (kDebugMode) {
      debugPrint('[COACH PLAN] saving training v$version for $athleteId');
    }

    await _planDoc(athleteId).set({
      'athleteId': athleteId,
      'athleteName': athleteName,
      'coachId': coachId,
      'coachName': coachName,
      'planType': planType,
      'training': stamped,
      'trainingUpdatedAt': now.toIso8601String(),
      'trainingVersion': version,
    }, SetOptions(merge: true));

    await _snapshotVersion(
      athleteId: athleteId,
      type: 'training',
      data: stamped,
      version: version,
      savedBy: coachName,
      now: now,
    );

    await _notifyAthlete(
      athleteId: athleteId,
      title: '🏋 $coachName updated your workout plan',
      message: 'Tap to see what changed.',
      type: 'training_update',
      action: 'training',
    );
  }

  /// Every saved revision, newest first — the history and rollback source.
  Stream<List<CoachPlanVersion>> watchVersions(String athleteId, {String? type}) {
    Query<Map<String, dynamic>> query = _planDoc(athleteId).collection('versions');
    if (type != null) query = query.where('type', isEqualTo: type);
    return query.snapshots().map((snap) {
      final list = snap.docs
          .map((d) => CoachPlanVersion.fromMap(d.id, d.data()))
          .nonNulls
          .toList();
      // Sorted client-side rather than with orderBy so this needs no composite
      // index alongside the `type` filter — a version list is at most a few
      // dozen documents.
      list.sort((a, b) {
        final at = a.savedAt, bt = b.savedAt;
        if (at == null && bt == null) return b.version.compareTo(a.version);
        if (at == null) return 1;
        if (bt == null) return -1;
        return bt.compareTo(at);
      });
      return list;
    });
  }

  /// Restores a previous revision by SAVING IT FORWARD as a new version.
  ///
  /// Deliberately not a destructive rewind: rolling back is itself an edit the
  /// athlete is entitled to see, and the revision being replaced stays in the
  /// history. Nothing is ever deleted.
  Future<void> restoreVersion({
    required String athleteId,
    required String athleteName,
    required String coachId,
    required String coachName,
    required String planType,
    required CoachPlanVersion version,
    String? athletePlanId,
  }) {
    if (version.type == 'training') {
      return saveTraining(
        athleteId: athleteId,
        athleteName: athleteName,
        coachId: coachId,
        coachName: coachName,
        planType: planType,
        training: version.data,
        athletePlanId: athletePlanId,
      );
    }
    return saveDiet(
      athleteId: athleteId,
      athleteName: athleteName,
      coachId: coachId,
      coachName: coachName,
      planType: planType,
      diet: CoachDietPlan.fromMap(version.data),
      athletePlanId: athletePlanId,
    );
  }

  /// The athlete's current selection per meal, keyed `'<day>:<mealId>'`.
  Future<void> saveSelections(String athleteId, Map<String, int> selections) {
    return _planDoc(athleteId).set({'dietSelections': selections}, SetOptions(merge: true));
  }

  Future<void> _snapshotVersion({
    required String athleteId,
    required String type,
    required Map<String, dynamic> data,
    required int version,
    required String savedBy,
    required DateTime now,
  }) async {
    try {
      await _planDoc(athleteId)
          .collection('versions')
          .doc('${type}_${now.millisecondsSinceEpoch}')
          .set({
        'type': type,
        'data': data,
        'version': version,
        'savedAt': now.toIso8601String(),
        'savedBy': savedBy,
      });
    } catch (e) {
      // The plan itself is already published. Losing a history entry is worth
      // a log, not a failed save the coach would retry (and thereby publish
      // twice).
      if (kDebugMode) debugPrint('[COACH PLAN] version snapshot failed: $e');
    }
  }

  /// Same `notifications` doc shape `ZitlasNotify.send()` writes on the
  /// website, so these render identically in the athlete's Notification
  /// Center on both platforms.
  Future<void> _notifyAthlete({
    required String athleteId,
    required String title,
    required String message,
    required String type,
    required String action,
  }) async {
    final now = DateTime.now();
    final id = 'NTF_${now.millisecondsSinceEpoch}_$type';
    try {
      await _db.collection('notifications').doc(id).set({
        'notificationId': id,
        'userId': athleteId,
        'title': title,
        'message': message,
        'category': 'expert',
        'icon': null,
        'type': type,
        'action': action,
        'actionId': null,
        'expertId': null,
        'isRead': false,
        'priority': 'high',
        'createdAt': now.toIso8601String(),
      });
    } catch (e) {
      if (kDebugMode) debugPrint('[COACH PLAN] notification failed: $e');
    }
  }
}

/// The whole `coaching_plans/{athleteUid}` document.
@immutable
class CoachingPlanDoc {
  const CoachingPlanDoc({
    this.diet = const CoachDietPlan(),
    this.training,
    this.selections = const {},
    this.coachId,
    this.coachName,
    this.planType,
    this.dietVersion = 0,
    this.trainingVersion = 0,
    this.dietUpdatedAt,
    this.trainingUpdatedAt,
    this.exists = false,
  });

  final CoachDietPlan diet;

  /// Raw website shape — see [CoachingPlanRepository.saveTraining].
  final Map<String, dynamic>? training;

  final Map<String, int> selections;
  final String? coachId;
  final String? coachName;
  final String? planType;
  final int dietVersion;
  final int trainingVersion;
  final DateTime? dietUpdatedAt;
  final DateTime? trainingUpdatedAt;
  final bool exists;

  bool get hasTraining {
    final t = training;
    if (t == null) return false;
    final days = t['days'];
    return days is List && days.isNotEmpty;
  }

  /// Whether the coach may edit diet / training, from the plan they sold.
  ///
  /// `diet` → diet only, `training` → training only, `complete` → both. A
  /// coach paid for training must not quietly rewrite the athlete's food.
  bool get canEditDiet => planType == 'diet' || planType == 'complete' || planType == null;
  bool get canEditTraining =>
      planType == 'training' || planType == 'complete' || planType == null;

  /// True when this plan was authored against a DIFFERENT athlete plan
  /// generation than the one currently in force — the fail-closed guard.
  bool isStaleFor(String? athletePlanId) {
    final authored = diet.planId;
    if (authored == null || athletePlanId == null) return false;
    return authored != athletePlanId;
  }

  static CoachingPlanDoc fromMap(Map<String, dynamic>? data) {
    if (data == null) return const CoachingPlanDoc();
    final rawSelections = data['dietSelections'];
    return CoachingPlanDoc(
      diet: CoachDietPlan.fromMap(data['diet']),
      training: (data['training'] as Map?)?.cast<String, dynamic>(),
      // Coerced rather than cast: these documents are written by the website
      // too, and JS happily stores a version or a selection index as a string.
      // A hard cast threw on the real production document and took the whole
      // coach plan down with it.
      selections: {
        if (rawSelections is Map)
          for (final e in rawSelections.entries)
            if (asNum(e.value) != null) e.key.toString(): asNum(e.value)!.toInt(),
      },
      coachId: data['coachId'] as String?,
      coachName: data['coachName'] as String?,
      planType: data['planType'] as String?,
      dietVersion: asNum(data['dietVersion'])?.toInt() ?? 0,
      trainingVersion: asNum(data['trainingVersion'])?.toInt() ?? 0,
      dietUpdatedAt: _date(data['dietUpdatedAt']),
      trainingUpdatedAt: _date(data['trainingUpdatedAt']),
      exists: true,
    );
  }

  static DateTime? _date(Object? raw) =>
      raw is String ? DateTime.tryParse(raw)?.toLocal() : null;
}
