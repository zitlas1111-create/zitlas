import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../features/auth/auth_state.dart';
import '../../features/zino/presentation/widgets/zino_fab.dart';
import '../../features/zino/tour/zino_tour_controller.dart';
import '../../features/zino/tour/zino_tour_overlay.dart';
import '../../features/zino/tour/zino_tour_stops.dart';
import '../../features/zino/tour/zino_tour_store.dart';

/// Bottom-nav shell for the 5 primary tabs, mirroring `components/navbar.js`
/// on web (Home / Diet / Training / Experts / Profile). Wrapped around the
/// active branch by a `StatefulShellRoute.indexedStack` in `app/router.dart`
/// so each tab keeps its own navigation stack.
///
/// Also the single host for the two always-on Zino surfaces: the top-right
/// launcher and the first-run walkthrough. Both live here rather than on each
/// screen so they're guaranteed consistent across every tab.
class AppShell extends StatefulWidget {
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

  /// Branch index -> the `?from=` value Zino uses to anchor ambiguous
  /// questions. Order matches [_tabs] and the router's branch order.
  static const _zinoContextForBranch = [
    'dashboard',
    'diet',
    'training',
    'experts',
    'profile',
  ];

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  ZinoTourController? _tour;
  String? _tourUid;

  /// Tour screen -> nav branch index, so advancing the walkthrough moves the
  /// athlete through the real app the way the website navigated between pages.
  static const _branchForTourScreen = {
    ZinoTourScreen.dashboard: 0,
    ZinoTourScreen.diet: 1,
    ZinoTourScreen.training: 2,
    ZinoTourScreen.experts: 3,
    ZinoTourScreen.profile: 4,
  };

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final uid = context.watch<AuthState>().profile?.uid;
    if (uid == null || uid == _tourUid) return;
    _tourUid = uid;
    _initTourFor(uid);
  }

  Future<void> _initTourFor(String uid) async {
    final controller = ZinoTourController(
      uid: uid,
      store: ZinoTourStore(firestore: FirebaseFirestore.instance),
    )..addListener(_onTourChanged);
    // Only ever starts for an account that has verifiably never completed or
    // skipped it — see ZinoTourStore.shouldAutoStart, which fails CLOSED.
    final started = await controller.startIfNewUser();
    if (!mounted) {
      controller.dispose();
      return;
    }
    if (started) {
      setState(() => _tour = controller);
      _syncBranchToTour();
    } else {
      controller.dispose();
    }
  }

  void _onTourChanged() {
    if (!mounted) return;
    final tour = _tour;
    if (tour != null && !tour.isRunning) {
      // Finished or skipped — drop the overlay and leave the athlete on the
      // tab they ended on.
      setState(() => _tour = null);
      tour.removeListener(_onTourChanged);
      tour.dispose();
      return;
    }
    setState(() {});
    _syncBranchToTour();
  }

  /// Moves the visible tab to whatever the current stop describes.
  void _syncBranchToTour() {
    final tour = _tour;
    if (tour == null || !tour.isRunning) return;
    final target = _branchForTourScreen[tour.current.screen];
    if (target == null || target == widget.navigationShell.currentIndex) return;
    widget.navigationShell.goBranch(target);
  }

  /// Entry point for Profile -> "Take Zino Tour Again". Replaying never
  /// changes the athlete's completed status back to "new".
  void startTourManually(String uid) {
    _tour?.removeListener(_onTourChanged);
    _tour?.dispose();
    final controller = ZinoTourController(
      uid: uid,
      store: ZinoTourStore(firestore: FirebaseFirestore.instance),
    )..addListener(_onTourChanged);
    controller.startManually();
    setState(() => _tour = controller);
    _syncBranchToTour();
  }

  @override
  void dispose() {
    _tour?.removeListener(_onTourChanged);
    _tour?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final from = AppShell._zinoContextForBranch[widget.navigationShell.currentIndex
        .clamp(0, AppShell._zinoContextForBranch.length - 1)];
    final tour = _tour;

    return ZinoTourHost(
      startTour: startTourManually,
      child: Stack(
        children: [
          Scaffold(
            // Zino rides along on every primary tab, matching the website where
            // `zino.js` self-mounts its FAB on every page — the athlete can ask
            // a question from wherever they are, and Zino knows where that was.
            //
            // TOP-RIGHT, not a bottom FAB: that placement is part of the ZITLAS
            // design (`.zn-fab { top: …; right: 16px }`), so it is preserved
            // rather than converted to the usual Android bottom-right
            // convention.
            body: ZinoFabOverlay(
              onTap: () => context.push('/zino?from=$from'),
              child: widget.navigationShell,
            ),
            bottomNavigationBar: BottomNavigationBar(
              currentIndex: widget.navigationShell.currentIndex,
              onTap: (index) => widget.navigationShell.goBranch(
                index,
                initialLocation: index == widget.navigationShell.currentIndex,
              ),
              items: [
                for (final tab in AppShell._tabs)
                  BottomNavigationBarItem(icon: Icon(tab.icon), label: tab.label),
              ],
            ),
          ),
          // Above the Scaffold (including the nav bar) so the walkthrough
          // scrim genuinely blocks interaction with a half-explained screen.
          if (tour != null) ZinoTourOverlay(controller: tour),
        ],
      ),
    );
  }
}

/// Exposes "replay the tour" to descendants (Profile) without a global.
class ZinoTourHost extends InheritedWidget {
  const ZinoTourHost({super.key, required this.startTour, required super.child});

  final void Function(String uid) startTour;

  static ZinoTourHost? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ZinoTourHost>();

  @override
  bool updateShouldNotify(ZinoTourHost oldWidget) => false;
}
