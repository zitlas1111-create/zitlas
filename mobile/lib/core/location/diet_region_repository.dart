import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// `users/{uid}.preferredDietRegion` — the ONE canonical, user-confirmed
/// diet-region field. Distinct from `users/{uid}.location` (the raw
/// GPS/reverse-geocode snapshot, `ResolvedLocation`'s shape): `location` is
/// assist-data used to SUGGEST a region; `preferredDietRegion` is the
/// durable preference that actually reaches Assessment/Diet
/// generation/regeneration and Swap Meal. GPS initializes this once — it
/// never silently overwrites it again (traveling must not change a user's
/// Diet region out from under them).
class DietRegionRepository {
  DietRegionRepository({required FirebaseFirestore firestore}) : _db = firestore;

  final FirebaseFirestore _db;

  DocumentReference<Map<String, dynamic>> _userDoc(String uid) => _db.collection('users').doc(uid);

  Future<String?> fetchOnce(String uid) async {
    final doc = await _userDoc(uid).get();
    return doc.data()?['preferredDietRegion'] as String?;
  }

  Stream<String?> watch(String uid) {
    return _userDoc(uid).snapshots().map((s) => s.data()?['preferredDietRegion'] as String?);
  }

  Future<void> save(String uid, String state, {required String source}) async {
    if (kDebugMode) debugPrint('[REGION] preferredDietRegion = $state (source=$source)');
    await _userDoc(uid).set({
      'preferredDietRegion': state,
      'preferredDietRegionSource': source, // 'gps' | 'manual'
      'preferredDietRegionSetAt': DateTime.now().toIso8601String(),
    }, SetOptions(merge: true));
  }

  /// The exact `{state: ...}` shape `AssessmentInput.location` /
  /// `_engine_query_context` reads (`location_food_engine.resolve_state()`
  /// only ever needs `city`/`district`/`state`) — minimal and stable, so a
  /// temporary device location can never leak into a generation/swap call.
  /// Static and pure (no Firestore access) so it's unit-testable directly.
  static Map<String, dynamic> payloadFor(String? preferredRegion) {
    if (preferredRegion == null || preferredRegion.isEmpty) return const {};
    return {'state': preferredRegion};
  }
}
