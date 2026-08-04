import 'package:flutter/material.dart';

import '../../../../core/theme/zitlas_tokens.dart';

const _kGoals = [
  (icon: '🔥', name: 'Lose Weight', tag: 'AI-powered', value: 'lose_weight'),
  (icon: '💪', name: 'Gain Muscle', tag: 'AI-powered', value: 'muscle_gain'),
  (icon: '⚡', name: 'Transformation', tag: 'AI-POWERED', value: 'transformation'),
  (icon: '❤️', name: 'General Fitness', tag: 'AI-POWERED', value: 'general_fitness'),
];

/// `#s-goal` — "What's your main goal?" 4-card grid + "Step 1 of 3" progress.
class GoalSelectionView extends StatelessWidget {
  const GoalSelectionView({
    super.key,
    required this.selectedGoal,
    required this.onSelect,
    required this.onBack,
    required this.onNext,
  });

  final String selectedGoal;
  final ValueChanged<String> onSelect;
  final VoidCallback onBack;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 20, 4),
          child: Row(
            children: [
              IconButton(onPressed: onBack, icon: const Icon(Icons.arrow_back, color: ZitlasTokens.textPrimary)),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Step 1 of 3',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: ZitlasTokens.textMuted),
                    ),
                    const SizedBox(height: 4),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: const LinearProgressIndicator(
                        value: 0.33,
                        minHeight: 5,
                        backgroundColor: ZitlasTokens.bgCardLight,
                        valueColor: AlwaysStoppedAnimation(ZitlasTokens.primary),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            child: Column(
              children: [
                Image.asset('assets/images/zino.png', width: 64, height: 64),
                const SizedBox(height: 12),
                const Text(
                  "What's your main goal?",
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: ZitlasTokens.textPrimary),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Choose one to get started',
                  style: TextStyle(fontSize: 13, color: ZitlasTokens.textSecondary),
                ),
                const SizedBox(height: 20),
                GridView.count(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisCount: 2,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 1.05,
                  children: _kGoals.map((g) {
                    final selected = g.value == selectedGoal;
                    return GestureDetector(
                      onTap: () => onSelect(g.value),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: selected ? const Color(0x1FFF9800) : ZitlasTokens.bgCard,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: selected ? ZitlasTokens.primary : ZitlasTokens.border,
                            width: selected ? 2 : 1,
                          ),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(g.icon, style: const TextStyle(fontSize: 30)),
                            const SizedBox(height: 8),
                            Text(
                              g.name,
                              textAlign: TextAlign.center,
                              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: ZitlasTokens.textPrimary),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              g.tag,
                              style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700, color: ZitlasTokens.primaryDark, letterSpacing: 0.4),
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 24),
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
                    child: const Text('Start My Plan →', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
