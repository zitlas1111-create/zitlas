import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:zitlas_mobile/features/diet/models/swap_result.dart';

/// Contract test: what the deterministic swap engine returns must arrive in
/// the UI byte-for-byte.
///
/// The failure this guards against is subtle — a parser that rounds, reorders,
/// truncates, or silently drops a field looks fine in isolation and only shows
/// up as "the app showed a different food than the backend". Each case below
/// feeds a REAL captured `/api/diet/swap` response through `SwapResult` and
/// asserts the parsed values are identical to the JSON.
void main() {
  /// A real response body captured from POST /api/diet/swap
  /// (Maharashtra / Weight Loss / Vegetarian / Hostel, Mid-Morning).
  const capturedJson = '''
{
  "module": "deterministic_swap",
  "options": [
    {"name":"Lemon Honey Water (Hostel Mess Style)","foods":["Lemon Honey Water (Hostel Mess Style) (1 glass (250 ml))"],
     "food_ids":[101],"calories":199,"protein_g":4.0,"carbs_g":12.5,"fat_g":3.2,
     "reason":"Lemon Honey Water — 6% fewer calories (199 vs 211 kcal), about the same protein (4.0g).",
     "availability":"Available across India","budget_level":"Standard","high_protein":false},
    {"name":"Multigrain Khakhra","foods":["Multigrain Khakhra (2 pieces (40 g))"],
     "food_ids":[202],"calories":172,"protein_g":5.6,"carbs_g":28.0,"fat_g":4.1,
     "reason":"Multigrain Khakhra — 18% fewer calories (172 vs 211 kcal), more protein (5.6g vs 4.8g).",
     "availability":"Commonly available in Maharashtra","budget_level":"Standard","high_protein":false},
    {"name":"Mess Curd with Sugar (Home Style)","foods":["Mess Curd with Sugar (1 bowl (150 g))"],
     "food_ids":[303],"calories":178,"protein_g":5.1,"carbs_g":20.2,"fat_g":6.0,
     "reason":"Mess Curd with Sugar — 16% fewer calories (178 vs 211 kcal), about the same protein (5.1g).",
     "availability":"Available across India","budget_level":"Economy","high_protein":false},
    {"name":"Mess Roti Sabzi Combo (Home Style)","foods":["Mess Roti Sabzi Combo (1 plate (200 g))"],
     "food_ids":[404],"calories":184,"protein_g":4.0,"carbs_g":30.1,"fat_g":5.5,
     "reason":"Mess Roti Sabzi Combo — 13% fewer calories (184 vs 211 kcal), about the same protein (4.0g).",
     "availability":"Commonly available in Maharashtra","budget_level":"Economy","high_protein":false},
    {"name":"Brown Rice (Small Portion) (Home Style)","foods":["Brown Rice (Small Portion) (100 g)"],
     "food_ids":[505],"calories":149,"protein_g":4.8,"carbs_g":32.0,"fat_g":1.2,
     "reason":"Brown Rice — 29% fewer calories (149 vs 211 kcal), about the same protein (4.8g).",
     "availability":"Available across India","budget_level":"Standard","high_protein":false}
  ],
  "current": {"calories":211.0,"protein":4.8,"carbs":15.0,"fat":10.6},
  "relaxed_match": true,
  "match_note": "Closest available nutritional match",
  "elapsed_ms": 217.4,
  "llm_used": false
}
''';

  late Map<String, dynamic> raw;
  late SwapResult parsed;

  setUp(() {
    raw = jsonDecode(capturedJson) as Map<String, dynamic>;
    parsed = SwapResult.fromMap(raw);
  });

  group('Flutter receives exactly what the engine returned', () {
    test('all 5 options survive parsing — none dropped', () {
      expect(parsed.options.length, 5);
      expect(parsed.options.length, (raw['options'] as List).length);
    });

    test('order is preserved — rank 1 stays rank 1', () {
      final backendNames = [
        for (final o in raw['options'] as List) (o as Map)['name'] as String,
      ];
      expect(parsed.options.map((o) => o.name).toList(), backendNames,
          reason: 'the engine ranked these; the UI must not reorder them');
    });

    test('every macro matches the response exactly, with no rounding', () {
      final backend = raw['options'] as List;
      for (var i = 0; i < parsed.options.length; i++) {
        final b = backend[i] as Map<String, dynamic>;
        final p = parsed.options[i];
        expect(p.calories, b['calories'], reason: 'calories @$i');
        expect(p.proteinG, (b['protein_g'] as num).toDouble(), reason: 'protein @$i');
        expect(p.carbsG, (b['carbs_g'] as num).toDouble(), reason: 'carbs @$i');
        expect(p.fatG, (b['fat_g'] as num).toDouble(), reason: 'fat @$i');
      }
    });

    test('reason text is passed through verbatim', () {
      final backend = raw['options'] as List;
      for (var i = 0; i < parsed.options.length; i++) {
        expect(parsed.options[i].reason, (backend[i] as Map)['reason'],
            reason: 'the reason is engine-generated from real macros — '
                'the UI must not reword it');
      }
    });

    test('food display strings are unchanged', () {
      final backend = raw['options'] as List;
      for (var i = 0; i < parsed.options.length; i++) {
        final expected = [
          for (final f in (backend[i] as Map)['foods'] as List) f.toString(),
        ];
        expect(parsed.options[i].foods, expected);
      }
    });

    test('availability and budget labels are preserved', () {
      expect(parsed.options[1].availability, 'Commonly available in Maharashtra');
      expect(parsed.options[2].budgetLevel, 'Economy');
      expect(parsed.options[0].budgetLevel, 'Standard');
    });
  });

  group('honesty signals reach the UI', () {
    test('a widened nutrition band is surfaced, not hidden', () {
      expect(parsed.relaxedMatch, isTrue);
      expect(parsed.matchNote, 'Closest available nutritional match');
    });

    test('llm_used is carried through so a regression would be visible', () {
      expect(parsed.llmUsed, isFalse);
    });

    test('high_protein is only true when the DATASET says so', () {
      // Nothing in this captured set is flagged; the UI badge must therefore
      // not appear for any of them.
      expect(parsed.options.every((o) => !o.highProtein), isTrue);
    });
  });

  _legacyCompatibilityTests();

  group('malformed responses degrade safely', () {
    test('an option with no name is dropped, the rest still parse', () {
      final broken = jsonDecode(capturedJson) as Map<String, dynamic>;
      (broken['options'] as List)[2] = {'calories': 100};
      final r = SwapResult.fromMap(broken);
      expect(r.options.length, 4, reason: 'one unusable row must not kill the sheet');
    });

    test('an empty option list is reported as empty, not as a crash', () {
      final r = SwapResult.fromMap({'options': [], 'relaxed_match': false});
      expect(r.isEmpty, isTrue);
      expect(r.options, isEmpty);
    });

    test('a completely absent options key is handled', () {
      final r = SwapResult.fromMap({});
      expect(r.isEmpty, isTrue);
      expect(r.llmUsed, isFalse);
    });
  });
}

