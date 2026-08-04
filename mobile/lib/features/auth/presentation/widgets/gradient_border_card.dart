import 'dart:ui';

import 'package:flutter/material.dart';

import '../auth_visuals.dart';

/// `.login-card`'s glassmorphism: a 1.6px animated orange→cyan→orange
/// gradient rim around a blurred translucent-white interior. The rim here
/// is static (no `borderFlow` animation) — a deliberate simplification of
/// a purely decorative CSS animation, not a color/shape difference.
class GradientBorderCard extends StatelessWidget {
  const GradientBorderCard({
    super.key,
    required this.child,
    this.radius = kAuthRadiusXl,
    this.color = AuthColors.cardGlass,
    this.padding = const EdgeInsets.fromLTRB(28, 32, 28, 26),
    this.blur = true,
  });

  final Widget child;
  final double radius;
  final Color color;
  final EdgeInsets padding;
  final bool blur;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(1.6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        gradient: const LinearGradient(
          begin: Alignment(-0.9, -0.65),
          end: Alignment(0.9, 0.65),
          colors: [
            Color(0xE6FF8C00),
            Color(0x4DFFA726),
            Color(0xD900C2FF),
            Color(0x4DFFA726),
            Color(0xE6FF8C00),
          ],
        ),
        boxShadow: kAuthCardShadow,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius - 1.6),
        child: BackdropFilter(
          filter: blur ? ImageFilter.blur(sigmaX: 14, sigmaY: 14) : ImageFilter.blur(),
          child: Container(
            padding: padding,
            decoration: BoxDecoration(color: color),
            child: child,
          ),
        ),
      ),
    );
  }
}
