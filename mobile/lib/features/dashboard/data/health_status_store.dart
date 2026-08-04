import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/health_status.dart';

/// Device-local persistence for the Health Status card.
///
/// The website keeps this in `localStorage` under `zitlas_health_today` /
/// `zitlas_health_history` and never writes the status itself to Firestore
/// (only a `health_alerts` doc when a coach is active). `shared_preferences`
/// is the faithful native equivalent, so this ports the real behavior without
/// inventing a Firestore collection the production schema doesn't have.
///
/// The derived effective step goal IS mirrored onto today's
/// `users/{uid}/activity/{date}` doc — exactly as `_syncDayToFirestore` does
/// on the website — which is how the Activity card and the coach dashboard
/// see Recovery Mode.
class HealthStatusStore {
  static const _todayKey = 'zitlas_health_today';
  static const _historyKey = 'zitlas_health_history';
  static const _maxHistory = 60;

  static String dateKey([DateTime? now]) {
    final d = now ?? DateTime.now();
    return '${d.year.toString().padLeft(4, '0')}-'
        '${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  /// `activeToday()` — the stored adjustment only counts if it's for today.
  Future<HealthAdjustment?> loadToday({DateTime? now}) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_todayKey);
    if (raw == null) return null;
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final adj = HealthAdjustment.fromMap(map);
      return adj.date == dateKey(now) ? adj : null;
    } catch (_) {
      return null;
    }
  }

  /// `saveToday(adj)` — writes the override and appends to history
  /// (replacing any existing entry for the same date).
  Future<void> saveToday(HealthAdjustment adj) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_todayKey, jsonEncode(adj.toMap()));
    await _appendHistory(
      prefs,
      HealthHistoryEntry(
        date: adj.date,
        status: adj.status,
        severity: adj.severity,
        safety: adj.safety,
      ),
    );
  }

  /// `clearToday()` — removes ONLY today's override. Never touches the
  /// assessment, profile, goals, or expert-reviewed plans.
  Future<void> clearToday() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_todayKey);
  }

  /// "Feeling great" clears the override but still records the day, so the
  /// timeline shows it — `submitReport()`'s `status === 'great'` branch.
  Future<void> recordGreat({DateTime? now}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_todayKey);
    await _appendHistory(
      prefs,
      HealthHistoryEntry(date: dateKey(now), status: 'great'),
    );
  }

  Future<List<HealthHistoryEntry>> loadHistory() async {
    final prefs = await SharedPreferences.getInstance();
    return _readHistory(prefs);
  }

  /// `todayGreat()` — was today explicitly logged as "feeling great"?
  Future<bool> isTodayGreat({DateTime? now}) async {
    final key = dateKey(now);
    final hist = await loadHistory();
    return hist.any((h) => h.date == key && h.status == 'great');
  }

  Future<void> _appendHistory(SharedPreferences prefs, HealthHistoryEntry entry) async {
    final hist = _readHistory(prefs)..removeWhere((h) => h.date == entry.date);
    hist.add(entry);
    final trimmed =
        hist.length > _maxHistory ? hist.sublist(hist.length - _maxHistory) : hist;
    await prefs.setString(
      _historyKey,
      jsonEncode(trimmed.map((h) => h.toMap()).toList()),
    );
  }

  List<HealthHistoryEntry> _readHistory(SharedPreferences prefs) {
    final raw = prefs.getString(_historyKey);
    if (raw == null) return [];
    try {
      final list = jsonDecode(raw) as List;
      return list
          .whereType<Map>()
          .map((e) => HealthHistoryEntry.fromMap(e.cast<String, dynamic>()))
          .toList();
    } catch (_) {
      return [];
    }
  }
}
