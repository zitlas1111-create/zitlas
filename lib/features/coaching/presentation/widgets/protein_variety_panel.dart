import 'package:flutter/material.dart';

import '../../../../core/theme/zitlas_tokens.dart';
import '../../models/protein_variety.dart';

/// Weekly protein sources, with counts (Step 5).
///
/// Shows the spread whether or not there is a problem — a coach building a
/// week wants to see the balance forming, not only be told once it has gone
/// wrong. The warning appears on top when one source dominates.
class ProteinVarietyPanel extends StatelessWidget {
  const ProteinVarietyPanel({super.key, required this.report});

  final ProteinVarietyReport report;

  @override
  Widget build(BuildContext context) {
    if (report.usage.isEmpty && report.mealsWithoutProtein == 0) {
      return const SizedBox.shrink();
    }

    final warning = report.warning;

    return Container(
      padding: const EdgeInsets.fromLTRB(13, 11, 13, 12),
      decoration: BoxDecoration(
        color: ZitlasTokens.bgCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: warning != null
              ? ZitlasTokens.primary.withValues(alpha: 0.45)
              : ZitlasTokens.borderSub,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'WEEKLY PROTEIN SOURCES',
                style: TextStyle(
                  fontSize: 9.5,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.7,
                  color: ZitlasTokens.textMuted,
                ),
              ),
              const Spacer(),
              Text(
                '${report.mealsWithProtein} meals',
                style: const TextStyle(fontSize: 10.5, color: ZitlasTokens.textMuted),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (report.usage.isEmpty)
            const Text(
              'No protein source identified yet in this week.',
              style: TextStyle(fontSize: 11.5, color: ZitlasTokens.textSecondary),
            )
          else
            for (final usage in report.usage)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    Text(usage.source.icon, style: const TextStyle(fontSize: 13)),
                    const SizedBox(width: 7),
                    SizedBox(
                      width: 104,
                      child: Text(
                        usage.source.label,
                        style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: ZitlasTokens.textPrimary,
                        ),
                      ),
                    ),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(5),
                        child: LinearProgressIndicator(
                          value: report.mealsWithProtein == 0
                              ? 0
                              : usage.mealCount / report.mealsWithProtein,
                          minHeight: 6,
                          backgroundColor: ZitlasTokens.borderSub,
                          valueColor: AlwaysStoppedAnimation(
                            // The dominant source is tinted when it is the one
                            // causing the warning, so the bar and the sentence
                            // point at the same thing.
                            warning != null && usage == report.dominant
                                ? ZitlasTokens.primary
                                : ZitlasTokens.success,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 46,
                      child: Text(
                        '${usage.mealCount} ${usage.mealCount == 1 ? "meal" : "meals"}',
                        textAlign: TextAlign.right,
                        style: const TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          color: ZitlasTokens.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          if (report.mealsWithoutProtein > 0)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                '${report.mealsWithoutProtein} '
                '${report.mealsWithoutProtein == 1 ? "meal has" : "meals have"} '
                'no identified protein source.',
                style: const TextStyle(fontSize: 10.5, color: ZitlasTokens.textMuted),
              ),
            ),
          if (warning != null) ...[
            const SizedBox(height: 9),
            Container(
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(
                color: ZitlasTokens.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '⚠ Low protein variety',
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w900,
                      color: ZitlasTokens.primary,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    warning,
                    style: const TextStyle(
                      fontSize: 11,
                      height: 1.45,
                      color: ZitlasTokens.textSecondary,
                    ),
                  ),
                  if (report.unusedSources.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 5,
                      runSpacing: 5,
                      children: [
                        for (final s in report.unusedSources.take(5))
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                            decoration: BoxDecoration(
                              color: ZitlasTokens.bgCard,
                              borderRadius: BorderRadius.circular(7),
                              border: Border.all(color: ZitlasTokens.borderSub),
                            ),
                            child: Text(
                              '${s.icon} ${s.label}',
                              style: const TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w700,
                                color: ZitlasTokens.textPrimary,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
