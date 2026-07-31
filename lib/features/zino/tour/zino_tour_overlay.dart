import 'package:flutter/material.dart';

import '../../../core/theme/zitlas_tokens.dart';
import 'zino_tour_controller.dart';
import 'zino_tour_stops.dart';

/// The walkthrough UI: `.zn-tut-overlay` + `.zn-spotlight` + `.zn-guide-card`
/// for element stops, and `.zn-slide` for the intro/finish hero slides.
///
/// Rendered above the live app rather than over screenshots, so the athlete is
/// looking at their REAL dashboard/diet/training while Zino explains it —
/// which is what makes the walkthrough feel like guidance rather than a
/// slideshow.
class ZinoTourOverlay extends StatelessWidget {
  const ZinoTourOverlay({super.key, required this.controller});

  final ZinoTourController controller;

  @override
  Widget build(BuildContext context) {
    if (!controller.isRunning) return const SizedBox.shrink();
    final stop = controller.current;

    return Material(
      color: Colors.transparent,
      child: stop.isSlide
          ? _HeroSlide(controller: controller)
          : _SpotlightStop(controller: controller),
    );
  }
}

/// A full-screen intro/finish slide — `.zn-slide`.
class _HeroSlide extends StatelessWidget {
  const _HeroSlide({required this.controller});
  final ZinoTourController controller;

  @override
  Widget build(BuildContext context) {
    final stop = controller.current;
    final isLast = controller.isLast;

    return Container(
      color: const Color(0xF00F0F14),
      child: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Image.asset(
                    stop.hero!,
                    fit: BoxFit.contain,
                    // The tour must never be blocked by a missing image.
                    errorBuilder: (_, _, _) => const SizedBox.shrink(),
                  ),
                ),
              ),
            ),
            Container(
              margin: const EdgeInsets.fromLTRB(20, 0, 20, 24),
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(22),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    stop.title,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: ZitlasTokens.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    stop.body,
                    style: const TextStyle(
                      fontSize: 14,
                      height: 1.55,
                      color: ZitlasTokens.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      if (!isLast)
                        TextButton(
                          onPressed: controller.skip,
                          style: TextButton.styleFrom(
                            foregroundColor: ZitlasTokens.textMuted,
                          ),
                          child: const Text('Skip Tour'),
                        ),
                      const Spacer(),
                      ElevatedButton(
                        onPressed: controller.next,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: ZitlasTokens.primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 13),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: Text(
                          isLast ? 'Start My Journey 🚀' : 'Next →',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// An element stop — dark scrim with a cut-out around the real widget, plus
/// the guide card positioned clear of it.
class _SpotlightStop extends StatefulWidget {
  const _SpotlightStop({required this.controller});
  final ZinoTourController controller;

  @override
  State<_SpotlightStop> createState() => _SpotlightStopState();
}

class _SpotlightStopState extends State<_SpotlightStop> {
  Rect? _targetRect;

  @override
  void initState() {
    super.initState();
    _resolveTarget();
  }

  @override
  void didUpdateWidget(covariant _SpotlightStop oldWidget) {
    super.didUpdateWidget(oldWidget);
    _resolveTarget();
  }

  /// Measures the spotlighted widget after the frame it's laid out in.
  ///
  /// A stop whose widget isn't mounted (a fresh account has no diet plan, no
  /// experts, no coach) is skipped rather than pointed at empty space —
  /// matching the website's behaviour when `querySelector` finds nothing.
  void _resolveTarget() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final key = zinoTourTargetFor(widget.controller.current.id);
      final ctx = key?.currentContext;
      final box = ctx?.findRenderObject() as RenderBox?;
      if (box == null || !box.hasSize) {
        widget.controller.skipUnavailableStop();
        return;
      }
      final offset = box.localToGlobal(Offset.zero);
      final rect = offset & box.size;
      if (rect != _targetRect) setState(() => _targetRect = rect);
    });
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final rect = _targetRect;
    final screen = MediaQuery.of(context).size;

    // `pad: 8` in positionSpotlight()
    final hole = rect?.inflate(8);

    // The website places the card below the target when there's room, above
    // otherwise — the same rule, so the card never covers what it describes.
    final spaceBelow = hole == null ? 0.0 : screen.height - hole.bottom;
    final cardBelow = hole == null || spaceBelow > 260 || hole.top < 220;

    return Stack(
      children: [
        // Scrim with the cut-out. Absorbs taps so the athlete can't interact
        // with a half-explained screen mid-tour.
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {},
            child: CustomPaint(
              painter: _SpotlightPainter(hole: hole),
              size: Size.infinite,
            ),
          ),
        ),
        if (hole != null)
          Positioned(
            left: hole.left,
            top: hole.top,
            width: hole.width,
            height: hole.height,
            child: IgnorePointer(
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: ZitlasTokens.primary, width: 2.5),
                ),
              ),
            ),
          ),
        Positioned(
          left: 16,
          right: 16,
          top: cardBelow && hole != null ? hole.bottom + 14 : null,
          // `cardBelow` is unconditionally true when there's no hole, so the
          // else-branch only ever runs with a resolved target.
          bottom: cardBelow ? null : screen.height - hole.top + 14,
          child: SafeArea(child: _GuideCard(controller: controller)),
        ),
      ],
    );
  }
}

