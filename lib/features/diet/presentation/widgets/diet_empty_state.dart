import 'package:flutter/material.dart';

import '../../../../core/theme/zitlas_tokens.dart';

/// "No Plan Yet" state — shown when there is no valid `dietPlan` for this
/// athlete (never a fake/hardcoded plan). CTA routes to the assessment flow,
/// the only real way a Diet plan gets generated.
class DietEmptyState extends StatelessWidget {
  const DietEmptyState({super.key, required this.onStartAssessment});

  final VoidCallback onStartAssessment;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: ZitlasCard(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('🥗', style: TextStyle(fontSize: 40)),
              const SizedBox(height: 12),
              const Text(
                'No Diet Plan Yet',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: ZitlasTokens.textPrimary),
              ),
              const SizedBox(height: 8),
              const Text(
                'Complete your assessment to generate a personalized diet plan.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: ZitlasTokens.textSecondary, height: 1.4),
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: onStartAssessment,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: ZitlasTokens.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: const Text('Start Assessment', style: TextStyle(fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
