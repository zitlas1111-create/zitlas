import 'package:flutter/material.dart';

import '../../../../core/widgets/placeholder_screen.dart';

class ZinoScreen extends StatelessWidget {
  const ZinoScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const PlaceholderScreen(
      title: 'Zino',
      subtitle: 'AI companion chat -> POST /api/ai/zino-chat. See features/zino.',
    );
  }
}