/// `.zn-guide-card` — Zino's avatar, the step counter, the copy, and the
/// Skip / Back / Next controls.
class _GuideCard extends StatelessWidget {
  const _GuideCard({required this.controller});
  final ZinoTourController controller;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.28),
            blurRadius: 28,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ClipOval(
                child: Image.asset(
                  'assets/images/zino.png',
                  width: 28,
                  height: 28,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) =>
                      const Icon(Icons.auto_awesome, size: 20, color: ZitlasTokens.primary),
                ),
              ),
              const SizedBox(width: 8),
              const Text(
                'Zino',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: ZitlasTokens.textPrimary,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                decoration: BoxDecoration(
                  color: ZitlasTokens.bgCardLight,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '${controller.stepNumber} / ${controller.totalStops}',
                  style: const TextStyle(fontSize: 11, color: ZitlasTokens.textMuted),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            controller.current.title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: ZitlasTokens.textPrimary,
            ),
          ),
          const SizedBox(height: 7),
          Text(
            controller.currentBody,
            style: const TextStyle(
              fontSize: 13.5,
              height: 1.5,
              color: ZitlasTokens.textSecondary,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              TextButton(
                onPressed: controller.skip,
                style: TextButton.styleFrom(
                  foregroundColor: ZitlasTokens.textMuted,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text('Skip Tour', style: TextStyle(fontSize: 12.5)),
              ),
              const Spacer(),
              if (!controller.isFirst)
                TextButton(
                  onPressed: controller.back,
                  style: TextButton.styleFrom(
                    foregroundColor: ZitlasTokens.textSecondary,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text('Back', style: TextStyle(fontSize: 12.5)),
                ),
              const SizedBox(width: 6),
              ElevatedButton(
                onPressed: controller.next,
                style: ElevatedButton.styleFrom(
                  backgroundColor: ZitlasTokens.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  minimumSize: Size.zero,
                ),
                child: Text(
                  controller.isLast ? 'Finish' : 'Next →',
                  style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Paints the dimming scrim with a rounded hole punched out of it.
class _SpotlightPainter extends CustomPainter {
  const _SpotlightPainter({required this.hole});
  final Rect? hole;

  @override
  void paint(Canvas canvas, Size size) {
    final scrim = Paint()..color = const Color(0xB80F0F14);
    final full = Path()..addRect(Offset.zero & size);
    if (hole == null) {
      canvas.drawPath(full, scrim);
      return;
    }
    final cut = Path()
      ..addRRect(RRect.fromRectAndRadius(hole!, const Radius.circular(14)));
    // evenOdd leaves the spotlighted widget fully visible and un-dimmed.
    canvas.drawPath(
      Path.combine(PathOperation.difference, full, cut),
      scrim,
    );
  }

  @override
  bool shouldRepaint(covariant _SpotlightPainter old) => old.hole != hole;
}
