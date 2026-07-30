import 'package:flutter/material.dart';

import '../../dashboard_controller.dart';
import '../../models/health_status.dart';
import '../dashboard_visuals.dart';

/// `openReportSheet(statusKey)` — the per-status report form. "Feeling great"
/// submits immediately with no sheet, exactly like the website
/// (`if (statusKey === 'great') { submitReport(); return; }`).
Future<void> showHealthReportSheet(
  BuildContext context,
  DashboardController controller,
  HealthStatusOption status,
) async {
  if (status.key == 'great') {
    await controller.submitHealthReport(HealthReport(status: 'great'));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('😊 Great! Today’s plan runs as normal.')),
    );
    return;
  }

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _HealthReportSheet(controller: controller, status: status),
  );
}

class _HealthReportSheet extends StatefulWidget {
  const _HealthReportSheet({required this.controller, required this.status});

  final DashboardController controller;
  final HealthStatusOption status;

  @override
  State<_HealthReportSheet> createState() => _HealthReportSheetState();
}

class _HealthReportSheetState extends State<_HealthReportSheet> {
  late final HealthReport _draft = HealthReport(status: widget.status.key);
  final _noteController = TextEditingController();
  bool _submitting = false;

  bool get _isSymptomFlow =>
      const {'sick', 'unwell', 'other'}.contains(widget.status.key);

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _submitting = true);
    _draft.note = _noteController.text.trim();
    try {
      await widget.controller.submitHealthReport(_draft);
      if (!mounted) return;
      final safety = widget.controller.healthToday?.safety ?? false;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            safety
                ? '⚠ Plan paused — please consider medical attention.'
                : '✅ Today’s plan adjusted. Your coach has been notified if you have one.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not update today’s plan: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
        decoration: const BoxDecoration(
          color: DashboardColors.bgCard,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
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
                    color: DashboardColors.borderSub,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                widget.status.label,
                style: const TextStyle(
                  color: DashboardColors.textPrimary,
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 12),
              ..._statusFields(),
              const SizedBox(height: 12),
              const _Label('Optional note'),
              const SizedBox(height: 6),
              TextField(
                controller: _noteController,
                maxLines: 3,
                decoration: InputDecoration(
                  hintText: 'Describe how you’re feeling…',
                  filled: true,
                  fillColor: DashboardColors.bgCardLight,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _submitting ? null : () => Navigator.of(context).pop(),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: DashboardColors.textSecondary,
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton(
                      onPressed: _submitting ? null : _submit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: DashboardColors.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: _submitting
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text(
                              'Update Today’s Plan',
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _statusFields() {
    if (_isSymptomFlow) {
      return [
        const Text(
          'What are you experiencing? (select all that apply)',
          style: TextStyle(color: DashboardColors.textSecondary, fontSize: 12.5),
        ),
        const SizedBox(height: 8),
        _MultiChips(
          options: healthSymptoms,
          selected: _draft.symptoms,
          onToggle: (v) => setState(() {
            _draft.symptoms.contains(v)
                ? _draft.symptoms.remove(v)
                : _draft.symptoms.add(v);
          }),
        ),
        const SizedBox(height: 12),
        const _Label('Severity'),
        const SizedBox(height: 6),
        Row(
          children: [
            for (final sev in const ['mild', 'moderate', 'severe']) ...[
              Expanded(
                child: _SeverityButton(
                  label: '${sev[0].toUpperCase()}${sev.substring(1)}',
                  selected: _draft.severity == sev,
                  severe: sev == 'severe',
                  onTap: () => setState(() => _draft.severity = sev),
                ),
              ),
              if (sev != 'severe') const SizedBox(width: 8),
            ],
          ],
        ),
      ];
    }

    if (widget.status.key == 'injured') {
      return [
        const Text(
          'Which body part? (select all that apply)',
          style: TextStyle(color: DashboardColors.textSecondary, fontSize: 12.5),
        ),
        const SizedBox(height: 8),
        _MultiChips(
          options: healthBodyParts,
          selected: _draft.bodyParts,
          onToggle: (v) => setState(() {
            _draft.bodyParts.contains(v)
                ? _draft.bodyParts.remove(v)
                : _draft.bodyParts.add(v);
          }),
        ),
        const SizedBox(height: 12),
        _Label('Pain level: ${_draft.painLevel}/10'),
        Slider(
          value: _draft.painLevel.toDouble(),
          min: 1,
          max: 10,
          divisions: 9,
          activeColor: DashboardColors.primary,
          onChanged: (v) => setState(() => _draft.painLevel = v.round()),
        ),
      ];
    }

    if (widget.status.key == 'poor_sleep') {
      return [
        _Label('Hours slept: ${_fmtHours(_draft.sleepHours)}h'),
        Slider(
          value: _draft.sleepHours,
          max: 12,
          divisions: 24,
          activeColor: DashboardColors.primary,
          onChanged: (v) => setState(() => _draft.sleepHours = v),
        ),
      ];
    }

    if (widget.status.key == 'stress') {
      return [
        _Label('Stress level: ${_draft.stressLevel}/10'),
        Slider(
          value: _draft.stressLevel.toDouble(),
          min: 1,
          max: 10,
          divisions: 9,
          activeColor: DashboardColors.primary,
          onChanged: (v) => setState(() => _draft.stressLevel = v.round()),
        ),
      ];
    }

    return const [];
  }

  static String _fmtHours(double h) =>
      h == h.roundToDouble() ? h.toInt().toString() : h.toString();
}

class _Label extends StatelessWidget {
  const _Label(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        color: DashboardColors.textPrimary,
        fontSize: 12.5,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

/// `.hs-chip-grid` — multi-select toggle chips.
class _MultiChips extends StatelessWidget {
  const _MultiChips({
    required this.options,
    required this.selected,
    required this.onToggle,
  });

  final List<String> options;
  final List<String> selected;
  final ValueChanged<String> onToggle;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 7,
      runSpacing: 7,
      children: options.map((o) {
        final on = selected.contains(o);
        return GestureDetector(
          onTap: () => onToggle(o),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
            decoration: BoxDecoration(
              color: on
                  ? DashboardColors.primary.withValues(alpha: 0.16)
                  : DashboardColors.bgCardLight,
              border: Border.all(
                color: on ? DashboardColors.primary : DashboardColors.border,
              ),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              o,
              style: TextStyle(
                color: on ? DashboardColors.primaryDark : DashboardColors.textPrimary,
                fontSize: 12,
                fontWeight: on ? FontWeight.w800 : FontWeight.w600,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _SeverityButton extends StatelessWidget {
  const _SeverityButton({
    required this.label,
    required this.selected,
    required this.severe,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final bool severe;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = severe ? DashboardColors.error : DashboardColors.primary;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: selected ? accent.withValues(alpha: 0.16) : DashboardColors.bgCardLight,
          border: Border.all(color: selected ? accent : DashboardColors.border),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? accent : DashboardColors.textPrimary,
            fontSize: 12.5,
            fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
