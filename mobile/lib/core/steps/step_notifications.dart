import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'step_day.dart';

/// LOCAL step-milestone notifications.
///
/// Deliberately local, not FCM: a step milestone is a device-side fact known
/// only to this phone. Routing it through a server (which would need the step
/// count pushed to it first, then a Cloud Function that doesn't exist — see
/// `FcmService`'s honest note) would add latency and a hard dependency on
/// connectivity for something the device already knows. FCM stays for
/// server-originated events; this handles on-device progress.
class StepNotifications {
  StepNotifications({FlutterLocalNotificationsPlugin? plugin})
      : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;
  bool _initialized = false;

  static const _channelId = 'zitlas_steps';
  static const _channelName = 'Step goals';
  static const _channelDescription =
      'Daily step goal progress and completion updates.';

  /// Distinct ids so a progress update replaces the previous progress
  /// notification instead of stacking four of them, while the goal-complete
  /// message stands on its own and is never overwritten.
  static const _progressNotificationId = 8801;
  static const _completeNotificationId = 8802;

  Future<void> init() async {
    if (_initialized) return;
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    await _plugin.initialize(
      settings: const InitializationSettings(android: android),
    );
    // Channel is created up front so Android's per-channel settings exist
    // before the first notification (on API 26+ a missing channel is dropped
    // silently).
    await _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(
          const AndroidNotificationChannel(
            _channelId,
            _channelName,
            description: _channelDescription,
            importance: Importance.defaultImportance,
          ),
        );
    _initialized = true;
  }

  /// Requests POST_NOTIFICATIONS (Android 13+). Returns whether notifications
  /// can be shown. A `false` here must never stop step COUNTING — the caller
  /// treats notifications as strictly additive.
  Future<bool> requestPermission() async {
    await init();
    final android = _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    if (android == null) return false;
    final granted = await android.requestNotificationsPermission();
    return granted ?? false;
  }

  Future<bool> areNotificationsEnabled() async {
    final android = _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    if (android == null) return false;
    return await android.areNotificationsEnabled() ?? false;
  }

  Future<void> showMilestone({required int milestone, required int goal}) async {
    await init();
    final isComplete = milestone >= 100;
    await _plugin.show(
      id: isComplete ? _completeNotificationId : _progressNotificationId,
      title: milestoneTitle(milestone),
      body: milestoneMessage(milestone: milestone, goal: goal),
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: _channelDescription,
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
        ),
      ),
    );
    if (kDebugMode) debugPrint('[STEPS] notification shown: milestone = $milestone%');
  }
}
