import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/zitlas_tokens.dart';
import '../../../workout/models/workout_day.dart';
import '../../../workout/models/workout_exercise.dart';
import '../../../workout/models/workout_plan_content.dart';
import '../../data/expert_repository.dart';

/// Native rebuild of `frontend/pages/experts/modify-workout.html` +
/// `modify-workout.js` — the expert's Training review editor. Loads the
/// `review_requests/{id}` doc's `planData` snapshot, lets the expert edit
/// each day's focus/duration and each exercise's sets/reps, and on save
/// writes `workoutChangeHistory` back onto the SAME doc — the exact field
/// `WorkoutController._maybeAutoSyncReview()` already reads to auto-apply
/// the change on the athlete's Training page (which has no explicit
/// "Accept" button by website design, unlike Diet).
class ReviewWorkoutEditorScreen extends StatefulWidget {
  const ReviewWorkoutEditorScreen({super.key, required this.reviewId});
  final String reviewId;

  @override
  State<ReviewWorkoutEditorScreen> createState() => _ReviewWorkoutEditorScreenState();
}

class _ReviewWorkoutEditorScreenState extends State<ReviewWorkoutEditorScreen> {
  late final ExpertRepository _repository;
  bool _loading = true;
  bool _saving = false;
  Object? _error;
  Map<String, dynamic>? _raw;
  List<WorkoutDay> _days = const [];
  int _selectedDay = 0;
  final Map<int, WorkoutDay> _originalByDay = {};
  final Set<int> _editedDays = {};

  @override
  void initState() {
    super.initState();
    _repository = ExpertRepository(firestore: FirebaseFirestore.instance, auth: FirebaseAuth.instance);
    _load();
  }

