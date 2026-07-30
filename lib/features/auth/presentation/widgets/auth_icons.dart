import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Every icon here is the exact inline SVG markup copied from
/// `frontend/pages/login/login.html` (and the eye-toggle paths from
/// `login.js`) — not a Material Icons substitute. `flutter_svg` renders
/// them faithfully; [AuthIcon] tints the monochrome ones via [colorFilter]
/// since the source uses `stroke="currentColor"`, which has no meaning
/// outside a browser's CSS cascade.
class AuthIcon extends StatelessWidget {
  const AuthIcon(this._pathData, {super.key, this.size = 20, required this.color, this.strokeWidth = 2});

  final String _pathData;
  final double size;
  final Color color;
  final double strokeWidth;

  String get _svg =>
      '<svg viewBox="0 0 24 24" fill="none" stroke="#000000" stroke-width="$strokeWidth" '
      'stroke-linecap="round" stroke-linejoin="round">$_pathData</svg>';

  @override
  Widget build(BuildContext context) {
    return SvgPicture.string(
      _svg,
      width: size,
      height: size,
      colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
    );
  }
}

abstract final class AuthIconPaths {
  static const user = '<path d="M20 21v-2a4 4 0 0 0-4-4H8a4 4 0 0 0-4 4v2"/><circle cx="12" cy="7" r="4"/>';
  static const mail = '<rect x="2" y="4" width="20" height="16" rx="2"/><path d="m22 6-10 7L2 6"/>';
  static const lock = '<rect x="3" y="11" width="18" height="11" rx="2"/><path d="M7 11V7a5 5 0 0 1 10 0v4"/>';
  static const eyeOpen = '<path d="M1 12s4-8 11-8 11 8 11 8-4 8-11 8-11-8-11-8z"/><circle cx="12" cy="12" r="3"/>';
  static const eyeClosed =
      '<path d="M17.94 17.94A10.07 10.07 0 0 1 12 20c-7 0-11-8-11-8a18.45 18.45 0 0 1 5.06-5.94'
      'M9.9 4.24A9.12 9.12 0 0 1 12 4c7 0 11 8 11 8a18.5 18.5 0 0 1-2.16 3.19m-6.72-1.07a3 3 0 1 1-4.24-4.24"/>'
      '<line x1="1" y1="1" x2="23" y2="23"/>';
  static const athlete = '<polyline points="22 12 18 12 15 21 9 3 6 12 2 12"/>';
  static const expert = '<circle cx="12" cy="8" r="6"/><path d="M15.5 13.5 17 22l-5-3-5 3 1.5-8.5"/>';
  static const check = '<polyline points="20 6 9 17 4 12"/>';
  static const reviewClock = '<circle cx="12" cy="12" r="10"/><polyline points="12 6 12 12 16 14"/>';
  static const chevronDown = '<polyline points="6 9 12 15 18 9"/>';
}

/// The real 4-color Google "G" mark from `login.html`'s `#googleBtn` — never
/// tinted, unlike [AuthIcon].
class GoogleLogo extends StatelessWidget {
  const GoogleLogo({super.key, this.size = 18});

  final double size;

  static const _svg = '''
<svg width="24" height="24" viewBox="0 0 24 24">
<path fill="#4285F4" d="M22.56 12.25c0-.78-.07-1.53-.2-2.25H12v4.26h5.92c-.26 1.37-1.04 2.53-2.21 3.31v2.77h3.57c2.08-1.92 3.28-4.74 3.28-8.09z"/>
<path fill="#34A853" d="M12 23c2.97 0 5.46-.98 7.28-2.66l-3.57-2.77c-.98.66-2.23 1.06-3.71 1.06-2.86 0-5.29-1.93-6.16-4.53H2.18v2.84C3.99 20.53 7.7 23 12 23z"/>
<path fill="#FBBC05" d="M5.84 14.09c-.22-.66-.35-1.36-.35-2.09s.13-1.43.35-2.09V7.07H2.18C1.43 8.55 1 10.22 1 12s.43 3.45 1.18 4.93l2.85-2.22.81-.62z"/>
<path fill="#EA4335" d="M12 5.38c1.62 0 3.06.56 4.21 1.64l3.15-3.15C17.45 2.09 14.97 1 12 1 7.7 1 3.99 3.47 2.18 7.07l3.66 2.84c.87-2.6 3.3-4.53 6.16-4.53z"/>
</svg>''';

  @override
  Widget build(BuildContext context) {
    return SvgPicture.string(_svg, width: size, height: size);
  }
}
