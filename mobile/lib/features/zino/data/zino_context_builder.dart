import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../../../core/steps/step_tracking_service.dart';

/// Where the athlete is in the app right now — the mobile analogue of
/// `zino.js`'s `_PAGE_MAP`/`currentPage()`.
///
/// This is what lets Zino anchor an ambiguous question ("who do I send it
/// to?", "replace this") to what's actually on screen instead of asking a
/// clarifying question a coach standing next to them would never need to ask.
enum ZinoScreenContext {
  dashboard,
  diet,
  training,
  experts,
  expertProfile,
  profile,
  progress,
  other;

  /// Kept word-for-word from `_PAGE_MAP` — the backend prompt
  /// (`ZINO_COMPANION_SYSTEM`) reasons about these exact purposes, so
  /// rewording them here would silently change how Zino behaves.
  (String name, String purpose) get describe => switch (this) {
        ZinoScreenContext.dashboard => (
            'Home Dashboard',
            'overview: goal progress, today’s steps, SWOT, health status check-in',
          ),
        ZinoScreenContext.training => (
            'Training Plan',
            'the weekly workout plan — user questions here are usually about exercises, '
                'skipping, replacing, or making workouts easier/harder',
          ),
        ZinoScreenContext.diet => (
            'Diet Plan',
            'the 7-day meal plan — user questions here are usually about foods, replacing '
                'meals (Swap Meal button on each meal card), or requesting an expert diet review',
          ),
        ZinoScreenContext.expertProfile => (
            'Expert Profile',
            'viewing one specific expert — user can Chat, hire as Personal Coach, or Request '
                'Review of their diet/workout plan from this page',
          ),
        ZinoScreenContext.experts => (
            'Experts Directory',
            'browsing verified experts — user questions here are usually about WHICH expert '
                'to pick or send a review/verification request to',
          ),
        ZinoScreenContext.profile => ('My Profile', 'account settings, personal info, wallet'),
        ZinoScreenContext.progress => (
            'Progress',
            'weight/step history and trends over time',
          ),
        ZinoScreenContext.other => ('ZITLAS app', ''),
      };
}

/// Maps the `?from=` route parameter onto a screen context.
///
/// Unknown/absent values fall back to [ZinoScreenContext.other] rather than
/// throwing — a bad deep link should open a working chat with slightly less
/// context, never a crash.
ZinoScreenContext zinoScreenContextFromName(String? name) => switch (name) {
      'dashboard' => ZinoScreenContext.dashboard,
      'diet' => ZinoScreenContext.diet,
      'training' => ZinoScreenContext.training,
      'experts' => ZinoScreenContext.experts,
      'expert' => ZinoScreenContext.expertProfile,
      'profile' => ZinoScreenContext.profile,
      'activity' || 'progress' => ZinoScreenContext.progress,
      _ => ZinoScreenContext.other,
    };

/// Builds the athlete-context snapshot sent with every Zino message.
///
/// Ported from `ZinoManager.buildContext()` (zino.js:155-218), reading the
/// same facts from their Flutter-native sources: the `users/{uid}` doc
/// (which `cloud-sync.js` already mirrors every one of these localStorage
/// keys onto), today's `activity/{date}` doc, and the live step service.
///
/// TWO DELIBERATE CONSTRAINTS:
///
///  * **Only relevant facts travel.** Null/empty entries are stripped before
///    sending (same as zino.js's final `delete` pass), and bulky structures
///    are summarized rather than dumped — the full 7-day diet plan is a large
///    payload, but "today's meals" is what a question about today needs. The
///    goal is a small, high-signal context, not everything the app knows.
///  * **One athlete's context can never reach another's session.** Everything
///    is read from the passed-in `uid`'s own documents; nothing is cached in a
///    static/global, so a logout+login rebuilds from the new user's data.
class ZinoContextBuilder {
  ZinoContextBuilder({
    required FirebaseFirestore firestore,
    StepTrackingService? stepService,
  })  : _db = firestore,
        _stepService = stepService;

