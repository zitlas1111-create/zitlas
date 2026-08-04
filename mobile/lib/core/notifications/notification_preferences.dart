import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../storage/local_storage_service.dart';

/// What an athlete can switch off.
///
/// Categories, not individual times. Someone who wants fewer notifications
/// wants "stop nagging me about water", not "move my water reminder to
/// 14:20" — and a settings screen with eight time pickers is a wall most
/// people bounce off before they ever get a reminder.
enum NotificationCategory {
  meals('meals', '🍽', 'Meal reminders', 'Breakfast, lunch, snack and dinner'),
  workout('workout', '💪', 'Workout reminders', 'A nudge when your session is due'),
  steps('steps', '🚶', 'Step reminders', 'Evening progress towards your step goal'),
  motivation('motivation', '🌞', 'Daily motivation', 'A morning quote and an evening wind-down'),
  water('water', '💧', 'Water reminders', 'Hydration nudges through the day'),
  achievements('achievements', '🎉', 'Achievements', 'Goal completions and streak milestones');

  const NotificationCategory(this.id, this.icon, this.label, this.blurb);

  final String id, icon, label, blurb;

  static NotificationCategory? fromId(String id) {
    for (final c in values) {
      if (c.id == id) return c;
    }
    return null;
  }
}

/// Which reminder categories are on.
///
/// Everything defaults to ON. A fitness app whose reminders are opt-in mostly
/// ships silent — the athlete asked for a coach, so Zino speaks unless told
/// otherwise, and every category is one tap from off.
@immutable
class NotificationPreferences {
  const NotificationPreferences({
    this.masterEnabled = true,
    this.disabled = const {},
  });

  final bool masterEnabled;

  /// Stored as the DISABLED set rather than the enabled one, so a category
  /// added in a future release is on by default without a migration.
  final Set<NotificationCategory> disabled;

  bool isEnabled(NotificationCategory c) => masterEnabled && !disabled.contains(c);

  NotificationPreferences withCategory(NotificationCategory c, bool enabled) {
    final next = {...disabled};
    if (enabled) {
      next.remove(c);
    } else {
      next.add(c);
    }
    return NotificationPreferences(masterEnabled: masterEnabled, disabled: next);
  }

  NotificationPreferences withMaster(bool enabled) =>
      NotificationPreferences(masterEnabled: enabled, disabled: disabled);

  static const storageKey = 'zitlas_notification_prefs';

  Map<String, dynamic> toMap() => {
        'masterEnabled': masterEnabled,
        'disabled': [for (final c in disabled) c.id],
      };

  static NotificationPreferences fromMap(Map<String, dynamic>? m) {
    if (m == null) return const NotificationPreferences();
    final raw = m['disabled'];
    return NotificationPreferences(
      masterEnabled: m['masterEnabled'] != false,
      disabled: {
        if (raw is List)
          for (final id in raw) ?NotificationCategory.fromId(id.toString()),
      },
    );
  }

  /// Device-scoped on purpose: "don't buzz this phone" is a property of the
  /// handset, not the account. A shared tablet shouldn't inherit someone
  /// else's silence, and a second device shouldn't be silent because the
  /// first one was.
  static NotificationPreferences load([LocalStorageService? storage]) {
    final store = storage ?? _instanceOrNull();
    if (store == null) return const NotificationPreferences();
    try {
      final raw = store.getString(storageKey);
      if (raw == null) return const NotificationPreferences();
      return fromMap(jsonDecode(raw) as Map<String, dynamic>);
    } catch (e) {
      if (kDebugMode) debugPrint('[NOTIF] prefs unreadable, using defaults: $e');
      return const NotificationPreferences();
    }
  }

  Future<void> save([LocalStorageService? storage]) async {
    final store = storage ?? _instanceOrNull();
    if (store == null) return;
    await store.setString(storageKey, jsonEncode(toMap()));
  }

  static LocalStorageService? _instanceOrNull() {
    try {
      return LocalStorageService.instance;
    } catch (_) {
      // Not initialised (tests, very early startup) — defaults are correct.
      return null;
    }
  }
}
