import 'package:flutter/material.dart';

import '../../../../core/theme/zitlas_tokens.dart';
import '../../diet_controller.dart';
import '../../models/diet_meal.dart';

/// Native rebuild of `#swapModal` (`frontend/pages/diet/diet.js:848-1260`) —
/// the REAL website's 3-phase swap flow: Phase A asks WHY before anything
/// else, Phase B is the loading state, Phase C previews the suggestion with
/// Try Again / Accept. The 7 reason options and their exact copy are
/// word-for-word from the website (`diet.html:332-388`) — not invented.
Future<void> showMealSwapSheet(
  BuildContext context, {
  required DietController controller,
  required int dayIndex,
  required int mealIndex,
  required DietMeal meal,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _MealSwapSheet(
      controller: controller,
      dayIndex: dayIndex,
      mealIndex: mealIndex,
      meal: meal,
    ),
  );
}

/// `data-reason` values ported verbatim — the backend keyword-matches on
/// this exact text (`groq_service._build_reason_context`/
/// `_diet_type_from_reason`), so the wording is load-bearing, not cosmetic.
const kDietSwapReasons = <(String icon, String title, String desc, String reason)>[
  ('📍', 'Not Available', "Can't get this where I live", 'Not available near me'),
  ('💸', 'Too Expensive', 'Out of my daily budget', 'Too expensive for my budget'),
  ('🏫', "Hostel Doesn't Provide", 'Not served in my mess', "My hostel mess doesn't provide this"),
  ('😬', "Don't Like It", 'Not a fan of this', "I don't like this food"),
  ('⚠️', 'Allergic', "I can't eat this for health reasons", 'I am allergic to this'),
  ('🌿', 'Vegetarian Option', "I don't eat meat or non-veg", 'I am vegetarian and need a veg option'),
  ('🙏', 'Religious / Cultural', 'Not allowed for me to eat this', 'Religious or cultural reason'),
];

class _MealSwapSheet extends StatefulWidget {
  const _MealSwapSheet({
    required this.controller,
    required this.dayIndex,
    required this.mealIndex,
    required this.meal,
  });

  final DietController controller;
  final int dayIndex;
  final int mealIndex;
  final DietMeal meal;

  @override
  State<_MealSwapSheet> createState() => _MealSwapSheetState();
}

enum _SwapPhase { reason, loading, result }

class _MealSwapSheetState extends State<_MealSwapSheet> {
  _SwapPhase _phase = _SwapPhase.reason;
  String? _reason;
  final List<String> _rejectedFoods = [];
  final List<Map<String, dynamic>> _previousSuggestions = [];

  String? _error;
  Map<String, dynamic>? _suggestion;

  Future<void> _selectReason(String reason) async {
    setState(() {
      _reason = reason;
      _phase = _SwapPhase.loading;
      _error = null;
    });
    final swap = await widget.controller.requestMealSwap(
      dayIndex: widget.dayIndex,
      mealIndex: widget.mealIndex,
      reason: reason,
      rejectedFoods: _rejectedFoods,
      previousSuggestions: _previousSuggestions,
    );
    if (!mounted) return;
    setState(() {
      if (swap == null) {
        _phase = _SwapPhase.reason;
        _error = 'Could not get a suggestion. Please try again.';
      } else {
        _phase = _SwapPhase.result;
        _suggestion = swap;
        _previousSuggestions.add(swap);
      }
    });
  }

  void _tryAgain() {
    if (widget.meal.foods.isNotEmpty) _rejectedFoods.addAll(widget.meal.foods);
    final reason = _reason;
    if (reason == null) return;
    setState(() => _phase = _SwapPhase.loading);
    _selectReason(reason);
  }