  final FirebaseFirestore _db;
  final StepTrackingService? _stepService;

  /// Assembles the context for one message.
  ///
  /// [now] is injectable so date/time-dependent behaviour is testable.
  Future<Map<String, dynamic>> build({
    required String uid,
    required String athleteName,
    ZinoScreenContext screen = ZinoScreenContext.other,
    String? viewingExpertId,
    DateTime? now,
  }) async {
    final today = now ?? DateTime.now();
    final ctx = <String, dynamic>{
      'athleteName': athleteName,
      'today': _humanDate(today),
      'time_of_day': _timeOfDay(today),
    };

    final (name, purpose) = screen.describe;
    ctx['current_page'] = {'name': name, if (purpose.isNotEmpty) 'purpose': purpose};

    Map<String, dynamic>? user;
    try {
      user = (await _db.collection('users').doc(uid).get()).data();
    } catch (e) {
      // A failed read must never block the conversation — Zino simply has
      // less to work with and the prompt already handles thin context
      // ("say so warmly and point them to where they can generate it").
      if (kDebugMode) debugPrint('[ZINO] context: user doc read failed: $e');
    }

    if (user != null) {
      _addGoal(ctx, user);
      _addCalculations(ctx, user);
      _addSwot(ctx, user);
      _addMedical(ctx, user);
      _addPlans(ctx, user);
      _addRegion(ctx, user);
      final streak = (user['currentStreak'] as num?)?.toInt();
      if (streak != null && streak > 0) ctx['streak_days'] = streak;
    }

    await _addActivity(ctx, uid: uid, user: user, now: today);
    await _addCoaching(ctx, uid);
    if (viewingExpertId != null) await _addViewingExpert(ctx, viewingExpertId);

    ctx.removeWhere((_, v) => v == null);
    return ctx;
  }

  // ── Goal / calculations ────────────────────────────────────────────────

  void _addGoal(Map<String, dynamic> ctx, Map<String, dynamic> user) {
    final goal = user['goal'];
    if (goal is Map) ctx['goal'] = goal.cast<String, dynamic>();
  }

  void _addCalculations(Map<String, dynamic> ctx, Map<String, dynamic> user) {
    final calc = (user['calculations'] as Map?)?.cast<String, dynamic>();
    if (calc == null) return;
    ctx['bmi'] = calc['bmi'];
    ctx['bmi_category'] = calc['bmi_category'];
    ctx['bmr_kcal'] = calc['bmr_kcal'];
    ctx['tdee_kcal'] = calc['tdee_kcal'];
    // Same precedence as zino.js: the weight-loss target wins when present.
    ctx['target_calories_kcal'] =
        calc['weight_loss_calories_kcal'] ?? calc['target_calories_kcal'];
    ctx['protein_target_g'] = calc['protein_target_g'];
    ctx['water_target_l'] = calc['water_target_liters'];
    ctx['daily_steps_goal'] = calc['daily_steps_goal'];
  }

  void _addSwot(Map<String, dynamic> ctx, Map<String, dynamic> user) {
    final swotDoc = (user['swot'] as Map?)?.cast<String, dynamic>();
    final swot = (swotDoc?['swot'] as Map?)?.cast<String, dynamic>();
    if (swot == null) return;
    // Only the headline strength/weakness — the full SWOT is four lists of
    // paragraphs and would dominate the payload for little conversational gain.
    ctx['swot_summary'] = {
      'top_strength': _firstTitle(swot['strengths']),
      'top_weakness': _firstTitle(swot['weaknesses']),
      'archetype': swotDoc?['user_archetype'],
    }..removeWhere((_, v) => v == null);
  }

  String? _firstTitle(Object? list) {
    if (list is! List || list.isEmpty) return null;
    final first = list.first;
    if (first is Map) return first['title'] as String?;
    return first?.toString();
  }

