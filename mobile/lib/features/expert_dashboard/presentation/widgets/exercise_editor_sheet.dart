import 'package:flutter/material.dart';

import '../../../../core/theme/zitlas_tokens.dart';
import '../../../workout/models/workout_exercise.dart';

/// Full exercise editor — name, sets, reps/duration, weight, rest, and
/// instructions.
///
/// Sets/reps/rest are deliberately TEXT rather than numbers: real programming
/// uses ranges and semantic values ("3-4", "AMRAP", "12 each side", "60-90s")
/// that a numeric field would make unsayable. Validation below still rejects
/// the things that are genuinely wrong.
Future<WorkoutExercise?> showExerciseEditorSheet(
  BuildContext context, {
  required WorkoutExercise exercise,
  bool isNew = false,
}) {
  return showModalBottomSheet<WorkoutExercise>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _ExerciseEditorSheet(exercise: exercise, isNew: isNew),
  );
}

class _ExerciseEditorSheet extends StatefulWidget {
  const _ExerciseEditorSheet({required this.exercise, required this.isNew});
  final WorkoutExercise exercise;
  final bool isNew;

  @override
  State<_ExerciseEditorSheet> createState() => _ExerciseEditorSheetState();
}

class _ExerciseEditorSheetState extends State<_ExerciseEditorSheet> {
  late final _name = TextEditingController(text: widget.exercise.name);
  late final _sets = TextEditingController(text: widget.exercise.sets ?? '');
  late final _reps = TextEditingController(text: widget.exercise.repsOrDuration ?? '');
  late final _weight = TextEditingController(text: widget.exercise.weight ?? '');
  late final _rest = TextEditingController(text: widget.exercise.restSeconds ?? '');
  late final _tip = TextEditingController(text: widget.exercise.tip ?? '');

  String? _error;

  @override
  void dispose() {
    for (final c in [_name, _sets, _reps, _weight, _rest, _tip]) {
      c.dispose();
    }
    super.dispose();
  }

  String? _validate() {
    if (_name.text.trim().isEmpty) return 'An exercise needs a name.';
    // Only reject a value that is unambiguously a NUMBER and negative —
    // "3-4" and "AMRAP" must stay valid.
    for (final (label, ctrl) in [('Sets', _sets), ('Reps', _reps), ('Rest', _rest)]) {
      final value = num.tryParse(ctrl.text.trim());
      if (value != null && value < 0) return "$label can't be negative.";
    }
    final sets = num.tryParse(_sets.text.trim());
    if (sets != null && sets > 20) return 'That many sets looks like a typo.';
    return null;
  }

  void _save() {
    final error = _validate();
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    String? nullIfBlank(TextEditingController c) =>
        c.text.trim().isEmpty ? null : c.text.trim();

    Navigator.of(context).pop(
      widget.exercise.copyWith(
        name: _name.text.trim(),
        sets: nullIfBlank(_sets),
        repsOrDuration: nullIfBlank(_reps),
        weight: nullIfBlank(_weight),
        restSeconds: nullIfBlank(_rest),
        tip: nullIfBlank(_tip),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: ZitlasTokens.bgCard,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 22),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: ZitlasTokens.borderSub,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                widget.isNew ? 'Add Exercise' : 'Edit Exercise',
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: ZitlasTokens.textPrimary,
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _name,
                autofocus: widget.isNew,
                decoration: _dec('Exercise name'),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(child: TextField(controller: _sets, decoration: _dec('Sets', hint: '3-4'))),
                  const SizedBox(width: 10),
                  Expanded(child: TextField(controller: _reps, decoration: _dec('Reps / Duration', hint: '12 reps'))),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(child: TextField(controller: _weight, decoration: _dec('Weight', hint: '40 kg'))),
                  const SizedBox(width: 10),
                  Expanded(child: TextField(controller: _rest, decoration: _dec('Rest', hint: '60 sec'))),
                ],
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _tip,
                maxLines: 3,
                decoration: _dec('Instructions / form cue'),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Icon(Icons.error_outline_rounded, size: 16, color: ZitlasTokens.danger),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        _error!,
                        style: const TextStyle(fontSize: 12.5, color: ZitlasTokens.danger),
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: ZitlasTokens.primary,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  onPressed: _save,
                  child: Text(
                    widget.isNew ? 'Add Exercise' : 'Save Exercise',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  InputDecoration _dec(String label, {String? hint}) => InputDecoration(
        labelText: label,
        hintText: hint,
        isDense: true,
        filled: true,
        fillColor: ZitlasTokens.bgCardLight,
        labelStyle: const TextStyle(fontSize: 12.5),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
      );
}
