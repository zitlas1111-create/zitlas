import 'package:flutter/material.dart';

import '../../../../app/theme.dart';

/// Shown while [AuthStatus.unknown] — i.e. before Firebase's persisted
/// session check resolves. Router redirect logic keeps the app here until
/// then, so an already-signed-in user never flashes the login screen.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: ZitlasColors.bgPrimary,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'ZITLAS',
              style: TextStyle(
                color: ZitlasColors.primary,
                fontSize: 32,
                fontWeight: FontWeight.w800,
              ),
            ),
            SizedBox(height: 24),
            CircularProgressIndicator(color: ZitlasColors.primary),
          ],
        ),
      ),
    );
  }
}
