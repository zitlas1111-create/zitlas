import 'package:flutter/material.dart';

import '../../../../core/widgets/placeholder_screen.dart';

class PaymentsScreen extends StatelessWidget {
  const PaymentsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const PlaceholderScreen(
      title: 'Wallet',
      subtitle: 'Wallet balance, top-up, transaction history. See features/payments.',
    );
  }
}
