import 'package:flutter_test/flutter_test.dart';
import 'package:zitlas_mobile/features/experts/models/expert_listing.dart';

/// `ExpertListing.fromMap` mirrors `_normalizeExpertToCoach()`
/// (cprofile.js:4629-4664) — the athlete-facing marketplace/profile field
/// mapping. Covers the fallback chains and the just-fixed unsafe-cast class
/// of defect (rating/fee/price fields arriving as strings from legacy or
/// manually-entered expert docs).
void main() {
  group('ExpertPricing.fromMap', () {
    test('defaults match PRICING_DEFAULTS when no override is present', () {
      const p = ExpertPricing();
      expect(p.dietReviewPrice, 49);
      expect(p.workoutReviewPrice, 59);
      expect(p.bothReviewPrice, 99);
      expect(p.chatPrice, 149);
      expect(p.coachingDietPrice, 499);
      expect(p.coachingTrainingPrice, 699);
      expect(p.coachingCompletePrice, 999);
    });

    test('per-expert overrides win, unspecified keys keep the default', () {
      final p = ExpertPricing.fromMap({'dietReviewPrice': 79});
      expect(p.dietReviewPrice, 79);
      expect(p.workoutReviewPrice, 59); // untouched default
    });

    test('tolerates string-typed prices without throwing', () {
      final p = ExpertPricing.fromMap({'dietReviewPrice': '79', 'chatPrice': '199 '});
      expect(p.dietReviewPrice, 79);
      expect(p.chatPrice, 199);
    });

    test('lowestReviewPrice picks the smaller of diet/workout', () {
      final p = ExpertPricing.fromMap({'dietReviewPrice': 90, 'workoutReviewPrice': 40});
      expect(p.lowestReviewPrice, 40);
    });
  });

  group('ExpertListing.fromMap', () {
    test('maps the full production field set', () {
      final e = ExpertListing.fromMap('exp1', {
        'name': 'Dr. Asha Rao',
        'specialization': 'Sports Nutritionist',
        'profilePhoto': 'https://example.com/a.jpg',
        'rating': 4.8,
        'reviews': 120,
        'experience': '8 years',
        'languages': ['English', 'Hindi'],
        'about': 'Helping athletes eat better.',
        'specialties': ['Weight Loss', 'PCOS'],
        'verified': true,
        'verification': {'status': 'approved'},
        'pricing': {'dietReviewPrice': 59},
      });

      expect(e.name, 'Dr. Asha Rao');
      expect(e.role, 'Sports Nutritionist');
      expect(e.rating, '4.8');
      expect(e.reviewCount, 120);
      expect(e.languages, ['English', 'Hindi']);
      expect(e.expertise, ['Weight Loss', 'PCOS']);
      expect(e.verified, isTrue);
      expect(e.verificationStatus, 'approved');
      expect(e.pricing.dietReviewPrice, 59);
      expect(e.initials, 'DA');
    });

    test('falls back through legacy field names (speciality, photo, role)', () {
      final e = ExpertListing.fromMap('exp2', {
        'speciality': 'Weight Loss Coach',
        'photo': 'https://example.com/b.jpg',
      });
      expect(e.role, 'Weight Loss Coach');
      expect(e.image, 'https://example.com/b.jpg');
    });

    test('never infers `verified` from certificate existence — only the real field', () {
      final e = ExpertListing.fromMap('exp3', {'name': 'Someone', 'expertise': ['a', 'b']});
      expect(e.verified, isFalse, reason: 'verified must default false, never inferred');
    });

    test('missing/absent doc fields degrade to safe defaults, never throw', () {
      final e = ExpertListing.fromMap('exp4', const {});
      expect(e.name, 'Expert');
      expect(e.role, 'Nutrition Expert');
      expect(e.rating, '5.0');
      expect(e.reviewCount, 0);
      expect(e.languages, isEmpty);
      expect(e.expertise, isEmpty);
    });

    test('tolerates a string-typed rating/reviews (unsafe-cast defect class)', () {
      final e = ExpertListing.fromMap('exp5', {'rating': '4.6', 'reviews': '37'});
      expect(e.rating, '4.6');
      expect(e.reviewCount, 37);
      expect(e.ratingValue, 4.6);
    });

    test('languages tolerates a comma-separated string as well as a list', () {
      final e = ExpertListing.fromMap('exp6', {'languages': 'English, Hindi, Tamil'});
      expect(e.languages, ['English', 'Hindi', 'Tamil']);
    });

    test('single-word name yields a single-letter initials', () {
      final e = ExpertListing.fromMap('exp7', {'name': 'Coach'});
      expect(e.initials, 'C');
    });
  });
}
