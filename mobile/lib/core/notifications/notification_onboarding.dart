import 'dart:io';

import 'package:flutter/foundation.dart';

import '../storage/local_storage_service.dart';
import 'zino_notification_scheduler.dart';

/// Whether the first-launch notification prompt has already been shown.
///
/// Install-scoped, not account-scoped: POST_NOTIFICATIONS is granted to the
/// APP on this handset, so re-asking a returning athlete who already granted
/// (or deliberately declined) it would be noise. Android itself only ever
/// shows its system dialog once anyway — asking again just produces an
/// instant silent denial, which is worse than not asking.
class NotificationOnboarding {
  const NotificationOnboarding({
    LocalStorageService? storage,
    ZinoNotificationScheduler? scheduler,
    bool? isAndroid,
  })  : _storage = storage,
        _scheduler = scheduler,
        _isAndroidOverride = isAndroid;

  final LocalStorageService? _storage;
  final ZinoNotificationScheduler? _scheduler;
  final bool? _isAndroidOverride;

  static const promptedKey = 'zitlas_notification_prompted';

  LocalStorageService? get _store {
    if (_storage != null) return _storage;
    try {
      return LocalStorageService.instance;
    } catch (_) {
      return null;
    }
  }

  bool get _android => _isAndroidOverride ?? (!kIsWeb && Platform.isAndroid);

  bool get hasPrompted => _store?.getBool(promptedKey) ?? false;

  Future<void> markPrompted() async => _store?.setBool(promptedKey, true);

  /// True when this launch should show ZITLAS's own explanation sheet.
  ///
  /// Deliberately checks [ZinoNotificationScheduler.areEnabled] as well: an
  /// athlete who granted notifications through the OS settings screen instead
  /// of our flow never needs the pitch, and one who revoked them shouldn't be
  /// re-pitched on every launch either — the prompted flag covers that.
  Future<bool> shouldPrompt() async {
    if (!_android) return false;
    if (hasPrompted) return false;
    final scheduler = _scheduler ?? ZinoNotificationScheduler();
    try {
      if (await scheduler.areEnabled()) {
        // Already granted (Android 12 and below auto-grant). Record it so the
        // sheet never appears, and make sure the schedule is in place.
        await markPrompted();
        await scheduler.scheduleAll();
        return false;
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[NOTIF] permission state unreadable: $e');
      return false;
    }
    return true;
  }

  /// Runs the real OS request and (re)builds the schedule if it succeeds.
  ///
  /// Marks the prompt as shown either way — a decline is a decision, and
  /// ZITLAS asks once, not every launch.
  Future<bool> requestAfterConsent() async {
    await markPrompted();
    final scheduler = _scheduler ?? ZinoNotificationScheduler();
    final granted = await scheduler.requestPermission();
    if (granted) await scheduler.scheduleAll();
    return granted;
  }

  /// "Not now" — no OS dialog at all, and never asked again automatically.
  /// Profile → Notifications remains the way back in.
  Future<void> declineWithoutAsking() => markPrompted();
}
