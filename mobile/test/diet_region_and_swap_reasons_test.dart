import 'package:flutter_test/flutter_test.dart';
import 'package:zitlas_mobile/core/location/diet_region_repository.dart';
import 'package:zitlas_mobile/core/location/indian_states.dart';
import 'package:zitlas_mobile/features/diet/presentation/widgets/diet_meal_swap_sheet.dart';

/// Location-permission + intelligent-swap-meal-UX phase.
///
/// [kSupportedDietRegions] must stay in exact lockstep with the backend's
/// `location_food_engine._STATE_TO_ZONE` table (33 states/UTs, 6 zones) —
/// the whole point of a fixed picker list is that it can never offer a
/// label the backend can't zone-map. [DietRegionRepository.payloadFor] is
/// the one place the confirmed region becomes the `{state: ...}` shape
/// `AssessmentInput.location` actually reads.
void main() {
  group('kSupportedDietRegions', () {
    test('contains exactly the 33 states/UTs the backend zone table recognizes', () {
      expect(kSupportedDietRegions.length, 33);
      expect(kSupportedDietRegions, contains('Maharashtra'));
      expect(kSupportedDietRegions, contains('Kerala'));
      expect(kSupportedDietRegions, contains('Jammu & Kashmir'));
    });

    test('has no duplicates and no blank entries', () {
      expect(kSupportedDietRegions.toSet().length, kSupportedDietRegions.length);
      expect(kSupportedDietRegions.every((s) => s.trim().isNotEmpty), isTrue);
    });

    test('is sorted for a predictable search/picker UI', () {
      final sorted = [...kSupportedDietRegions]..sort();
      expect(kSupportedDietRegions, sorted);
    });
  });

  group('DietRegionRepository.payloadFor', () {
    test('a confirmed region becomes the exact {state: ...} backend shape', () {
      expect(DietRegionRepository.payloadFor('Maharashtra'), {'state': 'Maharashtra'});
    });

    test('null/empty region is a clean no-op payload, never a fabricated state', () {
      expect(DietRegionRepository.payloadFor(null), <String, dynamic>{});
      expect(DietRegionRepository.payloadFor(''), <String, dynamic>{});
    });
  });

  group('kDietSwapReasons — website parity', () {
    // Exact `data-reason` strings from `frontend/pages/diet/diet.html:332-388`
    // — the backend keyword-matches on this text
    // (`groq_service._build_reason_context`/`_diet_type_from_reason`), so a
    // wording drift here would silently break the reason->filter mapping.
    const expectedReasons = [
      'Not available near me',
      'Too expensive for my budget',
      "My hostel mess doesn't provide this",
      "I don't like this food",
      'I am allergic to this',
      'I am vegetarian and need a veg option',
      'Religious or cultural reason',
    ];

    test('exactly 7 reasons, matching the website word-for-word', () {
      expect(kDietSwapReasons.map((r) => r.$4).toList(), expectedReasons);
    });

    test('every reason keyword-matches the backend patterns it must trigger', () {
      bool contains(String reason, String keyword) => reason.toLowerCase().contains(keyword);
      expect(contains(expectedReasons[1], 'expensive'), isTrue, reason: 'budget constraint');
      expect(contains(expectedReasons[2], 'hostel'), isTrue, reason: 'hostel constraint');
      expect(contains(expectedReasons[4], 'allerg'), isTrue, reason: 'allergy constraint');
      expect(contains(expectedReasons[5], 'vegetarian'), isTrue, reason: 'diet_tags override -> Vegetarian');
      expect(contains(expectedReasons[6], 'religious') || contains(expectedReasons[6], 'cultural'), isTrue, reason: 'religious/cultural constraint');
      expect(contains(expectedReasons[0], 'available'), isTrue, reason: 'availability constraint');
    });
  });
}
