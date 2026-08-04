import 'package:flutter/material.dart';

import '../../../../core/theme/zitlas_tokens.dart';
import '../../assessment_controller.dart';
import '../../data/assessment_repository.dart';
import '../../models/snapshot_card.dart';

Color _accentColor(String accent) => switch (accent) {
  'green' => ZitlasTokens.success,
  'red' => ZitlasTokens.danger,
  'yellow' => const Color(0xFFF0A82E),
  'orange' => ZitlasTokens.primary,
  'blue' => ZitlasTokens.aiAccent,
  'purple' => const Color(0xFF8B5CF6),
  _ => ZitlasTokens.textMuted, // 'info'
};

/// `#s-snapshot` / `renderSnapshot()` — the goal-specific summary card, the
/// metric card grid (tap the ⓘ to expand), the AI coach note, and the
/// "View SWOT Analysis →" CTA. Shows the website's own fallback text when
/// generation failed (`apiResult == null`).
class SnapshotView extends StatelessWidget {
  const SnapshotView({super.key, required this.controller, required this.onNext});

  final AssessmentController controller;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final result = controller.apiResult;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text.rich(
            TextSpan(
              children: [
                const TextSpan(text: 'Your '),
                TextSpan(text: 'Fitness Snapshot', style: TextStyle(color: ZitlasTokens.primary)),
              ],
            ),
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: ZitlasTokens.textPrimary),
          ),
          const SizedBox(height: 4),
          const Text(
            'Personalised targets based on your body & goals',
            style: TextStyle(fontSize: 13, color: ZitlasTokens.textSecondary),
          ),
          const SizedBox(height: 18),
          if (result == null)
            _GenerationFailed(
              message: controller.submitErrorMessage ??
                  'Could not load data. Check your connection and retry.',
              busy: controller.submitting,
              onRetry: controller.retryGeneration,
            )
          else ...[
            if (controller.persistErrorMessage != null) ...[
              _PersistWarning(
                message: controller.persistErrorMessage!,
                onRetry: controller.retryPersist,
              ),
              const SizedBox(height: 14),
            ],
            _buildSummary(result),
            const SizedBox(height: 18),
            _CardGrid(cards: _cardsFor(result)),
            const SizedBox(height: 18),
            _buildCoachNote(result),
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
              child: const Text('View SWOT Analysis →', style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800)),
            ),
          ),
        ],
      ),
    );
  }

  List<SnapshotCard> _cardsFor(AssessmentResult result) {
    if (controller.isTransformation) return buildTransformationCards(result.calculations);
    if (controller.isGeneralFitness) {
      return buildGeneralFitnessCards(
        result.calculations,
        fitnessLevel: (controller.answers['fitness_level'] as String?) ?? 'beginner',
        healthGoals: (controller.answers['health_goals'] as List?)?.cast<String>() ?? const [],
      );
    }
    return buildDefaultCards(result.calculations, isMuscle: controller.isMuscleGain);
  }

  Widget _buildSummary(AssessmentResult result) {
    final SnapshotSummary summary;
    if (controller.isTransformation) {
      summary = buildTransformationSummary(result.calculations);
    } else if (controller.isGeneralFitness) {
      summary = buildGeneralFitnessSummary(
        result.calculations,
        fitnessLevel: (controller.answers['fitness_level'] as String?) ?? 'beginner',
      );
    } else {
      summary = buildDefaultSummary(result.calculations, isMuscle: controller.isMuscleGain);
    }

    return ZitlasCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(summary.icon, style: const TextStyle(fontSize: 24)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(summary.heading, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: ZitlasTokens.textPrimary)),
                    Text(summary.sub, style: const TextStyle(fontSize: 11.5, color: ZitlasTokens.textSecondary)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 3,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 0.95,
            children: summary.items.map((it) {
              return Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: it.highlight ? const Color(0x1FFF9800) : ZitlasTokens.bgCardLight,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(it.emoji, style: const TextStyle(fontSize: 16)),
                    const SizedBox(height: 4),
                    Text(
                      it.value,
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: ZitlasTokens.textPrimary),
                    ),
                    Text(
                      it.label,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      style: const TextStyle(fontSize: 9, color: ZitlasTokens.textMuted),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildCoachNote(AssessmentResult result) {
    final CoachNote note;
    if (controller.isTransformation) {
      note = buildTransformationCoachNote(result.calculations);
    } else if (controller.isGeneralFitness) {
      note = buildGeneralFitnessCoachNote(
        result.calculations,
        healthGoals: (controller.answers['health_goals'] as List?)?.cast<String>() ?? const [],
      );
    } else {
      note = buildDefaultCoachNote(result.calculations, isMuscle: controller.isMuscleGain);
    }

    return ZitlasCard(
      color: ZitlasTokens.bgCardLight,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(note.avatar, style: const TextStyle(fontSize: 22)),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(note.name, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: ZitlasTokens.textPrimary)),
                  Text(note.sub, style: const TextStyle(fontSize: 11, color: ZitlasTokens.textSecondary)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),
          ...note.paragraphs.map((p) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _RichHtmlText(p, style: const TextStyle(fontSize: 12.5, color: ZitlasTokens.textSecondary, height: 1.4)),
              )),
          ...note.bullets.map((b) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: _RichHtmlText(b, style: const TextStyle(fontSize: 12.5, color: ZitlasTokens.textSecondary, height: 1.4)),
              )),
          const SizedBox(height: 6),
          _RichHtmlText(
            note.result,
            style: const TextStyle(fontSize: 12.5, color: ZitlasTokens.textPrimary, fontWeight: FontWeight.w600, height: 1.4),
          ),
        ],
      ),
    );
  }
}

