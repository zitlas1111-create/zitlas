import 'package:flutter/material.dart';

import '../../../../core/theme/zitlas_tokens.dart';

/// `_pcRenderBanner()` — shown whenever a coach's training plan is
/// overriding the AI plan. The verified-expert badge integration
/// (`ZitlasBadge`) is deliberately not built this phase (no shared Flutter
/// badge widget exists yet — same scope decision the Diet feature already
/// made); the banner text and both status branches are otherwise exact.
class WorkoutCoachBanner extends StatelessWidget {
  const WorkoutCoachBanner({super.key, required this.coachName, required this.ended});

  final String coachName;
  final bool ended;

  @override
  Widget build(BuildContext context) {
    return ZitlasCard(
      margin: const EdgeInsets.only(bottom: 16),
      color: const Color(0xE6E8F4FF),
      child: Text.rich(
        TextSpan(
          children: ended
              ? const [
                  TextSpan(text: '👨‍🏫 Coaching ended — you’re keeping your coach’s last training plan.'),
                ]
              : [
                  const TextSpan(text: '👨‍🏫 Training managed by '),
                  TextSpan(text: coachName, style: const TextStyle(fontWeight: FontWeight.w800)),
                  const TextSpan(text: ' — updates appear here instantly.'),
                ],
        ),
        style: const TextStyle(fontSize: 12.5, color: ZitlasTokens.textPrimary, height: 1.4),
      ),
    );
  }
}
