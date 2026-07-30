import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../dashboard_controller.dart';
import '../dashboard_visuals.dart';
import 'section_header.dart';

/// `#wellnessSection` / `renderWellnessCard()` — water (+250ml/+500ml quick
/// log), sleep (numeric input + Save), weight (numeric input + Log, with
/// the same week-over-week delta line as `_dashWeightDeltaHtml()`).
class WellnessCard extends StatefulWidget {
  const WellnessCard({super.key});

  @override
  State<WellnessCard> createState() => _WellnessCardState();
}

class _WellnessCardState extends State<WellnessCard> {
  final _sleepController = TextEditingController();
  final _weightController = TextEditingController();
  bool _sleepPrefilled = false;

  @override
  void dispose() {
    _sleepController.dispose();
    _weightController.dispose();
    super.dispose();
  }

  String _weightDeltaText(DashboardController controller) {
    final history = controller.weightHistory;
    if (history.isEmpty) return '';
    final latest = history.first;
    final cutoff = DateTime.now().subtract(const Duration(days: 6));
    final weekAgo = history.where((w) => !w.date.isAfter(cutoff)).firstOrNull;
    if (weekAgo == null || weekAgo.date == latest.date) {
      return 'Latest: ${latest.weightKg} kg';
    }
    final delta = ((latest.weightKg - weekAgo.weightKg) * 10).round() / 10;
    final arrow = delta > 0 ? '▲' : (delta < 0 ? '▼' : '–');
    return '${latest.weightKg} kg  $arrow ${delta.abs()} kg this week';
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<DashboardController>();
    final activity = controller.todayActivity;
    final waterMl = activity?.waterMl ?? 0;
    final waterGoalMl = activity?.waterGoalMl ?? 2500;
    final waterPct = waterGoalMl > 0 ? (waterMl / waterGoalMl * 100).clamp(0, 100) : 0.0;

    if (!_sleepPrefilled && activity?.sleepHours != null) {
      _sleepController.text = _fmt(activity!.sleepHours!);
      _sleepPrefilled = true;
    }

    return DashboardCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionHeader(
            emoji: '💧',
            title: 'Daily Wellness',
            subtitle: 'Water, sleep & weight',
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _Tile(
                width: _tileWidth(context),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('💧 Water', style: _tileLabelStyle),
                    Text('$waterMl / $waterGoalMl ml', style: _tileValueStyle),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(
                        value: waterPct / 100,
                        minHeight: 6,
                        backgroundColor: const Color(0x1FFF9800),
                        valueColor: const AlwaysStoppedAnimation(DashboardColors.primary),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        _WaterButton(label: '+250ml', onTap: () => controller.logWater(250)),
                        const SizedBox(width: 8),
                        _WaterButton(label: '+500ml', onTap: () => controller.logWater(500)),
                      ],
                    ),
                  ],
                ),
              ),
              _Tile(
                width: _tileWidth(context),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('😴 Sleep', style: _tileLabelStyle),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: _WellnessInput(controller: _sleepController, hint: 'hrs'),
                        ),
                        const SizedBox(width: 8),
                        _SaveButton(
                          label: 'Save',
                          onTap: () {
                            final v = double.tryParse(_sleepController.text);
                            if (v != null) controller.logSleep(v);
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              _Tile(
                width: _tileWidth(context),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('⚖️ Weight', style: _tileLabelStyle),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: _WellnessInput(controller: _weightController, hint: 'kg'),
                        ),
                        const SizedBox(width: 8),
                        _SaveButton(
                          label: 'Log',
                          onTap: () {
                            final v = double.tryParse(_weightController.text);
                            if (v != null) {
                              controller.logWeight(v);
                              _weightController.clear();
                            }
                          },
                        ),
                      ],
                    ),
                    if (_weightDeltaText(controller).isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        _weightDeltaText(controller),
                        style: const TextStyle(color: DashboardColors.textMuted, fontSize: 11),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  double _tileWidth(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    // 3 tiles/row on wide screens, wrap to fewer on narrow phones.
    return w > 520 ? (w - 100) / 3 : (w - 76) / 2;
  }

  String _fmt(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toString();
}

const _tileLabelStyle = TextStyle(
  color: DashboardColors.textSecondary,
  fontSize: 12.5,
  fontWeight: FontWeight.w700,
);
const _tileValueStyle = TextStyle(
  color: DashboardColors.textPrimary,
  fontSize: 17,
  fontWeight: FontWeight.w900,
);

class _Tile extends StatelessWidget {
  const _Tile({required this.width, required this.child});
  final double width;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: DashboardColors.bgCard,
          border: Border.all(color: DashboardColors.border),
          borderRadius: BorderRadius.circular(18),
        ),
        child: child,
      ),
    );
  }
}

class _WaterButton extends StatelessWidget {
  const _WaterButton({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 8),
          side: const BorderSide(color: DashboardColors.border),
          foregroundColor: DashboardColors.primary,
          textStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
        ),
        child: Text(label),
      ),
    );
  }
}

class _WellnessInput extends StatelessWidget {
  const _WellnessInput({required this.controller, required this.hint});
  final TextEditingController controller;
  final String hint;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      style: const TextStyle(color: DashboardColors.textPrimary, fontSize: 14),
      decoration: InputDecoration(
        isDense: true,
        filled: true,
        fillColor: DashboardColors.bgCardLight,
        hintText: hint,
        hintStyle: const TextStyle(color: DashboardColors.textMuted),
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: DashboardColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: DashboardColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: DashboardColors.primary),
        ),
      ),
    );
  }
}

class _SaveButton extends StatelessWidget {
  const _SaveButton({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 38,
      child: ElevatedButton(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: DashboardColors.primary,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
        child: Text(label),
      ),
    );
  }
}
