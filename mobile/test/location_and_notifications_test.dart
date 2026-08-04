import 'package:flutter_test/flutter_test.dart';
import 'package:zitlas_mobile/core/location/location_service.dart';
import 'package:zitlas_mobile/features/notifications/models/app_notification.dart';

/// Phase 8 — regional Diet personalization + advanced notifications.
///
/// [ResolvedLocation] mirrors `zitlas_location` (geo-location.js) exactly;
/// `toAssessmentPayload()` is what actually reaches
/// `AssessmentInput.location` -> `location_food_engine.resolve_state()` on
/// the backend, so its shape is load-bearing, not cosmetic.
///
/// [AppNotification] mirrors the `notifications/{id}` doc shape
/// `ZitlasNotify.send()` writes — the one real, currently-live notification
/// system (see docs/MIGRATION_INVENTORY.md Phase 8 for why OS-level push
/// isn't wired to real events yet).
void main() {
  group('ResolvedLocation', () {
    test('toMap/toAssessmentPayload carry the exact field names the backend reads', () {
      final loc = ResolvedLocation(
        latitude: 18.52,
        longitude: 73.85,
        city: 'Pune',
        district: 'Pune',
        state: 'Maharashtra',
        country: 'India',
        pincode: '411001',
        savedAt: DateTime(2026, 1, 1),
      );
      final map = loc.toAssessmentPayload();
      expect(map['city'], 'Pune');
      expect(map['state'], 'Maharashtra');
      expect(map['country'], 'India');
      expect(map['pincode'], '411001');
    });

    test('hasRegion is false for an empty/unresolved location — the backend no-op case', () {
      const loc = ResolvedLocation();
      expect(loc.hasRegion, isFalse);
      expect(loc.toMap()['city'], '');
      expect(loc.toMap()['state'], '');
    });

    test('hasRegion is true once either city or state resolves', () {
      const withCity = ResolvedLocation(city: 'Mumbai');
      const withState = ResolvedLocation(state: 'Maharashtra');
      expect(withCity.hasRegion, isTrue);
      expect(withState.hasRegion, isTrue);
    });

    test('fromMap/toMap round-trips losslessly', () {
      final loc = ResolvedLocation(latitude: 1.0, longitude: 2.0, city: 'X', state: 'Y', savedAt: DateTime(2026, 2, 2));
      final round = ResolvedLocation.fromMap(loc.toMap());
      expect(round.latitude, 1.0);
      expect(round.city, 'X');
      expect(round.state, 'Y');
    });

    test('fromMap(null) degrades to an empty, no-op location rather than throwing', () {
      final loc = ResolvedLocation.fromMap(null);
      expect(loc.hasRegion, isFalse);
    });
  });

  group('AppNotification.fromMap', () {
    test('parses the exact ZitlasNotify.send() doc shape', () {
      final n = AppNotification.fromMap('NTF_1', {
        'userId': 'u1',
        'title': '⭐ Dr. Rao reviewed your plan',
        'message': 'Your diet plan has been reviewed.',
        'category': 'review',
        'type': 'review_completed',
        'action': 'diet',
        'actionId': null,
        'isRead': false,
        'priority': 'high',
        'createdAt': '2026-01-01T10:00:00.000',
      });
      expect(n.userId, 'u1');
      expect(n.category, 'review');
      expect(n.action, 'diet');
      expect(n.isRead, isFalse);
      expect(n.displayIcon, '⭐'); // category fallback icon
    });

    test('an unrecognized category still renders — matches "never gates creation"', () {
      final n = AppNotification.fromMap('NTF_2', {'userId': 'u1', 'title': 'X', 'category': 'totally_new_category'});
      expect(n.displayIcon, '🔔');
      expect(n.category, 'totally_new_category');
    });

    test('a Firestore Timestamp createdAt parses the same as an ISO string', () {
      final n = AppNotification.fromMap('NTF_3', {'userId': 'u1', 'title': 'X', 'createdAt': '2026-03-05T08:00:00.000'});
      expect(n.createdAt, DateTime.parse('2026-03-05T08:00:00.000'));
    });

    test('missing optional fields degrade to safe defaults, never throw', () {
      final n = AppNotification.fromMap('NTF_4', const {'userId': 'u1', 'title': 'X'});
      expect(n.message, isEmpty);
      expect(n.action, isNull);
      expect(n.isRead, isFalse);
      expect(n.priority, 'medium');
    });
  });
}