  Future<void> _accept() async {
    final suggestion = _suggestion;
    if (suggestion == null) return;
    setState(() => _phase = _SwapPhase.loading);
    try {
      await widget.controller.acceptSwap(
        dayIndex: widget.dayIndex,
        mealIndex: widget.mealIndex,
        swap: suggestion,
      );
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        setState(() {
          _phase = _SwapPhase.result;
          _error = 'Could not save the swap: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
        decoration: const BoxDecoration(
          color: ZitlasTokens.bgCard,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(color: ZitlasTokens.borderSub, borderRadius: BorderRadius.circular(4)),
                ),
              ),
              const SizedBox(height: 16),
              _buildPhase(context),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(_error!, style: const TextStyle(fontSize: 12, color: ZitlasTokens.danger)),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPhase(BuildContext context) {
    switch (_phase) {
      case _SwapPhase.reason:
        return _reasonPhase();
      case _SwapPhase.loading:
        return const Padding(
          padding: EdgeInsets.symmetric(vertical: 40),
          child: Center(child: CircularProgressIndicator(color: ZitlasTokens.primary)),
        );
      case _SwapPhase.result:
        return _resultPhase();
    }
  }

  Widget _reasonPhase() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("Can't eat this?", style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: ZitlasTokens.textPrimary)),
                  Text(widget.meal.mealName, style: const TextStyle(fontSize: 12, color: ZitlasTokens.textMuted)),
                ],
              ),
            ),
            IconButton(icon: const Icon(Icons.close, color: ZitlasTokens.textSecondary), onPressed: () => Navigator.of(context).pop()),
          ],
        ),
        const Text('Tell us why — we\'ll find something that works for you:', style: TextStyle(fontSize: 12.5, color: ZitlasTokens.textSecondary)),
        const SizedBox(height: 12),
        ...kDietSwapReasons.map((r) => _reasonTile(icon: r.$1, title: r.$2, desc: r.$3, reason: r.$4)),
      ],
    );
  }

  Widget _reasonTile({required String icon, required String title, required String desc, required String reason}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: ZitlasTokens.bgCardLight,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => _selectReason(reason),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), border: Border.all(color: ZitlasTokens.borderSub)),
            child: Row(
              children: [
                Text(icon, style: const TextStyle(fontSize: 20)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: ZitlasTokens.textPrimary)),
                      Text(desc, style: const TextStyle(fontSize: 11.5, color: ZitlasTokens.textMuted)),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded, size: 18, color: ZitlasTokens.textMuted),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _resultPhase() {
    final suggestion = _suggestion!;
    final suggestedFoods = suggestion['foods'] is List
        ? (suggestion['foods'] as List).map((e) => e.toString()).toList()
        : const <String>[];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Swap ${widget.meal.mealName}', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: ZitlasTokens.textPrimary)),
        const SizedBox(height: 4),
        Text('Current: ${widget.meal.foods.join(', ')}', style: const TextStyle(fontSize: 12.5, color: ZitlasTokens.textSecondary)),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: ZitlasTokens.bgCardLight, borderRadius: BorderRadius.circular(16)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Suggested swap', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: ZitlasTokens.primaryDark)),
              const SizedBox(height: 6),
              ...suggestedFoods.map((f) => Text('• $f', style: const TextStyle(fontSize: 13, color: ZitlasTokens.textPrimary))),
              if (suggestion['calories'] != null || suggestion['protein_g'] != null) ...[
                const SizedBox(height: 8),
                Text(
                  [
                    if (suggestion['calories'] != null) '${suggestion['calories']} kcal',
                    if (suggestion['protein_g'] != null) '${suggestion['protein_g']}g protein',
                  ].join(' · '),
                  style: const TextStyle(fontSize: 11.5, color: ZitlasTokens.textMuted),
                ),
              ],
              if (suggestion['reason'] != null) ...[
                const SizedBox(height: 8),
                Text('Why this works', style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: ZitlasTokens.textMuted)),
                Text('${suggestion['reason']}', style: const TextStyle(fontSize: 11.5, color: ZitlasTokens.textSecondary)),
              ],
            ],
          ),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _tryAgain,
                style: OutlinedButton.styleFrom(
                  foregroundColor: ZitlasTokens.textSecondary,
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: const Text('Try Again'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: ElevatedButton(
                onPressed: _accept,
                style: ElevatedButton.styleFrom(
                  backgroundColor: ZitlasTokens.success,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: const Text('Accept'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
