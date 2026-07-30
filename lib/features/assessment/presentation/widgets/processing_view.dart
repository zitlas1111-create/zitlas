import 'package:flutter/material.dart';

import '../../../../core/theme/zitlas_tokens.dart';
import '../../assessment_controller.dart';

/// `#s-processing` — the orb + 8 fake progress steps, ticking on a fixed
/// 800ms cadence while the real backend call runs in parallel
/// (`renderProcSteps()`/`callGeneratePlan()`).
class ProcessingView extends StatefulWidget {
  const ProcessingView({super.key});

  @override
  State<ProcessingView> createState() => _ProcessingViewState();
}

class _ProcessingViewState extends State<ProcessingView> {
  final Set<int> _visible = {};
  final Set<int> _done = {};

  @override
  void initState() {
    super.initState();
    for (var i = 0; i < kProcessingSteps.length; i++) {
      Future.delayed(Duration(milliseconds: i * 800), () {
        if (mounted) setState(() => _visible.add(i));
      });
      Future.delayed(Duration(milliseconds: i * 800 + 550), () {
        if (mounted) setState(() => _done.add(i));
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 100,
              height: 100,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  const SizedBox(
                    width: 100,
                    height: 100,
                    child: CircularProgressIndicator(strokeWidth: 3, color: ZitlasTokens.primary),
                  ),
                  ClipOval(
                    child: Image.asset('assets/images/zino.png', width: 64, height: 64, fit: BoxFit.cover),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Text.rich(
              TextSpan(
                children: [
                  const TextSpan(text: 'Building Your\n'),
                  TextSpan(text: 'Personalised Plan', style: TextStyle(color: ZitlasTokens.primary)),
                ],
              ),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: ZitlasTokens.textPrimary, height: 1.3),
            ),
            const SizedBox(height: 8),
            const Text(
              'Searching research database & generating recommendations…',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: ZitlasTokens.textSecondary),
            ),
            const SizedBox(height: 24),
            ...List.generate(kProcessingSteps.length, (i) {
              final step = kProcessingSteps[i];
              final visible = _visible.contains(i);
              final done = _done.contains(i);
              return AnimatedOpacity(
                opacity: visible ? 1 : 0.25,
                duration: const Duration(milliseconds: 250),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      Text(step.icon, style: const TextStyle(fontSize: 18)),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          step.label,
                          style: const TextStyle(fontSize: 13, color: ZitlasTokens.textSecondary, fontWeight: FontWeight.w600),
                        ),
                      ),
                      if (done) const Icon(Icons.check_circle, color: ZitlasTokens.success, size: 18),
                    ],
                  ),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}
