import 'package:flutter/material.dart';

import '../../../../core/theme/zitlas_tokens.dart';
import '../../models/diet_day.dart';

/// The selected day's theme + nutrition tip strip, shown above the meal
/// cards — matches `diet.js`'s per-day banner (`.day-theme` / `.nutrition-tip`).
class DietDayFocusCard extends StatelessWidget {
  const DietDayFocusCard({super.key, required this.day});

  final DietDay day;

  @override
  Widget build(BuildContext context) {
    if (day.theme == null && day.nutritionTip == null) return const SizedBox.shrink();

    return ZitlasCard(
      color: ZitlasTokens.bgCardLight,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (day.theme != null)
            Text(
              day.theme!,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: ZitlasTokens.textPrimary),
            ),
          if (day.nutritionTip != null) ...[
            if (day.theme != null) const SizedBox(height: 6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('💡 ', style: TextStyle(fontSize: 13)),
                Expanded(
                  child: Text(
                    day.nutritionTip!,
                    style: const TextStyle(fontSize: 12.5, color: ZitlasTokens.textSecondary, height: 1.4),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
