import 'package:flutter/material.dart';

import '../../../../app/theme.dart';

/// The branded ZITLAS launch screen — the app's first visual experience.
///
/// Shown while the router keeps the app on `/splash`: that is while
/// [AuthStatus.unknown] (Firebase's persisted-session check hasn't resolved)
/// AND until `SplashGate` reports its short minimum has elapsed. The router
/// redirects straight to the resolved destination afterwards — dashboard,
/// expert dashboard, login, or a notification's deep link — so the user never
/// sees a second loading screen in between.
///
/// The background matches `android/app/src/main/res/values/colors.xml`'s
/// `zitlas_splash_bg`, so the native pre-Flutter frame and this screen are the
/// same colour and the handover is invisible (it used to flash white).
///
/// Uses the REAL brand asset (`assets/images/logo.png`, already shipped and
/// declared in pubspec.yaml) — no new artwork.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  // 0.0s background (already painted by the native launch frame)
  // 0.1–0.7s logo fades + scales in
  // 0.5s onwards  wordmark/tagline fade up
  // continuous    slow glow pulse behind the logo
  late final Animation<double> _logoFade;
  late final Animation<double> _logoScale;
  late final Animation<double> _textFade;
  late final Animation<double> _textSlide;
  late final Animation<double> _glow;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    );

    _logoFade = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.06, 0.44, curve: Curves.easeOut),
    );
    // Settles with a gentle overshoot rather than a linear zoom — reads as
    // "arriving", not "resizing".
    _logoScale = Tween<double>(begin: 0.86, end: 1.0).animate(CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.06, 0.52, curve: Curves.easeOutBack),
    ));
    _textFade = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.32, 0.72, curve: Curves.easeOut),
    );
    _textSlide = Tween<double>(begin: 10, end: 0).animate(CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.32, 0.72, curve: Curves.easeOutCubic),
    ));
    _glow = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.30, 1.0, curve: Curves.easeInOut),
    );

    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ZitlasColors.bgPrimary,
      body: DecoratedBox(
        // A barely-there warm lift from the bottom, so a pure-black panel
        // doesn't read as "screen off".
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0, 0.35),
            radius: 1.1,
            colors: [Color(0xFF16100A), ZitlasColors.bgPrimary],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, _) {
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Opacity(
                      opacity: _logoFade.value,
                      child: Transform.scale(
                        scale: _logoScale.value,
                        child: Container(
                          width: 132,
                          height: 132,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: ZitlasColors.primary
                                    .withValues(alpha: 0.10 + 0.16 * _glow.value),
                                blurRadius: 34 + 26 * _glow.value,
                                spreadRadius: 2 + 5 * _glow.value,
                              ),
                            ],
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(6),
                            child: Image.asset(
                              'assets/images/logo.png',
                              fit: BoxFit.contain,
                              // If the asset were ever renamed/removed, the
                              // wordmark below still identifies the app rather
                              // than showing a broken-image box.
                              errorBuilder: (_, _, _) => const SizedBox.shrink(),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 26),
                    Opacity(
                      opacity: _textFade.value,
                      child: Transform.translate(
                        offset: Offset(0, _textSlide.value),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text(
                              'ZITLAS',
                              style: TextStyle(
                                color: ZitlasColors.textPrimary,
                                fontSize: 30,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 7,
                                height: 1,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Container(
                              width: 46,
                              height: 2,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(2),
                                gradient: LinearGradient(colors: [
                                  ZitlasColors.primary.withValues(alpha: 0.15),
                                  ZitlasColors.primary,
                                  ZitlasColors.primary.withValues(alpha: 0.15),
                                ]),
                              ),
                            ),
                            const SizedBox(height: 14),
                            Text(
                              'Because Fitness Comes First.',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.62),
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0.4,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