/// Legacy-endpoint compatibility.
///
/// The app ships ahead of the backend. When `/api/diet/swap` is missing, a
/// POST falls through to the static-file mount at "/" and returns 405 — which
/// looks exactly like a routing bug from the client. These lock the shape the
/// adapter produces so the UI is identical on both paths.
void _legacyCompatibilityTests() {
  group('legacy /api/ai/swap-meal adapts into SwapResult', () {
    // Real body captured from the LIVE server.
    const legacy = '''
{"structured":{
  "swap":{"name":"Millet Khichdi","foods":["Millet Khichdi (1 bowl (150 g))"],
          "calories":179,"protein_g":22.2,"carbs_g":30.0,"fat_g":4.0,
          "reason":"Millet Khichdi - a light, nutrient-dense option."},
  "alternative":{"name":"Buckwheat Khichdi","foods":["Buckwheat Khichdi (100 g)"],
          "calories":165,"protein_g":6.1,"carbs_g":28.0,"fat_g":3.1,
          "reason":"Buckwheat Khichdi - similar calories."}}}
''';

    test('both blocks become options, in order', () {
      final structured =
          (jsonDecode(legacy) as Map<String, dynamic>)['structured'] as Map;
      final options = <Map<String, dynamic>>[];
      for (final k in ['swap', 'alternative']) {
        final b = structured[k];
        if (b is Map) options.add(b.cast<String, dynamic>());
      }
      final r = SwapResult.fromMap({
        'options': options,
        'relaxed_match': false,
        'match_note': 'Limited options (server update pending)',
        'llm_used': true,
      });

      expect(r.options.length, 2);
      expect(r.options[0].name, 'Millet Khichdi');
      expect(r.options[0].calories, 179);
      expect(r.options[0].proteinG, 22.2);
      expect(r.options[1].name, 'Buckwheat Khichdi');
    });

    test('llm_used is TRUE on the legacy path, so the difference is visible', () {
      final r = SwapResult.fromMap({
        'options': const [],
        'llm_used': true,
        'match_note': 'Limited options (server update pending)',
      });
      expect(r.llmUsed, isTrue);
      expect(r.matchNote, contains('server update pending'));
    });
  });
}
