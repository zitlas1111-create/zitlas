/// Models + the deterministic adjustment engine for the "❤️ How are you
/// feeling today?" card, ported field-for-field and rule-for-rule from
/// `frontend/assets/js/health-status.js`.
///
/// The engine is deliberately rule-based (no LLM call), exactly like the
/// website: the same report must always produce the same adjustment.
library;

class HealthStatusOption {
  const HealthStatusOption(this.key, this.label);
  final String key;
  final String label;
}

/// `STATUSES` (health-status.js:28-36) — order and labels are exact.
const healthStatuses = <HealthStatusOption>[
  HealthStatusOption('great', '😊 Feeling Great'),
  HealthStatusOption('unwell', '😐 Slightly Unwell'),
  HealthStatusOption('sick', '🤒 Sick Today'),
  HealthStatusOption('injured', '🤕 Injured'),
  HealthStatusOption('poor_sleep', '😴 Poor Sleep'),
  HealthStatusOption('stress', '😰 High Stress'),
  HealthStatusOption('other', '➕ Other'),
];

/// `SYMPTOMS` (health-status.js:37-39).
const healthSymptoms = <String>[
  'Fever', 'Cold', 'Cough', 'Headache', 'Vomiting', 'Diarrhea',
  'Food Poisoning', 'Sore Throat', 'Stomach Pain', 'Weakness', 'Fatigue',
  'Body Pain', 'Chest Pain', 'Difficulty Breathing', 'Other',
];

/// `BODY_PARTS` (health-status.js:40-41).
const healthBodyParts = <String>[
  'Neck', 'Shoulder', 'Chest', 'Back', 'Lower Back', 'Elbow',
  'Wrist', 'Hip', 'Knee', 'Ankle', 'Foot',
];

String healthStatusLabel(String key) =>
    healthStatuses.firstWhere((s) => s.key == key, orElse: () => HealthStatusOption(key, key)).label;

const healthStatusIcons = <String, String>{
  'great': '😊', 'unwell': '😐', 'sick': '🤒', 'injured': '🤕',
  'poor_sleep': '😴', 'stress': '😰', 'other': '➕',
};

/// The in-progress report the bottom sheet builds — `draft` on the website.
class HealthReport {
  HealthReport({
    required this.status,
    this.symptoms = const [],
    this.bodyParts = const [],
    this.severity,
    this.painLevel = 5,
    this.sleepHours = 6,
    this.stressLevel = 7,
    this.note = '',
  });

  final String status;
  List<String> symptoms;
  List<String> bodyParts;

  /// 'mild' | 'moderate' | 'severe'
  String? severity;
  int painLevel;
  double sleepHours;
  int stressLevel;
  String note;
}

class HealthPlanBlock {
  const HealthPlanBlock({required this.title, required this.items, this.mode});

  /// `workout.title` or `diet.focus`.
  final String title;
  final List<String> items;

  /// 'none' | 'rest' | 'reduced' | 'mobility' | 'modified' (workout only).
  final String? mode;

  Map<String, dynamic> toMap() => {
    if (mode != null) 'mode': mode,
    'title': title,
    'items': items,
  };

  factory HealthPlanBlock.fromMap(Map<String, dynamic> m) => HealthPlanBlock(
    title: (m['title'] as String?) ?? (m['focus'] as String?) ?? '',
    items: (m['items'] as List?)?.map((e) => e.toString()).toList() ?? const [],
    mode: m['mode'] as String?,
  );
}

/// The computed override — `zitlas_health_today`'s shape.
class HealthAdjustment {
  const HealthAdjustment({
    required this.date,
    required this.status,
    required this.symptoms,
    required this.bodyParts,
    required this.oldStepsGoal,
    required this.stepsGoal,
    this.severity,
    this.painLevel,
    this.sleepHours,
    this.stressLevel,
    this.note = '',
    this.safety = false,
    this.workout,
    this.diet,
    this.createdAt,
  });

