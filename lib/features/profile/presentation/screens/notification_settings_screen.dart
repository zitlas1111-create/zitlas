import 'package:flutter/material.dart';

import '../../../../core/notifications/notification_preferences.dart';
import '../../../../core/notifications/zino_notification_scheduler.dart';
import '../../../../core/theme/zitlas_tokens.dart';

/// Profile → Notifications.
///
/// Categories only — no time pickers. The eight reminder times are fixed
/// defaults chosen for when the reminder is actually useful; asking an athlete
/// to configure them before they have received a single one is a setup wall.
/// What they get to decide is which categories speak at all.
class NotificationSettingsScreen extends StatefulWidget {
  const NotificationSettingsScreen({super.key, this.scheduler});

  /// Injectable for tests.
  final ZinoNotificationScheduler? scheduler;

  @override
  State<NotificationSettingsScreen> createState() => _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState extends State<NotificationSettingsScreen> {
  late final ZinoNotificationScheduler _scheduler =
      widget.scheduler ?? ZinoNotificationScheduler();

  NotificationPreferences _prefs = NotificationPreferences.load();
  bool _osAllowed = true;
  bool _exactAllowed = true;
  bool _checking = true;

  @override
  void initState() {
    super.initState();
    _checkOsPermission();
  }

  /// The app-level switches are meaningless if Android itself is blocking
  /// notifications, so that state is surfaced rather than letting someone
  /// toggle happily and hear nothing.
  Future<void> _checkOsPermission() async {
    final allowed = await _scheduler.areEnabled();
    final exact = await _scheduler.canScheduleExactly();
    if (!mounted) return;
    setState(() {
      _osAllowed = allowed;
      _exactAllowed = exact;
      _checking = false;
    });
  }

  Future<void> _apply(NotificationPreferences next) async {
    setState(() => _prefs = next);
    await next.save();
    // Reschedule immediately — a toggle that only takes effect after a restart
    // reads as broken.
    await _scheduler.scheduleAll(preferences: next);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ZitlasTokens.bgStart,
      appBar: AppBar(
        backgroundColor: ZitlasTokens.bgCard,
        elevation: 0,
        title: const Text('Notifications',
            style: TextStyle(
                color: ZitlasTokens.textPrimary, fontSize: 16, fontWeight: FontWeight.w800)),
        iconTheme: const IconThemeData(color: ZitlasTokens.textPrimary),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        children: [
          if (!_checking && !_osAllowed) _blockedBanner(),
          _card(
            child: SwitchListTile(
              value: _prefs.masterEnabled,
              onChanged: (v) => _apply(_prefs.withMaster(v)),
              activeThumbColor: ZitlasTokens.primary,
              title: const Text('All notifications',
                  style: TextStyle(
                      fontSize: 14.5, fontWeight: FontWeight.w800, color: ZitlasTokens.textPrimary)),
              subtitle: const Text('Turn everything from Zino on or off',
                  style: TextStyle(fontSize: 11.5, color: ZitlasTokens.textMuted)),
            ),
          ),
          const SizedBox(height: 16),
          const Padding(
            padding: EdgeInsets.only(left: 4, bottom: 8),
            child: Text('WHAT ZINO REMINDS YOU ABOUT',
                style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.7,
                    color: ZitlasTokens.textMuted)),
          ),
          _card(
            child: Column(
              children: [
                for (final c in NotificationCategory.values)
                  SwitchListTile(
                    value: _prefs.isEnabled(c),
                    // Greyed out under the master switch rather than hidden,
                    // so it stays obvious WHY they're all off.
                    onChanged: _prefs.masterEnabled
                        ? (v) => _apply(_prefs.withCategory(c, v))
                        : null,
                    activeThumbColor: ZitlasTokens.primary,
                    title: Row(
                      children: [
                        Text(c.icon, style: const TextStyle(fontSize: 15)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(c.label,
                              style: const TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w700,
                                  color: ZitlasTokens.textPrimary)),
                        ),
                      ],
                    ),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(left: 23),
                      child: Text(c.blurb,
                          style: const TextStyle(fontSize: 11, color: ZitlasTokens.textMuted)),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _scheduleCard(),
          if (!_checking && _osAllowed && !_exactAllowed) ...[
            const SizedBox(height: 12),
            _precisionCard(),
          ],
        ],
      ),
    );
  }

  /// Android 12+ won't fire a to-the-minute alarm without a separate grant,
  /// so reminders land inside a window instead. Offered as an opt-in rather
  /// than demanded up front: ZITLAS isn't an alarm clock, and a reminder an
  /// hour late is still a reminder.
  Widget _precisionCard() {
    return _card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Reminders arriving late?',
                style: TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w800, color: ZitlasTokens.textPrimary)),
            const SizedBox(height: 4),
            const Text(
              "Android is batching Zino's reminders to save battery, so they "
              'can land up to an hour after the times above. Allowing precise '
              'alarms delivers them on the minute.',
              style: TextStyle(fontSize: 11.5, height: 1.45, color: ZitlasTokens.textSecondary),
            ),
            TextButton(
              onPressed: () async {
                await _scheduler.requestExactAlarms();
                // The grant happens on an OS screen, so re-read on return and
                // reschedule with the mode the system now allows.
                await _checkOsPermission();
                await _scheduler.scheduleAll(preferences: _prefs);
              },
              style: TextButton.styleFrom(
                padding: EdgeInsets.zero,
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text('Allow precise timing',
                  style: TextStyle(fontWeight: FontWeight.w800, color: ZitlasTokens.primary)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _blockedBanner() {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: ZitlasTokens.danger.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: ZitlasTokens.danger.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Notifications are blocked',
              style: TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w800, color: ZitlasTokens.danger)),
          const SizedBox(height: 4),
          const Text(
            "Android is blocking ZITLAS, so nothing below will reach you. "
            "Zino uses reminders to keep your meals, steps and workouts on "
            "track — without them you'll need to remember on your own.",
            style: TextStyle(fontSize: 11.5, height: 1.45, color: ZitlasTokens.textSecondary),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () async {
              await _scheduler.requestPermission();
              await _checkOsPermission();
            },
            style: TextButton.styleFrom(
              padding: EdgeInsets.zero,
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text('Turn on notifications',
                style: TextStyle(fontWeight: FontWeight.w800, color: ZitlasTokens.primary)),
          ),
        ],
      ),
    );
  }

