/// `swot` in the `/api/assessment/generate-plan` response — rule-based,
/// deterministic (`generate_swot()` in `assessment_service.py`, no LLM
/// call). Field names match `renderSwot()` in `ai-coach.js` exactly.
class SwotItem {
  const SwotItem({required this.title, this.detail});
  final String title;
  final String? detail;

  factory SwotItem.fromDynamic(dynamic v) {
    if (v is Map) {
      final m = v.cast<String, dynamic>();
      return SwotItem(title: (m['title'] as String?) ?? '', detail: m['detail'] as String?);
    }
    return SwotItem(title: v.toString());
  }
}

class SwotScores {
  const SwotScores({
    this.nutrition = 0,
    this.activity = 0,
    this.sleep = 0,
    this.habits = 0,
    this.mindset = 0,
    this.consistency = 0,
  });

  final num nutrition;
  final num activity;
  final num sleep;
  final num habits;
  final num mindset;
  final num consistency;

  factory SwotScores.fromMap(Map<String, dynamic>? m) {
    if (m == null) return const SwotScores();
    return SwotScores(
      nutrition: (m['nutrition'] as num?) ?? 0,
      activity: (m['activity'] as num?) ?? 0,
      sleep: (m['sleep'] as num?) ?? 0,
      habits: (m['habits'] as num?) ?? 0,
      mindset: (m['mindset'] as num?) ?? 0,
      consistency: (m['consistency'] as num?) ?? 0,
    );
  }
}

class AssessmentSwot {
  const AssessmentSwot({
    required this.strengths,
    required this.weaknesses,
    required this.opportunities,
    required this.threats,
    required this.scores,
    required this.userArchetype,
    required this.summary,
    required this.priorityAction,
  });

  final List<SwotItem> strengths;
  final List<SwotItem> weaknesses;
  final List<SwotItem> opportunities;
  final List<SwotItem> threats;
  final SwotScores scores;
  final String userArchetype;
  final String summary;
  final String priorityAction;

  factory AssessmentSwot.fromMap(Map<String, dynamic> m) {
    final swot = (m['swot'] as Map?)?.cast<String, dynamic>() ?? const {};
    List<SwotItem> listOf(String key) =>
        (swot[key] as List?)?.map(SwotItem.fromDynamic).toList() ?? const [];

    return AssessmentSwot(
      strengths: listOf('strengths'),
      weaknesses: listOf('weaknesses'),
      opportunities: listOf('opportunities'),
      threats: listOf('threats'),
      scores: SwotScores.fromMap((m['scores'] as Map?)?.cast<String, dynamic>()),
      userArchetype: (m['user_archetype'] as String?) ?? 'Unknown',
      summary: (m['summary'] as String?) ?? '',
      priorityAction: (m['priority_action'] as String?) ?? '',
    );
  }
}
