import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/zitlas_tokens.dart';
import '../../../diet/models/diet_day.dart';
import '../../../diet/models/diet_meal.dart';
import '../../../diet/models/diet_plan_content.dart';
import '../../data/expert_repository.dart';

/// Native rebuild of `frontend/pages/experts/modify-diet.html` +
/// `modify-diet.js` — the expert's Diet review editor. Loads the
/// `review_requests/{id}` doc's `planData` snapshot, lets the expert edit
/// each meal's foods/calories/protein, and on save writes
/// `reviewedDietPlan` + `mealChangeHistory` back onto the SAME doc — the
/// exact shape `DietController.acceptExpertReview()` already consumes on
/// the athlete side (CLAUDE.md "Diet Modification System — the
/// authoritative pattern"). No new schema.
class ReviewDietEditorScreen extends StatefulWidget {
  const ReviewDietEditorScreen({super.key, required this.reviewId});
  final String reviewId;

  @override
  State<ReviewDietEditorScreen> createState() => _ReviewDietEditorScreenState();
}

class _ReviewDietEditorScreenState extends State<ReviewDietEditorScreen> {
  late final ExpertRepository _repository;
  bool _loading = true;
  bool _saving = false;
  Object? _error;
  Map<String, dynamic>? _raw;
  List<DietDay> _days = const [];
  int _selectedDay = 0;
  final Map<String, MapEntry<DietMeal, DietMeal>> _edits = {}; // key = "dayIdx.mealKey" -> (old, new)

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
      if (planData is Map && (planData['originalDietPlan'] != null || planData['currentDietPlan'] != null)) {
        planData = planData['currentDietPlan'] ?? planData['originalDietPlan'];
      }
      final content = planData is Map ? DietPlanContent.fromMap(planData.cast<String, dynamic>()) : const DietPlanContent();
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
        title: const Text('Review Diet Plan', style: TextStyle(color: ZitlasTokens.textPrimary, fontSize: 15, fontWeight: FontWeight.w800)),
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
                  ? const Center(child: Text('This athlete has no diet plan on this request.', style: TextStyle(color: ZitlasTokens.textSecondary)))
                  : _body(),
    );
  }

  Widget _body() {
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
            children: _days[_selectedDay].meals.map((meal) => _mealCard(_selectedDay, meal)).toList(),
          ),
        ),
      ],
    );
  }

  Widget _mealCard(int dayIdx, DietMeal meal) {
    final key = '$dayIdx.${meal.mealKey}';
    final edited = _edits.containsKey(key);
    final display = edited ? _edits[key]!.value : meal;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: ZitlasTokens.bgCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: edited ? ZitlasTokens.primary : ZitlasTokens.borderSub),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(display.mealName, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: ZitlasTokens.textPrimary)),
              ),
              if (edited)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: ZitlasTokens.primary.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
                  child: const Text('Edited', style: TextStyle(fontSize: 10, color: ZitlasTokens.primaryDark, fontWeight: FontWeight.w700)),
                ),
              IconButton(icon: const Icon(Icons.edit_outlined, size: 18), onPressed: () => _editMeal(dayIdx, meal, display)),
            ],
          ),
          Text(display.foods.join(', '), style: const TextStyle(fontSize: 12, color: ZitlasTokens.textSecondary)),
          const SizedBox(height: 4),
          Text(
            '${display.calories ?? '—'} kcal · ${display.proteinG ?? '—'}g protein',
            style: const TextStyle(fontSize: 11, color: ZitlasTokens.textMuted),
          ),
        ],
      ),
    );
  }

  Future<void> _editMeal(int dayIdx, DietMeal original, DietMeal current) async {
    final foodsCtrl = TextEditingController(text: current.foods.join(', '));
    final calCtrl = TextEditingController(text: current.calories?.toString() ?? '');
    final protCtrl = TextEditingController(text: current.proteinG?.toString() ?? '');

    final result = await showModalBottomSheet<bool>(
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
            Text('Edit ${original.mealName}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: ZitlasTokens.textPrimary)),
            const SizedBox(height: 14),
            TextField(controller: foodsCtrl, maxLines: 3, decoration: const InputDecoration(labelText: 'Foods (comma separated)')),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(child: TextField(controller: calCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Calories'))),
                const SizedBox(width: 10),
                Expanded(child: TextField(controller: protCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Protein (g)'))),
              ],
            ),
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

    if (result != true) return;
    final newFoods = foodsCtrl.text.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
    final newCal = num.tryParse(calCtrl.text.trim());
    final newProt = num.tryParse(protCtrl.text.trim());

    final newMeal = original.copyWith(
      foods: newFoods,
      calories: newCal,
      proteinG: newProt,
      edited: true,
      modifiedBy: 'Expert',
      modifiedAt: DateTime.now().toIso8601String(),
    );

    setState(() {
      _edits['$dayIdx.${original.mealKey}'] = MapEntry(original, newMeal);
      final day = _days[dayIdx];
      final meals = day.meals.map((m) => m.mealKey == original.mealKey ? newMeal : m).toList();
      _days = List.of(_days)..[dayIdx] = day.copyWithMeals(meals);
    });
  }

  Future<void> _save() async {
    if (_edits.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Make at least one change before sending.')));
      return;
    }
    setState(() => _saving = true);
    try {
      final reviewedPlan = DietPlanContent(days: _days).toMap();
      final now = DateTime.now().toIso8601String();
      final history = _edits.entries.map((e) {
        final dayIdx = int.parse(e.key.split('.').first);
        final old = e.value.key;
        final nw = e.value.value;
        return {
          'dayIndex': dayIdx,
          'mealName': nw.mealName,
          'dayLabel': _days[dayIdx].day,
          'oldFoods': old.foods,
          'newFoods': nw.foods,
          'oldCalories': old.calories,
          'newCalories': nw.calories,
          'oldProtein': old.proteinG,
          'newProtein': nw.proteinG,
          'modifiedBy': 'Expert',
          'modifiedAt': now,
        };
      }).toList();

      await _repository.submitDietReview(
        reviewId: widget.reviewId,
        reviewedDietPlan: reviewedPlan,
        mealChangeHistory: history,
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