/// Replaces the website's single generic "Could not load data" dead end.
/// The message is classified by failure type (see
/// `AssessmentController.submitErrorMessage`) and — unlike the website —
/// actually offers the retry its own copy promises, reusing the answers
/// already collected so the questionnaire never has to be retaken.
class _GenerationFailed extends StatelessWidget {
  const _GenerationFailed({required this.message, required this.busy, required this.onRetry});

  final String message;
  final bool busy;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return ZitlasCard(
      child: Column(
        children: [
          const Text('⚠️', style: TextStyle(fontSize: 30)),
          const SizedBox(height: 10),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: ZitlasTokens.textSecondary, fontSize: 13, height: 1.45),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: busy ? null : onRetry,
              style: ElevatedButton.styleFrom(
                backgroundColor: ZitlasTokens.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('Try Again', style: TextStyle(fontWeight: FontWeight.w800)),
            ),
          ),
        ],
      ),
    );
  }
}

/// Generation succeeded but the Firestore write didn't — the plan is shown
/// (it's real), with an honest warning that it isn't saved yet.
class _PersistWarning extends StatelessWidget {
  const _PersistWarning({required this.message, required this.onRetry});

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0x1FF0A82E),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0x40F0A82E)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              message,
              style: const TextStyle(fontSize: 12.5, color: ZitlasTokens.textPrimary, height: 1.4),
            ),
          ),
          TextButton(
            onPressed: onRetry,
            style: TextButton.styleFrom(foregroundColor: ZitlasTokens.primaryDark),
            child: const Text('Retry', style: TextStyle(fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
  }
}

class _CardGrid extends StatefulWidget {
  const _CardGrid({required this.cards});
  final List<SnapshotCard> cards;

  @override
  State<_CardGrid> createState() => _CardGridState();
}

class _CardGridState extends State<_CardGrid> {
  String? _expandedId;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: widget.cards.map((c) {
        final expanded = _expandedId == c.id;
        final color = _accentColor(c.accent);
        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          decoration: BoxDecoration(
            color: ZitlasTokens.bgCard,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: color.withValues(alpha: 0.25)),
            boxShadow: kZitlasCardShadow,
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(8)),
                      child: Text(c.type, style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800, color: color, letterSpacing: 0.3)),
                    ),
                    const Spacer(),
                    GestureDetector(
                      onTap: () => setState(() => _expandedId = expanded ? null : c.id),
                      child: const Icon(Icons.info_outline, size: 18, color: ZitlasTokens.textMuted),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Text(c.icon, style: const TextStyle(fontSize: 26)),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
                      child: Text(c.badge, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: color)),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(c.name, style: const TextStyle(fontSize: 12.5, color: ZitlasTokens.textSecondary, fontWeight: FontWeight.w600)),
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(text: '${c.value} ', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: ZitlasTokens.textPrimary)),
                      TextSpan(text: c.sub, style: const TextStyle(fontSize: 11, color: ZitlasTokens.textMuted)),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                Text.rich(
                  TextSpan(children: [
                    const TextSpan(text: 'Why? ', style: TextStyle(fontWeight: FontWeight.w800)),
                    TextSpan(text: c.why),
                  ]),
                  style: const TextStyle(fontSize: 12, color: ZitlasTokens.textSecondary, height: 1.35),
                ),
                if (expanded) ...[
                  const Divider(height: 20, color: ZitlasTokens.borderSub),
                  Text(c.expandTitle, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: ZitlasTokens.textPrimary)),
                  const SizedBox(height: 6),
                  _RichHtmlText(c.expand, style: const TextStyle(fontSize: 12, color: ZitlasTokens.textSecondary, height: 1.4)),
                ],
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}

/// The website injects raw `<strong>…</strong>` HTML into these strings;
/// this renders the same text with those spans bolded instead of pulling in
/// a full HTML-rendering dependency for two tags.
class _RichHtmlText extends StatelessWidget {
  const _RichHtmlText(this.text, {required this.style});
  final String text;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    final spans = <InlineSpan>[];
    final pattern = RegExp('<strong>(.*?)</strong>', dotAll: true);
    var last = 0;
    for (final m in pattern.allMatches(text)) {
      if (m.start > last) spans.add(TextSpan(text: text.substring(last, m.start)));
      spans.add(TextSpan(text: m.group(1), style: const TextStyle(fontWeight: FontWeight.w800)));
      last = m.end;
    }
    if (last < text.length) spans.add(TextSpan(text: text.substring(last)));
    return Text.rich(TextSpan(children: spans), style: style);
  }
}
