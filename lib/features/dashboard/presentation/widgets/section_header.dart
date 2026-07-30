import 'package:flutter/material.dart';

import '../dashboard_visuals.dart';

/// `.section-header` — badge + title + subtitle, optional trailing link
/// button (`.view-link-btn`). Shared by SWOT/Activity/DailyScore/Wellness/
/// Training section headers on `dashboard.html`.
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.emoji,
    required this.title,
    required this.subtitle,
    this.trailingText,
    this.onTrailingTap,
  });

  final String emoji;
  final String title;
  final String subtitle;
  final String? trailingText;
  final VoidCallback? onTrailingTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: const Color(0x1FFF9800),
            border: Border.all(color: const Color(0x33FF9800)),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(emoji, style: const TextStyle(fontSize: 18)),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: DashboardColors.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: DashboardColors.primary,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        if (trailingText != null)
          GestureDetector(
            onTap: onTrailingTap,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                border: Border.all(color: const Color(0x40FF9800)),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                trailingText!,
                style: const TextStyle(
                  color: DashboardColors.primary,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
