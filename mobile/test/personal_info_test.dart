import 'package:flutter_test/flutter_test.dart';
import 'package:zitlas_mobile/features/profile/models/personal_info.dart';

/// `PersonalInfo`/`Membership` mirror `zitlas_personal_info`/
/// `zitlas_membership` field-for-field. Covers the DOB→age boundary
/// exactly like `computeAge()` (personal-info.js:122-131), the missing/
/// legacy-data tolerance the Phase 9 task calls out, and the premium
/// expiry-degradation rule ported from `getMembership()` (membership.js).
void main() {
  group('PersonalInfo.fromMap', () {
    test('parses a full production doc', () {
      final info = PersonalInfo.fromMap(const {
        'fullName': 'Atharva Sankpal',
        'email': 'atharva@example.com',
        'mobile': '+91 90000 00000',
        'dob': '2000-01-15',
        'gender': 'male',
        'city': 'Pune',
        'state': 'Maharashtra',
        'height_cm': 175,
        'weight_kg': 70,
        'preferred_height_unit': 'cm',
        'preferred_weight_unit': 'kg',
      });
      expect(info.fullName, 'Atharva Sankpal');
      expect(info.email, 'atharva@example.com');
      expect(info.heightCm, 175);
      expect(info.weightKg, 70);
    });

    test('missing/absent doc degrades to all-null, never throws', () {
      final info = PersonalInfo.fromMap(null);
      expect(info.fullName, isNull);
      expect(info.heightCm, isNull);
      expect(info.preferredHeightUnit, 'cm');
      expect(info.preferredWeightUnit, 'kg');
      expect(info.age, isNull);
    });

    test('tolerates height/weight arriving as strings (legacy/manual entry)', () {
      final info = PersonalInfo.fromMap(const {'height_cm': '175', 'weight_kg': '70.5'});
      expect(info.heightCm, 175);
      expect(info.weightKg, 70.5);
    });

    test('a genuinely unparseable dob does not crash age computation', () {
      final info = PersonalInfo.fromMap(const {'dob': 'not-a-date'});
      expect(info.age, isNull);
    });
  });

  group('PersonalInfo.age — computeAge() boundary port', () {
    test('birthday already passed this year computes the expected age', () {
      final now = DateTime.now();
      // A birthday 20 years ago, guaranteed to have already passed today
      // (one day before "today" in month/day terms) unless today is Jan 1.
      final birth = DateTime(now.year - 20, now.month, now.day).subtract(const Duration(days: 1));
      final dob = '${birth.year.toString().padLeft(4, '0')}-${birth.month.toString().padLeft(2, '0')}-${birth.day.toString().padLeft(2, '0')}';
      final info = PersonalInfo.fromMap({'dob': dob});
      expect(info.age, 20);
    });

    test('birthday not yet reached this year computes one year younger', () {
      final now = DateTime.now();
      final birth = DateTime(now.year - 20, now.month, now.day).add(const Duration(days: 1));
      final dob = '${birth.year.toString().padLeft(4, '0')}-${birth.month.toString().padLeft(2, '0')}-${birth.day.toString().padLeft(2, '0')}';
      final info = PersonalInfo.fromMap({'dob': dob});
      expect(info.age, 19);
    });
  });

  group('Membership.fromMap — premium expiry degradation', () {
    test('defaults to basic/monthly when absent', () {
      final m = Membership.fromMap(null);
      expect(m.plan, 'basic');
      expect(m.isPremium, isFalse);
    });

    test('active (future-dated) premium stays premium', () {
      final future = DateTime.now().add(const Duration(days: 10)).toIso8601String();
      final m = Membership.fromMap({'plan': 'premium', 'premium_expiry_date': future});
      expect(m.isPremium, isTrue);
    });

    test('expired premium reads back as basic — server date is authoritative', () {
      final past = DateTime.now().subtract(const Duration(days: 1)).toIso8601String();
      final m = Membership.fromMap({'plan': 'premium', 'premium_expiry_date': past, 'billing': 'yearly'});
      expect(m.plan, 'basic');
      expect(m.isPremium, isFalse);
      // billing preference survives the degradation, matching web.
      expect(m.billing, 'yearly');
    });

    test('premium with no expiry date at all stays premium (never degraded on missing data)', () {
      final m = Membership.fromMap(const {'plan': 'premium'});
      expect(m.isPremium, isTrue);
    });
  });
}
