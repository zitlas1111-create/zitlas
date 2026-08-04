import 'package:flutter/material.dart';

import '../../dashboard_controller.dart';
import '../../models/goal_model.dart';
import '../dashboard_visuals.dart';

/// `#setGoalModal` / `initSetGoalModal()` — same 5 goal-type pills, same
/// validation rules (current > 0, target > 0, target != current, end date
/// required and strictly after today), same save shape.
Future<void> showSetGoalSheet(BuildContext context, DashboardController controller) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => _SetGoalSheet(controller: controller),
  );
}

const _goalTypes = [
  ('Weight Loss', '⚖️'),
  ('Nutrition', '🥗'),
  ('Fitness', '💪'),
  ('Habits', '⭐'),
  ('Custom', '✏️'),
];

class _SetGoalSheet extends StatefulWidget {
  const _SetGoalSheet({required this.controller});
  final DashboardController controller;

  @override
  State<_SetGoalSheet> createState() => _SetGoalSheetState();
}

class _SetGoalSheetState extends State<_SetGoalSheet> {
  String _type = 'Weight Loss';
  final _currentController = TextEditingController();
  final _targetController = TextEditingController();
  DateTime? _endDate;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final goal = widget.controller.goal;
    if (goal != null) {
      _type = goal.type;
      _currentController.text = _fmt(goal.currentVal);
      _targetController.text = _fmt(goal.targetVal);
      _endDate = goal.endDate;
    }
  }

  String _fmt(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toString();

  @override
  void dispose() {
    _currentController.dispose();
    _targetController.dispose();
    super.dispose();
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _endDate ?? now.add(const Duration(days: 30)),
      firstDate: now,
      lastDate: DateTime(now.year + 5),
    );
    if (picked != null) setState(() => _endDate = picked);
  }

  Future<void> _save() async {
    final cur = double.tryParse(_currentController.text);
    final tgt = double.tryParse(_targetController.text);

    if (cur == null || cur <= 0) return _toast('⚠️ Enter a valid current value');
    if (tgt == null || tgt <= 0) return _toast('⚠️ Enter a valid target value');
    if (tgt == cur) return _toast('⚠️ Target must differ from current value');
    if (_endDate == null) return _toast('⚠️ Select a goal end date');

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    if (!_endDate!.isAfter(today)) return _toast('⚠️ End date must be in the future');

    setState(() => _saving = true);
    try {
      await widget.controller.setGoal(
        GoalModel(
          type: _type,
          currentVal: cur,
          targetVal: tgt,
          startDate: today,
          endDate: _endDate!,
        ),
      );
      if (mounted) {
        Navigator.of(context).pop();
        _toast('🎯 Goal saved! Keep pushing.');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        decoration: const BoxDecoration(
          color: DashboardColors.bgCard,
          borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
        ),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 14),
                  decoration: BoxDecoration(
                    color: DashboardColors.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const Text(
                'Set Your Goal',
                style: TextStyle(
                  color: DashboardColors.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                "Define what you're working towards this season.",
                style: TextStyle(color: DashboardColors.textSecondary, fontSize: 13, height: 1.45),
              ),
              const SizedBox(height: 18),
              const Text(
                'Goal Type',
                style: TextStyle(
                  color: DashboardColors.textPrimary,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final (type, emoji) in _goalTypes)
                    _TypePill(
                      label: '$emoji $type',
                      selected: _type == type,
                      onTap: () => setState(() => _type = type),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: _NumberField(
                      label: 'Current Value',
                      hint: 'e.g. 42',
                      controller: _currentController,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _NumberField(
                      label: 'Target Value',
                      hint: 'e.g. 60',
                      controller: _targetController,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Text(
                'Goal End Date',
                style: TextStyle(
                  color: DashboardColors.textPrimary,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              GestureDetector(
                onTap: _pickDate,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                  decoration: BoxDecoration(
                    color: DashboardColors.bgCardLight,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: DashboardColors.border),
                  ),
                  child: Text(
                    _endDate == null
                        ? 'Select a date'
                        : '${_endDate!.day}/${_endDate!.month}/${_endDate!.year}',
                    style: TextStyle(
                      color: _endDate == null
                          ? DashboardColors.textMuted
                          : DashboardColors.textPrimary,
                      fontSize: 14,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                height: 50,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [DashboardColors.primary, DashboardColors.primaryHover],
                    ),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: _saving ? null : _save,
                      child: Center(
                        child: _saving
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.4,
                                  color: Colors.white,
                                ),
                              )
                            : const Text(
                                'Save Goal',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TypePill extends StatelessWidget {
  const _TypePill({required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? DashboardColors.primary : DashboardColors.bgCardLight,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: selected ? DashboardColors.primary : DashboardColors.border),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : DashboardColors.textSecondary,
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _NumberField extends StatelessWidget {
  const _NumberField({required this.label, required this.hint, required this.controller});
  final String label;
  final String hint;
  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: DashboardColors.textPrimary,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          style: const TextStyle(color: DashboardColors.textPrimary, fontSize: 14),
          decoration: InputDecoration(
            filled: true,
            fillColor: DashboardColors.bgCardLight,
            hintText: hint,
            hintStyle: const TextStyle(color: DashboardColors.textMuted),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: DashboardColors.border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: DashboardColors.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: DashboardColors.primary),
            ),
          ),
        ),
      ],
    );
  }
}