  final String date;
  final String status;
  final List<String> symptoms;
  final List<String> bodyParts;
  final String? severity;
  final int? painLevel;
  final double? sleepHours;
  final int? stressLevel;
  final String note;

  /// Severe/critical report — all workout generation suppressed.
  final bool safety;
  final HealthPlanBlock? workout;
  final HealthPlanBlock? diet;
  final int oldStepsGoal;

  /// `null` == the website's `'Rest'` sentinel (goal paused for today).
  final int? stepsGoal;
  final String? createdAt;

  bool get isRest => stepsGoal == null;

  /// What `getEffectiveGoal()` derives from this record: a paused goal is 0.
  int get effectiveStepsGoal => stepsGoal ?? 0;

  String get stepsGoalLabel => stepsGoal == null ? 'Rest' : stepsGoal.toString();

  Map<String, dynamic> toMap() => {
    'date': date,
    'status': status,
    'symptoms': symptoms,
    'bodyParts': bodyParts,
    'severity': severity,
    'painLevel': painLevel,
    'sleepHours': sleepHours,
    'stressLevel': stressLevel,
    'note': note,
    'safety': safety,
    'workout': workout?.toMap(),
    'diet': diet == null
        ? null
        : {'focus': diet!.title, 'items': diet!.items},
    'oldStepsGoal': oldStepsGoal,
    'stepsGoal': stepsGoal ?? 'Rest',
    'createdAt': createdAt,
  };

  factory HealthAdjustment.fromMap(Map<String, dynamic> m) {
    final raw = m['stepsGoal'];
    return HealthAdjustment(
      date: (m['date'] as String?) ?? '',
      status: (m['status'] as String?) ?? 'other',
      symptoms: (m['symptoms'] as List?)?.map((e) => e.toString()).toList() ?? const [],
      bodyParts: (m['bodyParts'] as List?)?.map((e) => e.toString()).toList() ?? const [],
      severity: m['severity'] as String?,
      painLevel: (m['painLevel'] as num?)?.toInt(),
      sleepHours: (m['sleepHours'] as num?)?.toDouble(),
      stressLevel: (m['stressLevel'] as num?)?.toInt(),
      note: (m['note'] as String?) ?? '',
      safety: m['safety'] == true,
      workout: m['workout'] is Map
          ? HealthPlanBlock.fromMap((m['workout'] as Map).cast<String, dynamic>())
          : null,
      diet: m['diet'] is Map
          ? HealthPlanBlock.fromMap((m['diet'] as Map).cast<String, dynamic>())
          : null,
      oldStepsGoal: (m['oldStepsGoal'] as num?)?.toInt() ?? 7000,
      stepsGoal: raw is num ? raw.toInt() : null,
      createdAt: m['createdAt'] as String?,
    );
  }
}

/// One row of `zitlas_health_history` — drives the recovery timeline.
class HealthHistoryEntry {
  const HealthHistoryEntry({
    required this.date,
    required this.status,
    this.severity,
    this.safety = false,
  });

  final String date;
  final String status;
  final String? severity;
  final bool safety;

  Map<String, dynamic> toMap() =>
      {'date': date, 'status': status, 'severity': severity, 'safety': safety};

  factory HealthHistoryEntry.fromMap(Map<String, dynamic> m) => HealthHistoryEntry(
    date: (m['date'] as String?) ?? '',
    status: (m['status'] as String?) ?? 'other',
    severity: m['severity'] as String?,
    safety: m['safety'] == true,
  );
}

