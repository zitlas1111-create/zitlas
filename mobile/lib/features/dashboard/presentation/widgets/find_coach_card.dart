import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../dashboard_visuals.dart';
import 'section_header.dart';

/// What sits where "My Personal Coach" was, once there is no coach.
///
/// Shown to an athlete who has just ended coaching AND to one who never had a
/// coach — deliberately the same card, because there is nothing different to
/// say. An athlete who ended yesterday does not need reminding of it every
/// time they open the app, and a "your coaching ended" banner that lingers is
/// a worse experience than a clean invitation to start again.
///
/// Requesting a new coach needs no cleanup step: the backend's duplicate guard
/// only blocks an ACTIVE relationship, so ending one frees the athlete
/// immediately.
class FindCoachCard extends StatelessWidget {
  const FindCoachCard({super.key});

  @override
  Widget build(BuildContext context) {
    return DashboardCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionHeader(
            emoji: '🤝',
            title: 'Personal Coach',
            subtitle: 'One-to-one guidance from a verified expert',
          ),
          const SizedBox(height: 12),
          const Text(
            'A personal coach writes your diet and training around you, reviews '
            'the meals you photograph, and adjusts as you go.',
            style: TextStyle(
              fontSize: 12.5,
              height: 1.5,
              color: DashboardColors.textSecondary,
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => context.push('/experts'),
              style: ElevatedButton.styleFrom(
                backgroundColor: DashboardColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: const Text(
                'Find a Personal Coach',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
