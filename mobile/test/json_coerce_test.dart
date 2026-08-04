import 'package:flutter_test/flutter_test.dart';
import 'package:zitlas_mobile/core/util/json_coerce.dart';

/// Unit tests for the shared coercion layer introduced to fix
/// `type 'String' is not a subtype of type 'num?' in type cast`.
///
/// The guiding rule under test: **be tolerant of type, never invent data.**
/// Anything genuinely uninformative returns `null` so callers can still tell
/// "absent" from "zero" — a fabricated `0` would be indistinguishable from a
/// real measurement.
void main() {
  group('asDisplayString — opaque display values (sets, rest_seconds)', () {
    test('preserves semantic strings verbatim', () {
      expect(asDisplayString('3-4'), '3-4');
      expect(asDisplayString('AMRAP'), 'AMRAP');
      expect(asDisplayString('To failure'), 'To failure');
      expect(asDisplayString('30 sec'), '30 sec');
    });

    test('renders numbers the way JS String() does', () {
      expect(asDisplayString(3), '3');
      expect(asDisplayString(3.0), '3', reason: 'no trailing .0');
      expect(asDisplayString(2.5), '2.5');
    });

    test('trims, and treats blank as absent (matches JS truthiness gate)', () {
      expect(asDisplayString('  3  '), '3');
      expect(asDisplayString(''), isNull);
      expect(asDisplayString('   '), isNull);
      expect(asDisplayString(null), isNull);
    });
  });

  group('asNum — fields used in arithmetic', () {
    test('passes through real numbers', () {
      expect(asNum(45), 45);
      expect(asNum(45.5), 45.5);
      expect(asNum(-3), -3);
    });

    test('parses clean numeric strings', () {
      expect(asNum('45'), 45);
      expect(asNum('45.5'), 45.5);
      expect(asNum('-3'), -3);
      expect(asNum(' 45 '), 45);
    });

    test('strips unit suffixes and separators, like the website parseInt path', () {
      expect(asNum('45 min'), 45);
      expect(asNum('520 kcal'), 520);
      expect(asNum('1,600'), 1600);
      expect(asNum('32 g'), 32);
    });

    test('returns null when there is no number — never a fabricated 0', () {
      expect(asNum(null), isNull);
      expect(asNum(''), isNull);
      expect(asNum('unknown'), isNull);
      expect(asNum('N/A'), isNull);
      expect(asNum(true), isNull);
      expect(asNum(double.nan), isNull);
      expect(asNum(double.infinity), isNull);
    });
  });

  group('asText — captions that may arrive as bare numbers', () {
    test('stringifies numbers cleanly', () {
      expect(asText(12), '12');
      expect(asText(12.0), '12');
    });

    test('passes strings through, blank as absent', () {
      expect(asText('12 reps'), '12 reps');
      expect(asText(''), isNull);
      expect(asText(null), isNull);
    });
  });

  group('collection helpers', () {
    test('asMapList yields the valid subset instead of throwing', () {
      expect(asMapList(null), isEmpty);
      expect(asMapList('nope'), isEmpty);
      expect(
        asMapList([
          {'a': 1},
          'junk',
          null,
          {'b': 2},
        ]),
        hasLength(2),
      );
    });

    test('asStringList tolerates mixed entries and non-lists', () {
      expect(asStringList(null), isEmpty);
      expect(asStringList('nope'), isEmpty);
      expect(asStringList(['a', 1, null]), ['a', '1']);
    });

    test('asMap returns null for non-maps', () {
      expect(asMap({'a': 1}), isNotNull);
      expect(asMap('nope'), isNull);
      expect(asMap(null), isNull);
    });
  });

  group('displayStringToJson — lossless numeric round-trip', () {
    test('numeric-looking values go back out as numbers', () {
      // Prevents `sets: 3` drifting to `sets: "3"` for the expert dashboard,
      // which writes ints (modify-workout.js:139 parseInt).
      expect(displayStringToJson('3'), 3);
      expect(displayStringToJson('2.5'), 2.5);
      expect(displayStringToJson('60'), 60);
    });

    test('semantic strings are written back untouched', () {
      expect(displayStringToJson('3-4'), '3-4');
      expect(displayStringToJson('AMRAP'), 'AMRAP');
      expect(displayStringToJson('30 sec'), '30 sec');
    });

    test('null stays null', () {
      expect(displayStringToJson(null), isNull);
    });
  });
}
