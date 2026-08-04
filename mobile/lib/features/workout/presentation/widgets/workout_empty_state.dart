import 'package:flutter/material.dart';

import '../../../../core/theme/zitlas_tokens.dart';

/// `showError()` (weekly-plan.js) — exact copy, including the website's own
/// wording ("AI Nutrition assessment" — the website's literal text even
/// though this is the Training page, not Diet; preserved verbatim per exact
/// text parity, not corrected).
class WorkoutEmptyState extends StatelessWidget {
  const WorkoutEmptyState({super.key, required this.onStartAssessment, required this.onBack});

  final VoidCallback onStartAssessment;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: ZitlasCard(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('📋', style: TextStyle(fontSize: 40)),
              const SizedBox(height: 12),
              const Text(
                'No Plan Found',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: ZitlasTokens.textPrimary),
              ),
              const SizedBox(height: 8),
              const Text(
                'Complete the AI Nutrition assessment with Zino to generate your personalised 7-day plan.',
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
                  child: const Text('Start with Zino →', style: TextStyle(fontWeight: FontWeight.w700)),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: onBack,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: ZitlasTokens.textSecondary,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: const Text('← Back to Dashboard'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