  void _addMedical(Map<String, dynamic> ctx, Map<String, dynamic> user) {
    final assessment = (user['assessment'] as Map?)?.cast<String, dynamic>();
    ctx['medical_conditions'] = assessment?['medical_conditions'] ?? 'none';
    final precautions = (user['precautions'] as Map?)?.cast<String, dynamic>();
    if (precautions != null) ctx['precautions_today'] = precautions['precautions'];
  }

  void _addRegion(Map<String, dynamic> ctx, Map<String, dynamic> user) {
    // The canonical confirmed region drives diet/swap generation, so Zino
    // must reason with the SAME value rather than the raw GPS snapshot.
    final preferred = user['preferredDietRegion'];
    if (preferred is String && preferred.trim().isNotEmpty) {
      ctx['region'] = {'state': preferred};
      return;
    }
    final loc = (user['location'] as Map?)?.cast<String, dynamic>();
    if (loc == null) return;
    final city = loc['city'], state = loc['state'];
    if (city == null && state == null) return;
    ctx['region'] = {'city': city, 'state': state}..removeWhere((_, v) => v == null);
  }

  // ── Plans (expert-aware) ───────────────────────────────────────────────

  /// Summarizes both plans, mirroring `summarizeDiet`/`summarizeWorkout`.
  ///
  /// EXPERT AWARENESS: reads `currentDietPlan`/`currentWorkoutPlan` first —
  /// the plan actually in force — so Zino describes what a human expert
  /// approved, never the superseded AI original. `isCoachManaged` tells the
  /// prompt an expert is involved, which is what lets Zino say "your expert
  /// adjusted today's plan" instead of contradicting them.
  void _addPlans(Map<String, dynamic> ctx, Map<String, dynamic> user) {
    final diet = (user['dietPlan'] as Map?)?.cast<String, dynamic>();
    if (diet != null) {
      final flat = (diet['currentDietPlan'] as Map?) ?? (diet['originalDietPlan'] as Map?) ?? diet;
      final days = flat['days'];
      if (days is List && days.isNotEmpty) {
        final today = _todayEntry(days);
        ctx['diet'] = {
          'totalDays': days.length,
          'isCoachManaged':
              diet['isExpertPlan'] == true || (diet['expertModifications'] as Map?)?.isNotEmpty == true,
          if (diet['expertName'] != null) 'expertName': diet['expertName'],
          'todayMeals': [
            for (final m in (today?['meals'] as List?) ?? const [])
              if (m is Map)
                {
                  'name': m['meal_name'],
                  'foods': m['foods'],
                  if (m['time'] != null) 'time': m['time'],
                },
          ],
        };
      }
    }

    final workout = (user['workoutPlan'] as Map?)?.cast<String, dynamic>();
    if (workout != null) {
      final flat =
          (workout['currentWorkoutPlan'] as Map?) ?? (workout['originalWorkoutPlan'] as Map?) ?? workout;
      final days = (flat['weekly_plan'] as List?) ?? (flat['days'] as List?) ?? const [];
      if (days.isNotEmpty) {
        final today = _todayEntry(days);
        ctx['workout'] = {
          'totalDays': days.length,
          'isCoachManaged': workout['isExpertPlan'] == true ||
              (workout['workoutModifications'] as Map?)?.isNotEmpty == true,
          if (workout['expertName'] != null) 'expertName': workout['expertName'],
          'todayFocus': today?['focus'] ?? today?['type'],
          if (today?['duration_minutes'] != null) 'todayDuration': today?['duration_minutes'],
        };
      }
    }
  }

  /// Monday-indexed "today" lookup — `getDay()` is Sunday-based in JS, and
  /// zino.js compensates with `day === 0 ? 6 : day - 1`. Dart's `weekday` is
  /// already Monday=1, so this is the direct equivalent.
  Map<String, dynamic>? _todayEntry(List<dynamic> days, [DateTime? now]) {
    final index = ((now ?? DateTime.now()).weekday - 1).clamp(0, days.length - 1);
    final entry = days[index] ?? days.first;
    return entry is Map ? entry.cast<String, dynamic>() : null;
  }

