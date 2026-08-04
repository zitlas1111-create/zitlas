import 'package:flutter/material.dart';

import '../../../../core/theme/zitlas_tokens.dart';
import '../../models/diet_day.dart';

/// The 7 day-selector pills at the top of `diet.js`'s day view — tapping one
/// switches which `DietDay` the rest of the screen renders. Label is the
/// first 3 letters of `day.day` ("Monday" -> "Mon"), same abbreviation the
/// website uses.
class DietDaySelector extends StatelessWidget {
  const DietDaySelector({
    super.key,
    required this.days,
    required this.selectedIndex,
    required this.onSelect,
  });

  final List<DietDay> days;
  final int selectedIndex;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 64,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: days.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final day = days[index];
          final selected = index == selectedIndex;
          final label = day.day.isEmpty
              ? '${index + 1}'
              : day.day.substring(0, day.day.length >= 3 ? 3 : day.day.length);

          return GestureDetector(
            onTap: () => onSelect(index),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 56,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: selected ? ZitlasTokens.primary : Colors.white.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: selected ? ZitlasTokens.primary : ZitlasTokens.border,
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    label.toUpperCase(),
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: selected ? Colors.white : ZitlasTokens.textPrimary,
                    ),
                  ),
                  if (day.dayType != null)
                    Text(
                      day.dayType!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w600,
                        color: selected ? Colors.white70 : ZitlasTokens.textMuted,
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
