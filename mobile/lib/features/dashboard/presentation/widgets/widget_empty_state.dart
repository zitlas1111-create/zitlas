import 'package:flutter/material.dart';

import '../dashboard_visuals.dart';

/// `.widget-empty-state` / `.widget-empty-cta` — shared empty-state pattern
/// used by the SWOT and Training widgets when their backing data doesn't
/// exist yet (no assessment / no workout plan).
class WidgetEmptyState extends StatelessWidget {
  const WidgetEmptyState({
    super.key,
    required this.text,
    required this.ctaLabel,
    required this.onTap,
  });

  final String text;
  final String ctaLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 12),
      child: Column(
        children: [
          Text(
            text,
            textAlign: TextAlign.center,
            style: const TextStyle(color: DashboardColors.textSecondary, fontSize: 13, height: 1.4),
          ),
          const SizedBox(height: 14),
          GestureDetector(
            onTap: onTap,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
              decoration: BoxDecoration(
                color: DashboardColors.primary,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                ctaLabel,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
