import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../core/theme/zitlas_tokens.dart';
import '../../../auth/auth_state.dart';
import '../../../expert_dashboard/models/expert_models.dart';
import '../../../experts/data/experts_repository.dart';

/// Athlete-side Personal Coaching status page. `coaching-workspace.js` on
/// the website is a large shared athlete+coach surface (2164 lines) whose
/// coach-editing half is out of scope here (expert-side editing lives in
/// the Expert Dashboard); this screen covers the athlete's own view of it:
/// active relationship, plan, remaining days, End Coaching — the same
/// summary `cprofile.js`'s coaching status row shows on the Expert Profile
/// page, surfaced as its own tab per the bottom-nav `/coaching` route.
class CoachingScreen extends StatelessWidget {
  const CoachingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = context.watch<AuthState>().profile?.uid;
    if (uid == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final repo = ExpertsRepository(firestore: FirebaseFirestore.instance, auth: FirebaseAuth.instance);
    return Scaffold(
      backgroundColor: ZitlasTokens.bgStart,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('Personal Coaching', style: TextStyle(color: ZitlasTokens.textPrimary, fontWeight: FontWeight.w800)),
      ),
      body: SafeArea(
        child: StreamBuilder<CoachingRelationship?>(
          stream: repo.watchMyCoachingRelationship(uid),
          builder: (context, snap) {
            if (!snap.hasData && snap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator(color: ZitlasTokens.primary));
            }
            final rel = snap.data;
            if (rel == null || !rel.isActive) {
              return _Empty(hasEnded: rel?.hasEnded == true);
            }
            return _ActiveCoaching(rel: rel, repository: repo, uid: uid);
          },
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.hasEnded});
  final bool hasEnded;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.school_outlined, size: 44, color: ZitlasTokens.textMuted),
            const SizedBox(height: 12),
            Text(
              hasEnded ? 'Your coaching plan has ended' : 'No active coaching yet',
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: ZitlasTokens.textPrimary),
            ),
            const SizedBox(height: 6),
            const Text(
              'Browse verified experts and start a 1:1 personal coaching plan.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12.5, color: ZitlasTokens.textSecondary),
            ),
            const SizedBox(height: 16),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: ZitlasTokens.primary, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
              onPressed: () => context.go('/experts'),
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                child: Text('Browse Experts', style: TextStyle(fontWeight: FontWeight.w700, color: Colors.white)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActiveCoaching extends StatelessWidget {
  const _ActiveCoaching({required this.rel, required this.repository, required this.uid});
  final CoachingRelationship rel;
  final ExpertsRepository repository;
  final String uid;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: ZitlasCard(
        radius: kZitlasRadiusMd,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(rel.coachName ?? 'Your Coach', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: ZitlasTokens.textPrimary)),
            const SizedBox(height: 4),
            Text(rel.planLabel ?? 'Personal Coaching', style: const TextStyle(fontSize: 13, color: ZitlasTokens.textSecondary)),
            const SizedBox(height: 12),
            if (rel.daysRemaining != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(color: ZitlasTokens.success.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
                child: Text('${rel.daysRemaining} days remaining', style: const TextStyle(fontSize: 11.5, color: ZitlasTokens.success, fontWeight: FontWeight.w700)),
              ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(side: const BorderSide(color: ZitlasTokens.danger)),
                onPressed: () => _confirmEnd(context),
                child: const Text('End Coaching', style: TextStyle(color: ZitlasTokens.danger, fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmEnd(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('End coaching?'),
        content: const Text('Your coach will be notified and this relationship will end.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('End Coaching', style: TextStyle(color: ZitlasTokens.danger))),
        ],
      ),
    );
    if (confirmed == true) {
      await repository.endCoaching(uid);
    }
  }
}
