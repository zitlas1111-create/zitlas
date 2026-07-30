import 'package:flutter/material.dart';

import '../../../../core/theme/zitlas_tokens.dart';
import '../../models/assessment_swot.dart';

const _kQuadrants = [
  (key: 'S', icon: '💪', title: 'Strengths', color: ZitlasTokens.success),
  (key: 'W', icon: '⚠️', title: 'Weaknesses', color: Color(0xFFF0A82E)),
  (key: 'O', icon: '🚀', title: 'Opportunities', color: ZitlasTokens.aiAccent),
  (key: 'T', icon: '🔴', title: 'Threats', color: ZitlasTokens.danger),
];

const _kScoreLabels = [
  ('nutrition', 'Nutrition'),
  ('activity', 'Activity'),
  ('sleep', 'Sleep'),
  ('habits', 'Habits'),
  ('mindset', 'Mindset'),
  ('consistency', 'Consistency'),
];

/// `#s-swot` / `renderSwot()` — 4 SWOT quadrant cards (top 3 items each),
/// the 6-dimension wellness score bars, the summary card, and the
/// "See Your Diet Plan →" CTA.
class SwotView extends StatelessWidget {
  const SwotView({super.key, required this.swot, required this.onNext});

  final AssessmentSwot? swot;
  final VoidCallback onNext;

  num _scoreOf(String key) => switch (key) {
    'nutrition' => swot!.scores.nutrition,
    'activity' => swot!.scores.activity,
    'sleep' => swot!.scores.sleep,
    'habits' => swot!.scores.habits,
    'mindset' => swot!.scores.mindset,
    _ => swot!.scores.consistency,
  };

  List<SwotItem> _itemsOf(String key) => switch (key) {
    'S' => swot!.strengths,
    'W' => swot!.weaknesses,
    'O' => swot!.opportunities,
    _ => swot!.threats,
  };

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text.rich(
            TextSpan(
              children: [
                const TextSpan(text: 'Your '),
                TextSpan(text: 'SWOT Profile', style: TextStyle(color: ZitlasTokens.primary)),
              ],
            ),
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: ZitlasTokens.textPrimary),
          ),
          const SizedBox(height: 4),
          Text(
            swot == null ? 'Analysing your strengths…' : 'Archetype: ${swot!.userArchetype}',
            style: const TextStyle(fontSize: 13, color: ZitlasTokens.textSecondary),
          ),
          const SizedBox(height: 18),
          if (swot != null) ...[
            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 2,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 0.85,
              children: _kQuadrants.map((q) {
                final items = _itemsOf(q.key).take(3).toList();
                return Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: ZitlasTokens.bgCard,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: q.color.withValues(alpha: 0.25)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(q.icon, style: const TextStyle(fontSize: 15)),
                          const SizedBox(width: 6),
                          Text(q.title, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: q.color)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Expanded(
                        child: SingleChildScrollView(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: items.map((it) {
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 6),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('✓ ${it.title}', style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: ZitlasTokens.textPrimary)),
                                    if (it.detail != null)
                                      Text(it.detail!, style: const TextStyle(fontSize: 10.5, color: ZitlasTokens.textSecondary)),
                                  ],
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 20),
            const Text('Wellness Scores', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: ZitlasTokens.textPrimary)),
            const SizedBox(height: 10),
            ZitlasCard(
              child: Column(
                children: _kScoreLabels.map((s) {
                  final val = _scoreOf(s.$1);
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        SizedBox(width: 80, child: Text(s.$2, style: const TextStyle(fontSize: 12, color: ZitlasTokens.textSecondary))),
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: (val / 100).clamp(0, 1).toDouble(),
                              minHeight: 8,
                              backgroundColor: ZitlasTokens.bgCardLight,
                              valueColor: const AlwaysStoppedAnimation(ZitlasTokens.primary),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        SizedBox(width: 28, child: Text('$val', textAlign: TextAlign.right, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700))),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 16),
            ZitlasCard(
              color: ZitlasTokens.bgCardLight,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(swot!.summary, style: const TextStyle(fontSize: 13, color: ZitlasTokens.textPrimary, height: 1.4)),
                  if (swot!.priorityAction.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text('→ ${swot!.priorityAction}', style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: ZitlasTokens.primaryDark)),
                  ],
                ],
              ),
            ),
          ],
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: onNext,
              style: ElevatedButton.styleFrom(
                backgroundColor: ZitlasTokens.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              child: const Text('See Your Diet Plan →', style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800)),
            ),
          ),
        ],
      ),
    );
  }
}
