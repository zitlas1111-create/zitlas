import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../theme/zitlas_tokens.dart';
import '../diet_region_repository.dart';
import '../location_service.dart';
import 'region_picker_sheet.dart';

/// Part A→D — the full location-personalization consent flow: explanation
/// → [Allow Location] (real Android permission dialog) → detect → confirm,
/// or [Choose Region Manually] → the state picker directly. Returns the
/// confirmed state name, or `null` if the athlete dismissed without
/// choosing (Diet generation must never be blocked on this).
Future<String?> runLocationSetupFlow(
  BuildContext context, {
  required String uid,
  required LocationService locationService,
  required DietRegionRepository regionRepo,
}) async {
  final action = await showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    isDismissible: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const _LocationConsentSheet(),
  );

  if (action == 'manual') {
    final picked = await showRegionPickerSheet(context);
    if (picked == null || !context.mounted) return null;
    await regionRepo.save(uid, picked, source: 'manual');
    return picked;
  }

  if (action != 'allow') return null; // dismissed — Diet generation proceeds with no region.

  if (kDebugMode) debugPrint('[REGION] permission = requesting…');
  final result = await locationService.resolveCurrentLocation();
  if (kDebugMode) debugPrint('[REGION] permission = ${result.outcome.name}');

  if (result.outcome != LocationOutcome.granted || result.location == null || !result.location!.hasRegion) {
    if (!context.mounted) return null;
    // Denied / disabled / timeout / geocode failure — offer the manual
    // fallback immediately rather than leaving the athlete stuck (#5/#22).
    final message = switch (result.outcome) {
      LocationOutcome.denied => "Location permission wasn't granted.",
      LocationOutcome.deniedForever => 'Location permission is blocked for ZITLAS.',
      LocationOutcome.serviceDisabled => 'Location services are turned off on this device.',
      LocationOutcome.timeout => "Couldn't get your location in time.",
      _ => "Couldn't determine your region from location.",
    };
    if (!context.mounted) return null;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$message You can pick your region manually.')));
    final picked = await showRegionPickerSheet(context);
    if (picked == null || !context.mounted) return null;
    await regionRepo.save(uid, picked, source: 'manual');
    return picked;
  }

  final detected = result.location!.state.isNotEmpty ? result.location!.state : result.location!.city;
  if (kDebugMode) debugPrint('[REGION] detected state = $detected');
  if (!context.mounted) return null;

  final confirmed = await showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _RegionConfirmSheet(detected: detected),
  );

  if (confirmed == 'change') {
    final picked = await showRegionPickerSheet(context, current: detected);
    if (picked == null || !context.mounted) return null;
    await regionRepo.save(uid, picked, source: 'manual');
    return picked;
  }
  if (confirmed != 'use') return null;

  await regionRepo.save(uid, detected, source: 'gps');
  return detected;
}

class _LocationConsentSheet extends StatelessWidget {
  const _LocationConsentSheet();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
      decoration: const BoxDecoration(color: ZitlasTokens.bgCard, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(color: ZitlasTokens.primary.withValues(alpha: 0.1), shape: BoxShape.circle),
              child: const Icon(Icons.location_on_rounded, size: 26, color: ZitlasTokens.primaryDark),
            ),
          ),
          const SizedBox(height: 14),
          const Text('Personalize your food recommendations', textAlign: TextAlign.center, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: ZitlasTokens.textPrimary)),
          const SizedBox(height: 8),
          const Text(
            "ZITLAS uses your approximate location to recommend foods that are commonly available and practical in your region.",
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: ZitlasTokens.textSecondary, height: 1.4),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              style: FilledButton.styleFrom(backgroundColor: ZitlasTokens.primary, padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
              onPressed: () => Navigator.of(context).pop('allow'),
              child: const Text('Allow Location', style: TextStyle(fontWeight: FontWeight.w800, color: Colors.white)),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14), side: const BorderSide(color: ZitlasTokens.borderSub)),
              onPressed: () => Navigator.of(context).pop('manual'),
              child: const Text('Choose Region Manually', style: TextStyle(fontWeight: FontWeight.w700, color: ZitlasTokens.textPrimary)),
            ),
          ),
        ],
      ),
    );
  }
}

class _RegionConfirmSheet extends StatelessWidget {
  const _RegionConfirmSheet({required this.detected});
  final String detected;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
      decoration: const BoxDecoration(color: ZitlasTokens.bgCard, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Preferred Food Region', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: ZitlasTokens.textPrimary)),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: ZitlasTokens.bgCardLight, borderRadius: BorderRadius.circular(14)),
            child: Row(
              children: [
                const Icon(Icons.location_on_rounded, color: ZitlasTokens.primaryDark, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('We detected:', style: TextStyle(fontSize: 11.5, color: ZitlasTokens.textMuted)),
                      Text(detected, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: ZitlasTokens.textPrimary)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            'ZITLAS will prioritize foods commonly available in this region.',
            style: TextStyle(fontSize: 12.5, color: ZitlasTokens.textSecondary),
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              style: FilledButton.styleFrom(backgroundColor: ZitlasTokens.primary, padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
              onPressed: () => Navigator.of(context).pop('use'),
              child: Text('Use $detected', style: const TextStyle(fontWeight: FontWeight.w800, color: Colors.white)),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14), side: const BorderSide(color: ZitlasTokens.borderSub)),
              onPressed: () => Navigator.of(context).pop('change'),
              child: const Text('Change Region', style: TextStyle(fontWeight: FontWeight.w700, color: ZitlasTokens.textPrimary)),
            ),
          ),
        ],
      ),
    );
  }
}
