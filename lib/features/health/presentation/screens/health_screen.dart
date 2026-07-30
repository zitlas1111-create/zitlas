import 'package:flutter/material.dart';

import '../../../../core/widgets/placeholder_screen.dart';

class HealthScreen extends StatelessWidget {
  const HealthScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const PlaceholderScreen(
      title: 'Activity',
      subtitle:
          'Step counter (Health Connect / hardware sensor) + health status. Native platform channel not yet ported — see features/health.',
    );
  }
}
