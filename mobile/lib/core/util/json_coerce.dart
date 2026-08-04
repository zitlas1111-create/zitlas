/// Tolerant JSON coercion for LLM-generated payloads.
///
/// Why this exists: large parts of the ZITLAS response tree
/// (`diet_plan`, `workout_plan`) are **raw LLM output**. The JSON schemas in
/// `backend/routes/assessment.py` are *prompt instructions*, not enforced
/// contracts — nothing validates the model's reply before it reaches the
/// client. So a field documented as `"sets": number` genuinely arrives as
/// `3`, `"3"`, `3.0`, or `"3-4"` depending on the generation.
///
/// The website never noticed because JavaScript coerces on use
/// (`String(ex.sets)`, `parseInt(...)`). Dart's `as num?` does not, which is
/// what produced:
///   type 'String' is not a subtype of type 'num?' in type cast
///
/// These helpers restore that tolerance **without** inventing data: a value
/// that carries no usable information returns `null` rather than a
/// fabricated `0`/`''`.
library;

/// For values the UI only ever *displays* and never computes with — e.g.
/// `sets`, `rest_seconds`, `reps_or_duration`.
///
/// Preserves semantic strings verbatim (`"3-4"`, `"AMRAP"`, `"To failure"`,
/// `"30 sec"`) because destroying them would lose real production data, and
/// renders numbers the way JS `String()` does (`3.0` → `"3"`, not `"3.0"`).
///
/// Empty/whitespace-only input returns `null`, matching the website's
/// truthiness gate (`if (ex.sets)`) which skips rendering blank values.
String? asDisplayString(dynamic v) {
  if (v == null) return null;
  if (v is String) {
    final t = v.trim();
    return t.isEmpty ? null : t;
  }
  if (v is num) return _numToCleanString(v);
  if (v is bool) return null; // never a meaningful display value here
  final s = v.toString().trim();
  return s.isEmpty ? null : s;
}

/// For genuinely numeric fields that get used in **arithmetic** — e.g.
/// `duration_minutes` (summed into total training hours),
/// `calories_burned_est`, `calories`, `protein_g`.
///
/// Accepts a real number, a clean numeric string (`"45"`, `"45.5"`), or a
/// number with a unit suffix (`"45 min"`, `"1,600 kcal"`) — the last case
/// mirroring the website's own `parseInt(String(x).replace(/[^0-9]/g, ''))`
/// in `weekly-plan.js`'s `totalMin` reduce. Returns `null` when there is no
/// number to be found, so callers can distinguish "absent" from "zero".
num? asNum(dynamic v) {
  if (v == null) return null;
  if (v is num) return v.isFinite ? v : null;
  if (v is! String) return null;

  final t = v.trim();
  if (t.isEmpty) return null;

  // Fast path: a clean numeric string, including negatives and decimals.
  final direct = num.tryParse(t);
  if (direct != null) return direct.isFinite ? direct : null;

  // Unit-suffixed / thousands-separated: keep digits, one decimal point and
  // a leading sign, then retry. "45 min" -> 45, "1,600 kcal" -> 1600.
  final cleaned = t.replaceAll(RegExp(r'(?!^-)[^0-9.]'), '');
  if (cleaned.isEmpty || cleaned == '-' || cleaned == '.') return null;
  final parsed = num.tryParse(cleaned);
  return (parsed != null && parsed.isFinite) ? parsed : null;
}

/// Integer variant of [asNum], for fields that are conceptually whole
/// (step goals, day indices, set counts stored numerically).
int? asInt(dynamic v) => asNum(v)?.round();

/// For text fields that the LLM sometimes emits as a bare number — e.g. a
/// `reps_or_duration` of `12` instead of `"12 reps"`. Unlike
/// [asDisplayString] this keeps `"0"`/`"false"`-ish text, since a caption
/// legitimately can be any string.
String? asText(dynamic v) {
  if (v == null) return null;
  if (v is String) {
    final t = v.trim();
    return t.isEmpty ? null : t;
  }
  if (v is num) return _numToCleanString(v);
  return v.toString();
}

/// Safe `List<Map<String, dynamic>>` extraction. A non-list (or a list with
/// junk entries) yields the valid subset rather than throwing — one
/// malformed entry must not discard an otherwise-good 7-day plan.
List<Map<String, dynamic>> asMapList(dynamic v) {
  if (v is! List) return const [];
  return v.whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();
}

/// Safe `List<String>` extraction (food lists, key rules, precautions).
List<String> asStringList(dynamic v) {
  if (v is! List) return const [];
  return v.where((e) => e != null).map((e) => e.toString()).toList();
}

/// Safe nested-map extraction.
Map<String, dynamic>? asMap(dynamic v) =>
    v is Map ? v.cast<String, dynamic>() : null;

/// Writes a display value back out preserving its original numeric-ness:
/// a cleanly-numeric string round-trips as a number, so reading `sets: 3`
/// and saving does not silently drift the stored type to `"3"` for the
/// expert dashboard (which writes ints — `modify-workout.js:139`
/// `sets: parseInt(sets)`). Semantic strings are written back untouched.
Object? displayStringToJson(String? v) {
  if (v == null) return null;
  final n = num.tryParse(v);
  if (n == null) return v;
  return n is double && n == n.roundToDouble() ? n.toInt() : n;
}

String _numToCleanString(num n) {
  if (n is int) return n.toString();
  if (n == n.roundToDouble() && n.isFinite) return n.toInt().toString();
  return n.toString();
}
