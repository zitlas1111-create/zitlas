import 'package:flutter/foundation.dart';

import '../../../core/util/json_coerce.dart';

/// One saved revision of a coach-authored plan —
/// `coaching_plans/{athleteUid}/versions/{id}`.
///
/// Written on every publish, by both the website and the app, so the history
/// is shared. Nothing is ever deleted or rewritten: a rollback is saved
/// FORWARD as a new revision, which keeps the thing being rolled back
/// visible instead of erasing the record of it.
@immutable
class CoachPlanVersion {
  const CoachPlanVersion({
    required this.id,
    required this.type,
    required this.data,
    required this.version,
    this.savedAt,
    this.savedBy,
  });

  final String id;

  /// `diet` | `training`.
  final String type;

  /// The full plan payload as it was at save time — the restore source.
  final Map<String, dynamic> data;

  final int version;
  final DateTime? savedAt;
  final String? savedBy;

  bool get isDiet => type == 'diet';

  /// How many days the snapshot covers, for the history row's subtitle.
  int get dayCount {
    final days = data['days'];
    return days is List ? days.length : 0;
  }

  static CoachPlanVersion? fromMap(String id, Map<String, dynamic>? m) {
    if (m == null) return null;
    final data = m['data'];
    // A version row with no payload cannot be restored, so it is not a
    // version — dropping it beats offering a rollback that would blank the
    // athlete's plan.
    if (data is! Map) return null;
    final type = (m['type'] as String?)?.trim();
    if (type != 'diet' && type != 'training') return null;
    return CoachPlanVersion(
      id: id,
      type: type!,
      data: data.cast<String, dynamic>(),
      version: asNum(m['version'])?.toInt() ?? 0,
      savedAt: m['savedAt'] is String ? DateTime.tryParse(m['savedAt'] as String)?.toLocal() : null,
      savedBy: m['savedBy'] as String?,
    );
  }
}