  // ── Live activity ──────────────────────────────────────────────────────

  /// Today's REAL step data — the thing that makes "how am I doing today?"
  /// answerable with numbers instead of platitudes.
  ///
  /// Prefers the live on-device reading (freshest by definition) and falls
  /// back to today's synced day doc, so Zino still has figures on a device
  /// where step tracking isn't enabled but another device synced them.
  Future<void> _addActivity(
    Map<String, dynamic> ctx, {
    required String uid,
    required Map<String, dynamic>? user,
    required DateTime now,
  }) async {
    var steps = 0;
    var goal = 0;
    var recovery = false;
    var rest = false;
    var haveData = false;

    final dateKey =
        '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    try {
      final day = (await _db.collection('users').doc(uid).collection('activity').doc(dateKey).get()).data();
      if (day != null) {
        steps = (day['steps'] as num?)?.toInt() ?? 0;
        goal = (day['goalEffective'] as num?)?.toInt() ?? (day['goal'] as num?)?.toInt() ?? 0;
        recovery = day['recoveryMode'] == true;
        rest = recovery && goal == 0;
        haveData = true;
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[ZINO] context: activity read failed: $e');
    }

    if (goal <= 0) {
      goal = (user?['dailyStepGoal'] as num?)?.toInt() ??
          ((user?['calculations'] as Map?)?['daily_steps_goal'] as num?)?.toInt() ??
          0;
    }

    final service = _stepService;
    if (service != null && service.isEnabled && goal > 0) {
      try {
        final snap = await service.refresh(goal: goal);
        if (snap.isAvailable) {
          steps = snap.steps;
          haveData = true;
        }
      } catch (e) {
        if (kDebugMode) debugPrint('[ZINO] context: live step read failed: $e');
      }
    }

    if (!haveData && goal <= 0) return;
    ctx['activity_today'] = {
      'steps': steps,
      'step_goal': goal,
      'goal_pct': goal > 0 ? ((steps / goal) * 100).round() : 100,
      'steps_remaining': goal > steps ? goal - steps : 0,
      'recovery_mode': recovery,
      'rest_day': rest,
    };
  }

  Future<void> _addCoaching(Map<String, dynamic> ctx, String uid) async {
    try {
      final rel = (await _db.collection('personal_coaching').doc(uid).get()).data();
      final active = rel != null && rel['status'] == 'active';
      ctx['personal_coaching'] = active
          ? {'active': true, 'coachName': rel['coachName'], 'planType': rel['planType']}
          : {'active': false};
    } catch (e) {
      if (kDebugMode) debugPrint('[ZINO] context: coaching read failed: $e');
    }
  }

  Future<void> _addViewingExpert(Map<String, dynamic> ctx, String expertId) async {
    try {
      final expert = (await _db.collection('experts').doc(expertId).get()).data();
      if (expert == null) return;
      ctx['viewing_expert'] = {
        'name': expert['name'],
        'specialization': expert['specialization'] ?? expert['role'] ?? 'Expert',
      };
    } catch (e) {
      if (kDebugMode) debugPrint('[ZINO] context: expert read failed: $e');
    }
  }

  // ── Formatting ─────────────────────────────────────────────────────────

  static const _weekdays = [
    'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday',
  ];
  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  /// "Thursday, 30 Jul" — the same `en-IN` long-weekday shape zino.js sends.
  String _humanDate(DateTime d) =>
      '${_weekdays[d.weekday - 1]}, ${d.day} ${_months[d.month - 1]}';

  /// Lets Zino greet appropriately and judge whether a suggestion still fits
  /// the day ("a short evening walk" only makes sense in the evening).
  String _timeOfDay(DateTime d) {
    final h = d.hour;
    if (h < 5) return 'late night';
    if (h < 12) return 'morning';
    if (h < 17) return 'afternoon';
    if (h < 21) return 'evening';
    return 'night';
  }
}