  Future<void> _load() async {
    try {
      final raw = await _repository.fetchReviewRaw(widget.reviewId);
      if (raw == null) {
        setState(() {
          _error = 'not_found';
          _loading = false;
        });
        return;
      }
      var planData = raw['planData'];
      if (planData is Map && (planData['originalWorkoutPlan'] != null || planData['currentWorkoutPlan'] != null)) {
        planData = planData['currentWorkoutPlan'] ?? planData['originalWorkoutPlan'];
      }
      final content = planData is Map ? WorkoutPlanContent.fromMap(planData.cast<String, dynamic>()) : const WorkoutPlanContent();
      for (var i = 0; i < content.days.length; i++) {
        _originalByDay[i] = content.days[i];
      }
      setState(() {
        _raw = raw;
        _days = content.days;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ZitlasTokens.bgStart,
      appBar: AppBar(
        backgroundColor: ZitlasTokens.bgCard,
        title: const Text('Review Training Plan', style: TextStyle(color: ZitlasTokens.textPrimary, fontSize: 15, fontWeight: FontWeight.w800)),
        actions: [
          if (!_loading && _error == null)
            TextButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Save & Send', style: TextStyle(fontWeight: FontWeight.w800, color: ZitlasTokens.primaryDark)),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: ZitlasTokens.primary))
          : _error != null
              ? Center(
                  child: Text(
                    _error == 'not_found' ? 'This review request no longer exists.' : 'Could not load this review.',
                    style: const TextStyle(color: ZitlasTokens.textSecondary),
                  ),
                )
              : _days.isEmpty
                  ? const Center(child: Text('This athlete has no training plan on this request.', style: TextStyle(color: ZitlasTokens.textSecondary)))
                  : _body(),
    );
  }

  Widget _body() {
    final day = _days[_selectedDay];
    return Column(
      children: [
        SizedBox(
          height: 46,
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            scrollDirection: Axis.horizontal,
            itemCount: _days.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, i) {
              final selected = i == _selectedDay;
              return ChoiceChip(
                label: Text(_days[i].day, style: const TextStyle(fontSize: 12)),
                selected: selected,
                onSelected: (_) => setState(() => _selectedDay = i),
                selectedColor: ZitlasTokens.primary,
                labelStyle: TextStyle(color: selected ? Colors.white : ZitlasTokens.textSecondary),
              );
            },
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.only(bottom: 10),
                decoration: BoxDecoration(color: ZitlasTokens.bgCard, borderRadius: BorderRadius.circular(14), border: Border.all(color: ZitlasTokens.borderSub)),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(day.theme, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: ZitlasTokens.textPrimary)),
                          Text('${day.durationMinutes ?? '—'} min', style: const TextStyle(fontSize: 11.5, color: ZitlasTokens.textMuted)),
                        ],
                      ),
                    ),
                    IconButton(icon: const Icon(Icons.edit_outlined, size: 18), onPressed: _editDayHeader),
                  ],
                ),
              ),
              ...List.generate(day.exercises.length, (i) => _exerciseCard(day, i)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _exerciseCard(WorkoutDay day, int exIdx) {
    final ex = day.exercises[exIdx];
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: ZitlasTokens.bgCard, borderRadius: BorderRadius.circular(12), border: Border.all(color: ZitlasTokens.borderSub)),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(ex.name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: ZitlasTokens.textPrimary)),
                Text('${ex.sets ?? '—'} sets · ${ex.repsOrDuration ?? '—'}', style: const TextStyle(fontSize: 11.5, color: ZitlasTokens.textMuted)),
              ],
            ),
          ),
          IconButton(icon: const Icon(Icons.edit_outlined, size: 16), onPressed: () => _editExercise(exIdx, ex)),
        ],
      ),
    );
  }

  Future<void> _editDayHeader() async {
    final day = _days[_selectedDay];
    final focusCtrl = TextEditingController(text: day.theme);
    final durCtrl = TextEditingController(text: day.durationMinutes?.toString() ?? '');
    final ok = await _editDialog('Edit ${day.day}', [
      TextField(controller: focusCtrl, decoration: const InputDecoration(labelText: 'Focus')),
      const SizedBox(height: 10),
      TextField(controller: durCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Duration (minutes)')),
    ]);
    if (ok != true) return;
    setState(() {
      final updated = day.copyWith(focus: focusCtrl.text.trim(), durationMinutes: num.tryParse(durCtrl.text.trim()));
      _days = List.of(_days)..[_selectedDay] = updated;
      _editedDays.add(_selectedDay);
    });
  }

  Future<void> _editExercise(int exIdx, WorkoutExercise ex) async {
    final setsCtrl = TextEditingController(text: ex.sets ?? '');
    final repsCtrl = TextEditingController(text: ex.repsOrDuration ?? '');
    final ok = await _editDialog('Edit ${ex.name}', [
      TextField(controller: setsCtrl, decoration: const InputDecoration(labelText: 'Sets (e.g. 3-4)')),
      const SizedBox(height: 10),
      TextField(controller: repsCtrl, decoration: const InputDecoration(labelText: 'Reps / Duration (e.g. 12 reps, AMRAP)')),
    ]);
    if (ok != true) return;
    setState(() {
      final day = _days[_selectedDay];
      final exercises = List.of(day.exercises);
      exercises[exIdx] = ex.copyWith(sets: setsCtrl.text.trim(), repsOrDuration: repsCtrl.text.trim());
      _days = List.of(_days)..[_selectedDay] = day.copyWith(exercises: exercises);
      _editedDays.add(_selectedDay);
    });
  }

  Future<bool?> _editDialog(String title, List<Widget> fields) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: EdgeInsets.fromLTRB(20, 16, 20, 20 + MediaQuery.of(ctx).viewInsets.bottom),
        decoration: const BoxDecoration(color: ZitlasTokens.bgCard, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: ZitlasTokens.textPrimary)),
            const SizedBox(height: 14),
            ...fields,
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                style: FilledButton.styleFrom(backgroundColor: ZitlasTokens.primary),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Save Change', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    if (_editedDays.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Make at least one change before sending.')));
      return;
    }
    setState(() => _saving = true);
    try {
      final reviewedPlan = WorkoutPlanContent(days: _days).toMap();
      final now = DateTime.now().toIso8601String();
      final history = _editedDays.map((dayIdx) {
        final original = _originalByDay[dayIdx]!;
        final nw = _days[dayIdx];
        return {
          'dayIndex': dayIdx,
          'dayLabel': nw.day,
          'oldWorkout': original.toModificationSnapshot(),
          'newWorkout': nw.toModificationSnapshot(),
          'modifiedBy': 'Expert',
          'modifiedAt': now,
        };
      }).toList();

      await _repository.submitWorkoutReview(
        reviewId: widget.reviewId,
        reviewedWorkoutPlan: reviewedPlan,
        workoutChangeHistory: history,
        expertId: (_raw?['expertId'] as String?) ?? '',
        expertName: (_raw?['expertName'] as String?) ?? 'Expert',
        athleteId: _raw?['userId'] as String?,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('✅ Review sent to athlete.')));
      context.pop();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not save — please try again.')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}
