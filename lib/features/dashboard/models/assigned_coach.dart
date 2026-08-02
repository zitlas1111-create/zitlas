import 'package:flutter/foundation.dart';

/// The athlete's assigned Personal Coach.
///
/// Composed from `personal_coaching/{athleteUid}` (the assignment, written
/// only by the backend's accept transaction) plus the coach's public
/// `experts/{coachId}` profile for the photo and verified badge.
///
/// There is no separate assignment collection and no `assignedCoachId` copied
/// onto the user document. One backend-written doc, keyed by the athlete's
/// uid, is the whole assignment: it cannot duplicate (the key is the athlete),
/// it cannot drift out of sync with a copy (there is no copy), and it survives
/// logout, reinstall and a new device because it lives in Firestore rather
/// than on the handset.
@immutable
class AssignedCoach {
  const AssignedCoach({
    required this.coachId,
    required this.coachName,
    this.photo,
    this.verified = false,
    this.specialization,
    this.planLabel,
    this.startDate,
    this.endDate,
  });

  final String coachId;
  final String coachName;
  final String? photo;

  /// Backend/admin-set on `experts/{uid}` — Security Rules stop an expert
  /// writing it themselves (`updateKeeps(['verified', ...])`), so a badge on
  /// screen always reflects a real verification.
  final bool verified;

  final String? specialization;
  final String? planLabel;
  final DateTime? startDate;
  final DateTime? endDate;

  /// Whole days left, floor-rounded. Null when there's no end date.
  int? get daysRemaining {
    final end = endDate;
    if (end == null) return null;
    final days = end.difference(DateTime.now()).inMinutes / 1440;
    return days <= 0 ? 0 : days.floor();
  }

  static AssignedCoach? from({
    required Map<String, dynamic> relationship,
    Map<String, dynamic>? expert,
  }) {
    final coachId = relationship['coachId'] as String?;
    if (coachId == null || coachId.isEmpty) return null;
    return AssignedCoach(
      coachId: coachId,
      // The relationship's stored name wins: it records who the athlete
      // actually agreed to work with, even if the expert renames later.
      coachName: (relationship['coachName'] as String?)?.trim().isNotEmpty == true
          ? relationship['coachName'] as String
          : (expert?['name'] as String?) ?? 'Your coach',
      photo: (expert?['photo'] ?? expert?['photoUrl']) as String?,
      verified: expert?['verified'] == true,
      specialization: expert?['specialization'] as String?,
      planLabel: relationship['planLabel'] as String?,
      startDate: _date(relationship['startDate']),
      endDate: _date(relationship['endDate']),
    );
  }

  static DateTime? _date(Object? raw) =>
      raw is String ? DateTime.tryParse(raw)?.toLocal() : null;
}
