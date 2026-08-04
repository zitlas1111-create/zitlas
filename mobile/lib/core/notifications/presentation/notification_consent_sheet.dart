import 'package:flutter/material.dart';

import '../../theme/zitlas_tokens.dart';
import '../notification_onboarding.dart';

/// ZITLAS's own explanation, shown BEFORE Android's permission dialog.
///
/// Android grants POST_NOTIFICATIONS exactly once — a cold system prompt with
/// no context is the fastest way to a permanent "Don't allow", after which the
/// only route back is the OS settings screen. So Zino makes the case in its
/// own words first, and only "Turn on reminders" goes on to the real request.
///
/// Returns whether notifications ended up enabled.
Future<bool> showNotificationConsentSheet(
  BuildContext context, {
  NotificationOnboarding onboarding = const NotificationOnboarding(),
}) async {
  final accepted = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const _NotificationConsentSheet(),
  );

  if (accepted != true) {
    await onboarding.declineWithoutAsking();
    return false;
  }

  final granted = await onboarding.requestAfterConsent();
  if (!granted && context.mounted) {
    await _showDeclinedDialog(context);
  }
  return granted;
}

/// Shown when the OS request came back denied.
///
/// States what the athlete gives up and where to change their mind — no
/// second attempt, no guilt. Android won't re-show its dialog anyway.
Future<void> _showDeclinedDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: ZitlasTokens.bgCard,
      title: const Text(
        'No reminders for now',
        style: TextStyle(color: ZitlasTokens.textPrimary),
      ),
      content: const Text(
        "Without notifications Zino can't remind you about meals, your "
        'workout or your step goal — you\'ll need to open ZITLAS to check '
        'in. Everything else works exactly the same.\n\n'
        'You can turn reminders on any time from Profile → Notifications.',
        style: TextStyle(color: ZitlasTokens.textSecondary, height: 1.5),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('Got it'),
        ),
      ],
    ),
  );
}

class _NotificationConsentSheet extends StatelessWidget {
  const _NotificationConsentSheet();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: ZitlasTokens.bgCard,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: ZitlasTokens.borderSub,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
          const SizedBox(height: 22),
          const Text('🔔', style: TextStyle(fontSize: 34)),
          const SizedBox(height: 12),
          const Text(
            'Let Zino keep you on track',
            style: TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.w800,
              color: ZitlasTokens.textPrimary,
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            'A handful of short nudges a day — the difference between a plan '
            'you follow and a plan you forget.',
            style: TextStyle(
              fontSize: 13.5,
              height: 1.5,
              color: ZitlasTokens.textSecondary,
            ),
          ),
          const SizedBox(height: 16),
          const _Point(icon: '🍽', text: 'Meal reminders at breakfast, lunch, snack and dinner.'),
          const _Point(icon: '💪', text: 'Your workout, only if you haven\'t done it yet.'),
          const _Point(icon: '🚶', text: 'Step progress in the evening — never after you hit your goal.'),
          const _Point(icon: '🎚', text: 'Every category is one tap from off in Profile.'),
          const SizedBox(height: 22),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: ZitlasTokens.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 15),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: const Text(
                'Turn on reminders',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5),
              ),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              style: TextButton.styleFrom(
                foregroundColor: ZitlasTokens.textMuted,
                padding: const EdgeInsets.symmetric(vertical: 13),
              ),
              child: const Text('Not Now'),
            ),
          ),
        ],
      ),
    );
  }
}

class _Point extends StatelessWidget {
  const _Point({required this.icon, required this.text});
  final String icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(icon, style: const TextStyle(fontSize: 14)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 12.5, color: ZitlasTokens.textMuted),
            ),
          ),
        ],
      ),
    );
  }
}
