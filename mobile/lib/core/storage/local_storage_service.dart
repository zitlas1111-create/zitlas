import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Non-sensitive local cache, the Flutter analogue of the web app's
/// localStorage-first state (see the key table in CLAUDE.md). Not for
/// tokens or secrets — use [SecureStorageService] for those.
///
/// Must be initialized once via [init] before use (call from `main.dart`
/// after `WidgetsFlutterBinding.ensureInitialized()`).
class LocalStorageService {
  LocalStorageService._(this._prefs);

  static LocalStorageService? _instance;
  final SharedPreferences _prefs;

  static Future<LocalStorageService> init() async {
    final prefs = await SharedPreferences.getInstance();
    return _instance = LocalStorageService._(prefs);
  }

  static LocalStorageService get instance {
    final i = _instance;
    if (i == null) {
      throw StateError(
        'LocalStorageService.init() must be awaited before use.',
      );
    }
    return i;
  }

  String? getString(String key) => _prefs.getString(key);
  Future<bool> setString(String key, String value) => _prefs.setString(key, value);

  bool? getBool(String key) => _prefs.getBool(key);
  Future<bool> setBool(String key, bool value) => _prefs.setBool(key, value);

  int? getInt(String key) => _prefs.getInt(key);
  Future<bool> setInt(String key, int value) => _prefs.setInt(key, value);

  /// Mirrors the web app's pattern of storing structured state as a single
  /// JSON-serialized localStorage value (e.g. `zitlas_diet_plan`).
  Map<String, dynamic>? getJson(String key) {
    final raw = _prefs.getString(key);
    if (raw == null) return null;
    return jsonDecode(raw) as Map<String, dynamic>;
  }

  Future<bool> setJson(String key, Map<String, dynamic> value) {
    return _prefs.setString(key, jsonEncode(value));
  }

  Future<bool> remove(String key) => _prefs.remove(key);

  /// Clears everything except [preserve] — the mobile equivalent of the
  /// web app's `ZitlasAccountGuard` per-uid cache purge on account switch
  /// (see docs/MIGRATION_INVENTORY.md §3). Call this once real auth state
  /// tracking is wired up.
  Future<void> clearExcept(Set<String> preserve) async {
    final keep = <String, Object?>{
      for (final key in preserve)
        if (_prefs.containsKey(key)) key: _prefs.get(key),
    };
    await _prefs.clear();
    for (final entry in keep.entries) {
      final value = entry.value;
      if (value is String) await _prefs.setString(entry.key, value);
      if (value is bool) await _prefs.setBool(entry.key, value);
      if (value is int) await _prefs.setInt(entry.key, value);
      if (value is double) await _prefs.setDouble(entry.key, value);
      if (value is List<String>) await _prefs.setStringList(entry.key, value);
    }
  }
}
