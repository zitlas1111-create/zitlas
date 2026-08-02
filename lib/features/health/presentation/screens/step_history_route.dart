import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/steps/step_history.dart';
import '../../../../core/steps/step_tracking_service.dart';
import '../../../auth/auth_state.dart';
import 'step_history_screen.dart';

/// Loads what [StepHistoryScreen] needs, from local storage first.
///
/// The history itself is ALWAYS local — it's the offline-first record the
/// tracker writes on every read, so this screen opens with real data on a
/// plane. Only height and weight come from Firestore, and only to sharpen the
/// distance/calorie estimates; the screen renders fine without them and says
/// which figures are estimated.
class StepHistoryRoute extends StatefulWidget {
  const StepHistoryRoute({super.key});

  @override
  State<StepHistoryRoute> createState() => _StepHistoryRouteState();
}

class _StepHistoryRouteState extends State<StepHistoryRoute> {
  late final StepHistory _history = StepHistory(StepTrackingService().readHistory());
  double? _heightCm;
  double? _weightKg;

  @override
  void initState() {
    super.initState();
    _loadBody();
  }

  Future<void> _loadBody() async {
    final uid = context.read<AuthState>().profile?.uid;
    if (uid == null) return;
    try {
      final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
      final survey = doc.data()?['survey'] as Map<String, dynamic>?;
      final info = doc.data()?['personalInfo'] as Map<String, dynamic>?;
      if (!mounted) return;
      setState(() {
        _heightCm = _asDouble(survey?['height_cm'] ?? info?['heightCm']);
        _weightKg = _asDouble(survey?['weight_kg'] ?? info?['weightKg']);
      });
    } catch (e) {
      // Estimates fall back to adult averages — not worth an error state.
      if (kDebugMode) debugPrint('[STEPS] body metrics unavailable: $e');
    }
  }

  static double? _asDouble(Object? v) => v is num ? v.toDouble() : null;

  @override
  Widget build(BuildContext context) {
    return StepHistoryScreen(
      history: _history,
      heightCm: _heightCm,
      weightKg: _weightKg,
    );
  }
}
