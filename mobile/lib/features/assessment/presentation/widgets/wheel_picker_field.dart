import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../../../core/theme/zitlas_tokens.dart';

/// Native `CupertinoPicker` equivalent of the website's custom drag/scroll
/// wheel (`createWheelPicker()` in `ai-coach.js`) — same UX intent (scroll to
/// pick a numeric value from a range or a discrete preset list) via a native
/// widget instead of reproducing raw touch/drag physics, which the task's
/// own instructions treat as a legitimate translation (native widgets are
/// fine; only the FEATURE — picking a value from this exact range/preset
/// list — must not be simplified).
class WheelPickerField extends StatefulWidget {
  const WheelPickerField({
    super.key,
    this.min,
    this.max,
    this.values,
    required this.unit,
    required this.initialValue,
    required this.onChanged,
  });

  final int? min;
  final int? max;
  final List<int>? values;
  final String unit;
  final num initialValue;
  final ValueChanged<num> onChanged;

  @override
  State<WheelPickerField> createState() => _WheelPickerFieldState();
}

class _WheelPickerFieldState extends State<WheelPickerField> {
  late final List<int> _values = widget.values ?? List.generate(widget.max! - widget.min! + 1, (i) => widget.min! + i);
  late final FixedExtentScrollController _controller;

  @override
  void initState() {
    super.initState();
    var idx = _values.indexOf(widget.initialValue.round());
    if (idx == -1) {
      // closest value, matching `valueToIndex()`'s nearest-match fallback.
      idx = 0;
      var best = double.infinity;
      for (var i = 0; i < _values.length; i++) {
        final diff = (_values[i] - widget.initialValue).abs();
        if (diff < best) {
          best = diff.toDouble();
          idx = i;
        }
      }
    }
    _controller = FixedExtentScrollController(initialItem: idx);
    WidgetsBinding.instance.addPostFrameCallback((_) => widget.onChanged(_values[idx]));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 200,
      decoration: BoxDecoration(
        color: ZitlasTokens.bgCardLight,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          CupertinoPicker(
            scrollController: _controller,
            itemExtent: 44,
            selectionOverlay: Container(
              decoration: BoxDecoration(
                border: Border.symmetric(
                  horizontal: BorderSide(color: ZitlasTokens.primary.withValues(alpha: 0.4)),
                ),
              ),
            ),
            onSelectedItemChanged: (i) => widget.onChanged(_values[i]),
            children: _values
                .map(
                  (v) => Center(
                    child: Text(
                      '$v',
                      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: ZitlasTokens.textPrimary),
                    ),
                  ),
                )
                .toList(),
          ),
          Positioned(
            right: 28,
            child: IgnorePointer(
              child: Text(
                widget.unit,
                style: const TextStyle(fontSize: 13, color: ZitlasTokens.textMuted, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// `.unit-toggle` — CM/FT-IN or KG/LBS pill switch above a wheel picker.
class UnitToggle extends StatelessWidget {
  const UnitToggle({super.key, required this.options, required this.selected, required this.onSelect});

  final List<(String value, String label)> options;
  final String selected;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: ZitlasTokens.bgCardLight, borderRadius: BorderRadius.circular(14)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: options.map((o) {
          final active = o.$1 == selected;
          return GestureDetector(
            onTap: () => onSelect(o.$1),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
              decoration: BoxDecoration(
                color: active ? ZitlasTokens.primary : Colors.transparent,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                o.$2,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                  color: active ? Colors.white : ZitlasTokens.textSecondary,
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}
