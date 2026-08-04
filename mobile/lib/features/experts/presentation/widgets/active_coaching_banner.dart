import 'package:flutter/material.dart';

import '../../../../core/theme/zitlas_tokens.dart';
import '../../../expert_dashboard/models/expert_models.dart';

/// The single, canonical place an athlete ends Personal Coaching.
///
/// Lives on the Coach Profile screen (`ExpertProfileScreen`, opened from
/// "Profile" / "View Profile") — not on the Dashboard card and not on a
/// separate `/coaching` tab. Those were two duplicate implementations of the
/// same action; this widget replaces both so there is exactly one End
/// Coaching button, one confirmation dialog, and one backend call in the app.
///
/// Shown only when [relationship] is the ACTIVE relationship for THIS
/// specific expert — callers must check `relationship.coachId == expertId`
/// before rendering this, since an athlete can view any expert's profile
/// while coaching with someone else entirely.
class ActiveCoachingBanner extends StatelessWidget {
  const ActiveCoachingBanner({
    super.key,
    required this.relationship,
    required this.onEndCoaching,
  });

  final CoachingRelationship relationship;
  final Future<void> Function() onEndCoaching;

  @override
  Widget build(BuildContext context) {
    final days = relationship.daysRemaining;
    final coachName = relationship.coachName ?? 'your coach';

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: ZitlasTokens.bgCard,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: ZitlasTokens.success.withValues(alpha: 0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                  decoration: BoxDecoration(
                    color: ZitlasTokens.success,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: const Text(
                    'ACTIVE',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.3,
                      color: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                if (relationship.planLabel != null)
                  Expanded(
                    child: Text(
                      relationship.planLabel!,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: ZitlasTokens.textPrimary,
                      ),
                    ),
                  ),
              ],
            ),
            if (days != null) ...[
              const SizedBox(height: 6),
              Text(
                days > 0 ? '$days days left' : 'Ends today',
                style: const TextStyle(fontSize: 11.5, color: ZitlasTokens.textSecondary),
              ),
            ],
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () => _confirmEnd(context, coachName),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: ZitlasTokens.danger),
                  padding: const EdgeInsets.symmetric(vertical: 11),
                ),
                child: const Text(
                  'End Coaching',
                  style: TextStyle(color: ZitlasTokens.danger, fontWeight: FontWeight.w800, fontSize: 13),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Spells out exactly what ends and — just as importantly — what does not.
  ///
  /// An athlete hesitating over this button is usually worried they will lose
  /// their plans. They will not, and the dialog says so rather than leaving
  /// them to find out.
  Future<void> _confirmEnd(BuildContext context, String coachName) async {
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ZitlasTokens.bgCard,
        title: const Text(
          'End Personal Coaching?',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Are you sure you want to end your Personal Coaching with '
              '$coachName? This will:',
              style: const TextStyle(fontSize: 13, height: 1.45),
            ),
            const SizedBox(height: 10),
            const _Bullet('End your coaching relationship'),
            const _Bullet('Remove their access to your profile'),
            const _Bullet('Disable meal reviews'),
            const _Bullet('Disable coach chat and calls'),
            const SizedBox(height: 8),
            const Text(
              'Your diet plans, workouts, chat history and progress are kept — '
              'only access to them ends. You can request a new coach right away.',
              style: TextStyle(
                fontSize: 12,
                height: 1.45,
                color: ZitlasTokens.textSecondary,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'End Coaching',
              style: TextStyle(color: ZitlasTokens.danger, fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await onEndCoaching();
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(
          content: Text('Personal Coaching ended. Your plans and history are unchanged.'),
        ));
    } catch (e) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
        ));
    }
  }
}

class _Bullet extends StatelessWidget {
  const _Bullet(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('•  ', style: TextStyle(fontSize: 13)),
          Expanded(
            child: Text(text, style: const TextStyle(fontSize: 12.5, height: 1.4)),
          ),
        ],
      ),
    );
  }
}
