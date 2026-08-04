import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../theme/zitlas_tokens.dart';
import '../step_platform.dart';
import '../step_tracking_service.dart';

/// ZITLAS's own explanation, shown BEFORE any OS permission dialog.
///
/// Asking the system for health data cold is how apps get denied — the
/// athlete has no idea what they're granting or why. This sheet states the
/// purpose in ZITLAS's own words first; only "Enable Step Tracking" goes on
/// to the real Android/Health Connect flow. "Not Now" records the decision so
/// nothing re-prompts on the next launch.
Future<bool> showStepConsentSheet(
  BuildContext context, {
  required StepTrackingService service,
}) async {
  final accepted = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const _StepConsentSheet(),
  );
  if (accepted != true) return false;
  if (!context.mounted) return false;

  final enabled = await service.enableTracking(
    onNeedsActivityRecognition: _requestActivityRecognition,
  );

  if (!enabled && context.mounted) {
    await _showUnavailableDialog(context, service);
  }
  return enabled;
}

/// ACTIVITY_RECOGNITION for the hardware-sensor path. permission_handler is
/// already a project dependency and handles the API-29 gate for us.
Future<bool> _requestActivityRecognition() async {
  final status = await Permission.activityRecognition.request();
  return status.isGranted;
}

/// Shown when the flow completed without producing a usable source — always
/// with a real next step rather than a dead end.
Future<void> _showUnavailableDialog(
  BuildContext context,
  StepTrackingService service,
) async {
  final status = await service.platformStatus();
  if (!context.mounted) return;

  final (String title, String body, bool offerSettings) = switch (status) {
    StepPlatformStatus(healthConnect: HealthConnectAvailability.updateRequired) => (
        'Health Connect needs an update',
        'Update Health Connect from the Play Store, then enable step tracking '
            'again.',
        true,
      ),
    StepPlatformStatus(anySourcePossible: false) => (
        'Step tracking unavailable',
        "This device doesn't report step data to ZITLAS. Everything else in "
            'your plan works as normal.',
        false,
      ),
    _ => (
        'Permission needed',
        'ZITLAS needs permission to read your step activity. You can grant it '
            'any time from Profile → Step Tracking.',
        status.healthConnect == HealthConnectAvailability.available,
      ),
  };

  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: ZitlasTokens.bgCard,
      title: Text(title, style: const TextStyle(color: ZitlasTokens.textPrimary)),
      content: Text(body, style: const TextStyle(color: ZitlasTokens.textSecondary)),
      actions: [
        if (offerSettings)
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              const StepPlatform().openHealthConnectSettings();
            },
            child: const Text('Open settings'),
          ),
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('OK'),
        ),
      ],
    ),
  );
}

class _StepConsentSheet extends StatelessWidget {
  const _StepConsentSheet();

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
          const Text('👣', style: TextStyle(fontSize: 34)),
          const SizedBox(height: 12),
          const Text(
            'Track your daily activity',
            style: TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.w800,
              color: ZitlasTokens.textPrimary,
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            'Allow ZITLAS to read your step activity so we can track your '
            'daily movement, progress and fitness goals.',
            style: TextStyle(
              fontSize: 13.5,
              height: 1.5,
              color: ZitlasTokens.textSecondary,
            ),
          ),
          const SizedBox(height: 16),
          const _Point(icon: '🔒', text: 'Only step activity — no other health data.'),
          const _Point(icon: '📵', text: 'Works offline. Your steps stay on your device.'),
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
                'Enable Step Tracking',
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