  /// The fixed schedule, shown read-only. People trust reminders more when
  /// they can see exactly when they'll arrive — and it removes any question
  /// about why there are no time pickers.
  Widget _scheduleCard() {
    String fmt(ZinoSlot s) {
      final h = s.hour % 12 == 0 ? 12 : s.hour % 12;
      final m = s.minute.toString().padLeft(2, '0');
      return '$h:$m ${s.hour < 12 ? 'AM' : 'PM'}';
    }

    return _card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Zino's daily schedule",
                style: TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w800, color: ZitlasTokens.textPrimary)),
            const SizedBox(height: 2),
            const Text('Set automatically — nothing to configure.',
                style: TextStyle(fontSize: 11, color: ZitlasTokens.textMuted)),
            const SizedBox(height: 10),
            for (final s in ZinoSlot.values)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    SizedBox(
                      width: 68,
                      child: Text(fmt(s),
                          style: const TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              color: ZitlasTokens.textSecondary)),
                    ),
                    Expanded(
                      child: Text(s.heading,
                          style: TextStyle(
                              fontSize: 11.5,
                              color: _prefs.isEnabled(s.category)
                                  ? ZitlasTokens.textSecondary
                                  : ZitlasTokens.textMuted,
                              decoration: _prefs.isEnabled(s.category)
                                  ? null
                                  : TextDecoration.lineThrough)),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _card({required Widget child}) => Container(
        decoration: BoxDecoration(
          color: ZitlasTokens.bgCard,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: ZitlasTokens.borderSub),
        ),
        child: child,
      );
}
