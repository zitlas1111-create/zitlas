import 'dart:ui';

import 'package:flutter/material.dart';

/// Shared ZITLAS design tokens ported from the CURRENT
/// `frontend/assets/css/theme.css` — the single stylesheet every
/// authenticated page loads (athlete dashboard, expert dashboard, diet,
/// training, experts, profile). It is a LIGHT theme (`--bg-primary:
/// #F4F7ED`), which is why both dashboards render light even though the
/// app's global Flutter `ZitlasTheme` (built earlier from the now-stale
/// `COLOR_GUIDELINES.md`) is dark.
///
/// Both `features/dashboard` (athlete) and `features/expert_dashboard`
/// consume these so the two dashboards can't visually drift apart.
abstract final class ZitlasTokens {
  static const bgStart = Color(0xFFF4F7ED);
  static const bgEnd = Color(0xFFEEF3E3);
  static const bgCard = Color(0xFFFFFFFF);
  static const bgCardLight = Color(0xFFF5F8EC);

  static const primary = Color(0xFFFF9800);
  static const primaryHover = Color(0xFFFB8C00);
  static const primaryDark = Color(0xFFEF6C00);

  static const success = Color(0xFF6BA539);
  static const successDark = Color(0xFF578A2C);
  static const aiAccent = Color(0xFF0E9BB5);

  static const textPrimary = Color(0xFF1E293B);
  static const textSecondary = Color(0xFF64748B);
  static const textMuted = Color(0xFF94A3B8);

  static const border = Color(0x1FFF9800); // rgba(255,152,0,0.12)
  static const borderSub = Color(0x14475569);

  /// `#E5484D` — the exact red the expert dashboard uses for its
  /// notification dot and destructive actions.
  static const danger = Color(0xFFE5484D);

  /// `rgba(255,255,255,0.78)` frosted premium-card fill.
  static const cardGlass = Color(0xC7FFFFFF);
}

const double kZitlasRadiusLg = 28;
const double kZitlasRadiusMd = 18;
const double kZitlasRadiusSm = 14;

/// theme.css premium-card shadow recipe.
const List<BoxShadow> kZitlasCardShadow = [
  BoxShadow(color: Color(0x1A6BA539), blurRadius: 40, offset: Offset(0, 15)),
  BoxShadow(color: Color(0x14FF9800), blurRadius: 20, offset: Offset(0, 8)),
  BoxShadow(color: Color(0x1FFF9800), blurRadius: 30),
];

/// Frosted-glass card — the shared visual identity of every dashboard
/// section on both the athlete and expert sides.
class ZitlasCard extends StatelessWidget {
  const ZitlasCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.radius = kZitlasRadiusLg,
    this.margin,
    this.color = ZitlasTokens.cardGlass,
  });

  final Widget child;
  final EdgeInsets padding;
  final double radius;
  final EdgeInsets? margin;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: margin,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        boxShadow: kZitlasCardShadow,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(radius),
              border: Border.all(color: Colors.white.withValues(alpha: 0.6)),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// The `.zitlas-premium-bg` page background: `homebg.png` under a light
/// wash. Used as the root layer of both dashboards.
class ZitlasPremiumBackground extends StatelessWidget {
  const ZitlasPremiumBackground({super.key});

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset('assets/images/homebg.png', fit: BoxFit.cover),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  ZitlasTokens.bgStart.withValues(alpha: 0.45),
                  ZitlasTokens.bgStart.withValues(alpha: 0.55),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
