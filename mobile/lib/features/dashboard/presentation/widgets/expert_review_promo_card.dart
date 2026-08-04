import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../dashboard_controller.dart';
import '../dashboard_visuals.dart';

/// `#expertReviewPromoMount` / `expert-review-promo.js`. Eligibility
/// (`DashboardController.expertPromoEligible`) matches `baseEligible()` +
/// `refineWithCoachingStatus()` exactly: has an AI plan, isn't already an
/// expert-reviewed plan, and no active Personal Coaching relationship.
/// Copy/price ported verbatim from the website.
class ExpertReviewPromoCard extends StatelessWidget {
  const ExpertReviewPromoCard({super.key});

  @override
  Widget build(BuildContext context) {
    final eligible = context.watch<DashboardController>().expertPromoEligible;
    if (!eligible) return const SizedBox.shrink();

    return DashboardCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Get Expert Review',
                  style: TextStyle(
                    color: DashboardColors.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: DashboardColors.primary,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text(
                  '₹149',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'A certified expert reviews and personalises your AI plan.',
            style: TextStyle(color: DashboardColors.textSecondary, fontSize: 12.5, height: 1.4),
          ),
          const SizedBox(height: 10),
          const _Bullet('Personalised diet adjustments'),
          const _Bullet('Workout corrections & form fixes'),
          const _Bullet('30-minute 1-on-1 consultation'),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 46,
            child: ElevatedButton(
              onPressed: () => context.go('/experts'),
              style: ElevatedButton.styleFrom(
                backgroundColor: DashboardColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: const Text(
                'Get Expert Review — ₹149 →',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Bullet extends StatelessWidget {
  const _Bullet(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('✓ ', style: TextStyle(color: DashboardColors.success, fontSize: 12)),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(color: DashboardColors.textSecondary, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}