/// `computeAdjustments(report)` (health-status.js:147-276) — every branch,
/// threshold and copy string reproduced exactly.
///
/// [baseStepsGoal] is `zitlas_calculations.daily_steps_goal` (default 7000 on
/// the website). [hasCriticalCondition] / [hasAsthma] come from
/// `zitlas_precautions`.
HealthAdjustment computeHealthAdjustments(
  HealthReport report, {
  required int baseStepsGoal,
  bool hasCriticalCondition = false,
  bool hasAsthma = false,
  DateTime? now,
}) {
  final n = now ?? DateTime.now();
  final date = '${n.year.toString().padLeft(4, '0')}-'
      '${n.month.toString().padLeft(2, '0')}-${n.day.toString().padLeft(2, '0')}';
  final steps = baseStepsGoal;
  bool has(String s) => report.symptoms.contains(s);

  HealthAdjustment build({
    bool safety = false,
    HealthPlanBlock? workout,
    HealthPlanBlock? diet,
    int? stepsGoal = -1, // -1 sentinel = "unchanged (base goal)"
  }) {
    return HealthAdjustment(
      date: date,
      status: report.status,
      symptoms: report.symptoms,
      bodyParts: report.bodyParts,
      severity: report.severity,
      painLevel: report.painLevel,
      sleepHours: report.sleepHours,
      stressLevel: report.stressLevel,
      note: report.note,
      safety: safety,
      workout: workout,
      diet: diet,
      oldStepsGoal: steps,
      stepsGoal: stepsGoal == -1 ? steps : stepsGoal,
      createdAt: n.toIso8601String(),
    );
  }

  // ── SAFETY GATE (checked first, overrides everything) ──
  if (report.severity == 'severe' ||
      has('Chest Pain') ||
      has('Difficulty Breathing') ||
      (report.status == 'injured' && report.painLevel >= 8) ||
      (report.status == 'sick' && hasCriticalCondition)) {
    return build(
      safety: true,
      workout: const HealthPlanBlock(mode: 'none', title: '⚠ No workout today', items: [
        'Seek medical attention before exercising.',
        'Rest and hydrate.',
        'Resume training only after you feel fully recovered or are cleared by a doctor.',
      ]),
      diet: const HealthPlanBlock(title: 'Gentle recovery nutrition', items: [
        'Light, easy-to-digest meals (khichdi, soup)',
        'Electrolytes / coconut water',
        'Small frequent portions',
        'Plenty of water',
      ]),
      stepsGoal: null, // 'Rest'
    );
  }

  if (report.status == 'great') {
    return build(); // normal plan, no overrides
  }

  if (report.status == 'sick' || report.status == 'unwell' || report.status == 'other') {
    final feverish =
        has('Fever') || has('Vomiting') || has('Diarrhea') || has('Food Poisoning');
    final coldish = has('Cold') || has('Cough') || has('Sore Throat');
    final weak = has('Weakness') || has('Fatigue') || has('Body Pain');

    if (feverish || report.status == 'sick') {
      return build(
        workout: const HealthPlanBlock(mode: 'rest', title: 'Workout cancelled — Recovery Day', items: [
          'Complete rest',
          'Hydration: 3+ litres through the day',
          'Deep breathing: 5 minutes, 3 times',
          'Gentle full-body stretching: 10 minutes',
        ]),
        diet: const HealthPlanBlock(title: 'Fever recovery — light & hydrating', items: [
          'Vegetable / chicken soup',
          'Khichdi (easy to digest)',
          'Coconut water + electrolytes',
          'Vitamin C fruits (orange, amla)',
          'Light protein (curd, dal, boiled eggs)',
        ]),
        stepsGoal: feverish && report.severity == 'moderate' ? null : 2000,
      );
    }
    if (coldish) {
      return build(
        workout: HealthPlanBlock(mode: 'reduced', title: 'Intensity reduced ~60%', items: [
          'Skip high-intensity work today',
          'Easy walk or light mobility only',
          'Stop if breathing feels harder than usual',
          if (hasAsthma) 'Asthma: keep your inhaler nearby, train indoors',
        ]),
        diet: const HealthPlanBlock(title: 'Cold recovery — warm & soothing', items: [
          'Warm fluids through the day',
          'Turmeric milk before bed',
          'Ginger tea',
          'Warm soups',
          'Avoid cold drinks / ice cream',
        ]),
        stepsGoal: (steps * 0.5).round(),
      );
    }
    if (weak) {
      return build(
        workout: const HealthPlanBlock(mode: 'mobility', title: 'Mobility only', items: [
          'Gentle stretching: 15 minutes',
          'Easy walk if energy allows',
          'No strength or cardio today',
        ]),
        diet: const HealthPlanBlock(title: 'Anti-inflammatory + energy', items: [
          'Anti-inflammatory foods (turmeric, ginger, leafy greens)',
          'Balanced carbs for energy',
          'Extra hydration',
        ]),
        stepsGoal: (steps * 0.4).round(),
      );
    }
    return build(
      workout: const HealthPlanBlock(mode: 'reduced', title: 'Take it easier today', items: [
        'Reduce intensity ~40%',
        'Stop early if you feel worse',
      ]),
      diet: const HealthPlanBlock(title: 'Light, regular meals', items: [
        'Stick to simple whole foods',
        'Hydrate well',
      ]),
      stepsGoal: (steps * 0.6).round(),
    );
  }

  if (report.status == 'injured') {
    final parts = report.bodyParts.map((p) => p.toLowerCase()).toList();
    final lower = parts.any((p) => const ['knee', 'ankle', 'foot', 'hip'].contains(p));
    final back = parts.any((p) => p.contains('back'));
    final upper = parts
        .any((p) => const ['neck', 'shoulder', 'chest', 'elbow', 'wrist'].contains(p));
    return build(
      workout: HealthPlanBlock(mode: 'modified', title: 'Workout modified around your injury', items: [
        if (lower) 'Leg work removed — upper-body strength only (seated where possible)',
        if (back)
          'No deadlifts, no squats, no loaded spinal movement — core-safe work only '
              '(bird-dog, dead bug)',
        if (upper) 'Affected-arm/shoulder work removed — lower-body and walking focus',
        'Stay strictly pain-free: sharp pain = stop immediately',
      ]),
      diet: const HealthPlanBlock(title: 'Injury recovery', items: [
        'Extra protein for tissue repair',
        'Anti-inflammatory foods (omega-3, turmeric, berries)',
      ]),
      stepsGoal: lower ? 1500 : (steps * 0.7).round(),
    );
  }

  if (report.status == 'poor_sleep') {
    final hrs = report.sleepHours;
    const sleepDiet = HealthPlanBlock(title: 'Sleep support', items: [
      'Magnesium-rich foods (spinach, almonds, pumpkin seeds, banana)',
      'No caffeine after 2 PM',
      'Lighter dinner, earlier',
    ]);
    if (hrs < 5) {
      return build(
        workout: const HealthPlanBlock(mode: 'reduced', title: 'Light recovery session only', items: [
          'Skip intense training on <5h sleep',
          '15-20 min easy walk',
          'Light stretching before bed tonight',
        ]),
        diet: sleepDiet,
        stepsGoal: (steps * 0.6).round(),
      );
    }
    return build(
      workout: const HealthPlanBlock(mode: 'reduced', title: 'Reduce intensity today', items: [
        'Drop ~30% of planned intensity/volume',
        'Prioritise an earlier night tonight',
      ]),
      diet: sleepDiet,
      stepsGoal: (steps * 0.8).round(),
    );
  }

  if (report.status == 'stress') {
    final lvl = report.stressLevel;
    return build(
      workout: HealthPlanBlock(
        mode: lvl >= 8 ? 'mobility' : 'reduced',
        title: lvl >= 8 ? 'Calming movement only' : 'Moderate session',
        items: lvl >= 8
            ? const [
                'Yoga or gentle stretching: 20 minutes',
                'Breathing exercises: 4-7-8 pattern, 5 minutes',
                'Easy outdoor walk',
              ]
            : const [
                'Moderate workout is fine — it helps stress',
                'Finish with 5 minutes of slow breathing',
              ],
      ),
      diet: const HealthPlanBlock(title: 'Stress support', items: [
        'Complex carbs (oats, brown rice) for stable mood',
        'Omega-3 sources (walnuts, flaxseed)',
        'Limit caffeine today',
      ]),
      stepsGoal: (steps * 0.9).round(),
    );
  }

  return build();
}
