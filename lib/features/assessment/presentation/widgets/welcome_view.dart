import 'package:flutter/material.dart';

import '../../../../core/theme/zitlas_tokens.dart';

/// `#s-welcome` — exact copy: "Meet Zino", "Your Personal AI Nutrition
/// Assistant", the description, the "~3-4 minutes" note, and the CTA.
class WelcomeView extends StatelessWidget {
  const WelcomeView({super.key, required this.onStart});

  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 120,
              height: 120,
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: ZitlasTokens.primary, width: 3),
              ),
              child: ClipOval(
                child: Image.asset('assets/images/zino.png', fit: BoxFit.cover),
              ),
            ),
            const SizedBox(height: 20),
            Text.rich(
              TextSpan(
                children: [
                  const TextSpan(text: 'Meet '),
                  TextSpan(text: 'Zino', style: TextStyle(color: ZitlasTokens.primary)),
                ],
              ),
              style: const TextStyle(
                fontSize: 30,
                fontWeight: FontWeight.w900,
                color: ZitlasTokens.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Your Personal AI Nutrition Assistant',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: ZitlasTokens.textSecondary),
            ),
            const SizedBox(height: 14),
            const Text(
              "I'll ask a few questions, then build your personalised meal & fitness plan — backed by real research.",
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: ZitlasTokens.textSecondary, height: 1.5),
            ),
            const SizedBox(height: 14),
            const Text(
              '⏱ Takes about 3–4 minutes',
              style: TextStyle(fontSize: 13, color: ZitlasTokens.textMuted, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 28),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: onStart,
                style: ElevatedButton.styleFrom(
                  backgroundColor: ZitlasTokens.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                child: const Text(
                  "Let's Start →",
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
