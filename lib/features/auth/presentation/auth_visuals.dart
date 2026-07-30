import 'package:flutter/material.dart';

/// Visual tokens ported 1:1 from `frontend/pages/login/login.css`'s
/// `:root` block. The website's auth pages deliberately use a light
/// "glassmorphism landing page" theme (`--z-bg: #F7F3EA`) that is entirely
/// separate from the dark in-app theme (`ZitlasColors`/`theme.css`) used
/// everywhere else — this is real, intentional design, not a mismatch to
/// fix. Do not reuse `ZitlasColors` on these screens.
abstract final class AuthColors {
  static const bg = Color(0xFFF7F3EA); // --z-bg
  static const ink = Color(0xFF101828); // --z-ink
  static const muted = Color(0xFF667085); // --z-muted
  static const cardGlass = Color(0xB8FFFFFF); // --z-card: rgba(255,255,255,.72)
  static const cardSolid = Color(0xFFFFFFFF); // --z-card-solid
  static const border = Color(0x1A111827); // --z-border: rgba(17,24,39,.10)
  static const orange = Color(0xFFFF8C00); // --z-orange (== --primary)
  static const orange2 = Color(0xFFFFA726); // --z-orange-2 (== --primary-hover)
  static const green = Color(0xFF22C55E); // --z-green (== --success)
  static const cyan = Color(0xFF00C2FF); // --z-cyan (== --ai-accent)
  static const errorBorder = Color(0x99EF4444); // .input-error border: rgba(239,68,68,.6)
  static const btnLoginText = Color(0xFF101010); // .btn-login color
  static const inputFill = Color(0xA6FFFFFF); // rgba(255,255,255,.65)
  static const inputFillFocus = Color(0xE6FFFFFF); // rgba(255,255,255,.9)
  static const roleTrackBg = Color(0x0D111827); // rgba(17,24,39,.05)
  static const overlayBg = Color(0xEBF7F3EA); // rgba(247,243,234,.92)
}

// --radius-xl / --radius-lg / --radius-md
const double kAuthRadiusXl = 34;
const double kAuthRadiusLg = 26;
const double kAuthRadiusMd = 18;

/// Matches `.login-card`'s combined box-shadow (drop shadow + orange/cyan
/// ambient glow) closely enough to read the same without an animated blur.
const List<BoxShadow> kAuthCardShadow = [
  BoxShadow(color: Color(0x1F101828), blurRadius: 80, offset: Offset(0, 24)),
  BoxShadow(color: Color(0x17FF8C00), blurRadius: 60),
  BoxShadow(color: Color(0x0F00C2FF), blurRadius: 90),
];

/// `--z-glow` — the ambient orange glow under primary buttons.
const List<BoxShadow> kAuthButtonGlow = [
  BoxShadow(color: Color(0x3DFF8C00), blurRadius: 46),
];
