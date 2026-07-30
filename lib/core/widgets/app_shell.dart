import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Bottom-nav shell for the 5 primary tabs, mirroring `components/navbar.js`
/// on web (Home / Diet / Training / Experts / Profile). Wrapped around the
/// active branch by a `StatefulShellRoute.indexedStack` in `app/router.dart`
/// so each tab keeps its own navigation stack.
class AppShell extends StatelessWidget {
  const AppShell({
    super.key,
    required this.navigationShell,
  });

  final StatefulNavigationShell navigationShell;

  static const _tabs = [
    (icon: Icons.home_rounded, label: 'Home'),
    (icon: Icons.restaurant_menu_rounded, label: 'Diet'),
    (icon: Icons.fitness_center_rounded, label: 'Training'),
    (icon: Icons.groups_rounded, label: 'Experts'),
    (icon: Icons.person_rounded, label: 'Profile'),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: navigationShell.currentIndex,
        onTap: (index) => navigationShell.goBranch(
          index,
          initialLocation: index == navigationShell.currentIndex,
        ),
        items: [
          for (final tab in _tabs)
            BottomNavigationBarItem(icon: Icon(tab.icon), label: tab.label),
        ],
      ),
    );
  }
}
