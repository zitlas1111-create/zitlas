import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/theme/zitlas_tokens.dart';
import '../../expert_dashboard_controller.dart';
import '../../models/expert_models.dart';
import '../widgets/expert_common.dart';

/// `#sectionReviews` — the Reviews Inbox with pending / in-progress /
/// completed tabs and per-status card actions (`renderInbox`, ED:4533+).
class ExpertReviewsSection extends StatefulWidget {
  const ExpertReviewsSection({super.key, required this.onOpenChat, required this.onEditPlan});

  /// Opens the chat thread for a review (`_prOpenReviewChat`, ED:4815).
  final void Function(ReviewRequest) onOpenChat;

  /// Opens the Diet/Workout plan editor (`modify-diet.html`/
  /// `modify-workout.html`) for a diet/workout-type review.
  final void Function(ReviewRequest) onEditPlan;

  @override
  State<ExpertReviewsSection> createState() => _ExpertReviewsSectionState();
}

class _ExpertReviewsSectionState extends State<ExpertReviewsSection> {
  int _tab = 0;
  final _busy = <String>{};

  Future<void> _run(String id, Future<void> Function() action, String successMsg) async {
    setState(() => _busy.add(id));
    try {
      await action();
      if (mounted) _toast(successMsg);
    } catch (e) {
      if (mounted) _toast('Something went wrong. Please try again.');
    } finally {
      if (mounted) setState(() => _busy.remove(id));
    }
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _accept(ExpertDashboardController c, ReviewRequest r) async {
    setState(() => _busy.add(r.id));
    try {
      final error = await c.acceptReview(r);
      if (!mounted) return;
      if (error == null) {
        _toast('✅ Review accepted — you can now chat with the athlete.');
      } else if (error == 'insufficient_balance') {
        // Same handling as ED:4777 — the athlete is told to top up.
        _toast("Athlete's wallet balance is insufficient. They've been notified.");
      } else {
        _toast('Could not accept this review. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _busy.remove(r.id));
    }
  }

  Future<void> _confirmReject(ExpertDashboardController c, ReviewRequest r) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ZitlasTokens.bgCard,
        title: const Text('Reject this request?'),
        content: Text(
          'The request from ${r.displayName} will be marked rejected. '
          'This cannot be undone.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Reject', style: TextStyle(color: ZitlasTokens.danger)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _run(r.id, () => c.rejectReview(r), 'Request rejected.');
  }

  Future<void> _confirmComplete(ExpertDashboardController c, ReviewRequest r) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ZitlasTokens.bgCard,
        title: const Text('Mark review complete?'),
        content: Text(
          'This sends your completed review to ${r.displayName} and closes the request.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Complete')),
        ],
      ),
    );
    if (ok != true) return;
    await _run(r.id, () => c.completeReview(r), '✅ Review sent to athlete.');
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<ExpertDashboardController>();

    final buckets = [c.pendingReviews, c.inProgressReviews, c.completedReviews];
    final list = buckets[_tab];

    // Empty-state copy per tab, verbatim from ED:4579-4590.
    const emptyStates = [
      ('📋', 'No Pending Reviews', 'New athlete requests will appear here.'),
      ('💬', 'No Active Reviews', 'Accepted reviews open here for consultation.'),
      ('✅', 'No Completed Reviews', 'Finished reviews are archived here.'),
    ];

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
      children: [
        const EdSectionLabel('Reviews Inbox'),
        EdTabStrip(
          labels: const ['Pending', 'In Progress', 'Completed'],
          badges: [c.pendingReviews.length, c.inProgressReviews.length, 0],
          activeIndex: _tab,
          onChanged: (i) => setState(() => _tab = i),
        ),
        const SizedBox(height: 14),
        if (c.reviewsLoading)
          const EdLoading()
        else if (c.reviewsError != null)
          ZitlasCard(
            child: EdErrorState(
              message: edErrorMessage(c.reviewsError, what: 'your review requests'),
            ),
          )
        else if (list.isEmpty)
          ZitlasCard(
            padding: EdgeInsets.zero,
            child: EdEmptyState(
              icon: emptyStates[_tab].$1,
              title: emptyStates[_tab].$2,
              subtitle: emptyStates[_tab].$3,
            ),
          )
        else
          for (final r in list)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _ReviewCard(
                review: r,
                fee: c.profile?.fee ?? 0,
                busy: _busy.contains(r.id),
                onAccept: () => _accept(c, r),
                onReject: () => _confirmReject(c, r),
                onChat: () => widget.onOpenChat(r),
                onComplete: () => _confirmComplete(c, r),
                onEditPlan: () => widget.onEditPlan(r),
              ),
            ),
      ],
    );
  }
}

/// `_prBuildInboxCard` (ED:4616-4695) — header row, meta, and the exact
/// per-status button/stamp matrix.
class _ReviewCard extends StatelessWidget {
  const _ReviewCard({
    required this.review,
    required this.fee,
    required this.busy,
    required this.onAccept,
    required this.onReject,
    required this.onChat,
    required this.onComplete,
    required this.onEditPlan,
  });

  final ReviewRequest review;
  final int fee;
  final bool busy;
  final VoidCallback onAccept;
  final VoidCallback onReject;
  final VoidCallback onChat;
  final VoidCallback onComplete;
  final VoidCallback onEditPlan;

  @override
  Widget build(BuildContext context) {
    final price = review.totalPrice ?? fee;

    return ZitlasCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (review.isPremium) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: ZitlasTokens.primary,
                borderRadius: BorderRadius.circular(999),
              ),
              child: const Text(
                '⭐ PRIORITY · PREMIUM',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 9.5,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.4,
                ),
              ),
            ),
            const SizedBox(height: 10),
          ],
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              EdAvatar(name: review.displayName, size: 42),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      review.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: ZitlasTokens.textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      review.typeLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: ZitlasTokens.textSecondary,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      edTimeAgo(review.createdAt),
                      style: const TextStyle(color: ZitlasTokens.textMuted, fontSize: 11),
                    ),
                  ],
                ),
              ),
              if (review.totalPrice != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                  decoration: BoxDecoration(
                    color: ZitlasTokens.border,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '₹${review.totalPrice}',
                    style: const TextStyle(
                      color: ZitlasTokens.primaryDark,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          ..._actions(price),
        ],
      ),
    );
  }

  List<Widget> _actions(num price) {
    // Bundled secondary — accepting the primary starts both (ED:4631).
    if (review.status == ReviewStatus.pending && review.isBundledSecondary) {
      return const [
        EdStamp('🔗 Bundled with Diet Review — accept that to start both'),
      ];
    }

    if (review.status == ReviewStatus.pending) {
      return [
        Row(
          children: [
            Expanded(
              flex: 2,
              child: EdActionButton(
                label: '✅ Accept (₹$price)',
                onPressed: onAccept,
                busy: busy,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: EdActionButton(
                label: '✕ Reject',
                onPressed: onReject,
                filled: false,
                danger: true,
              ),
            ),
          ],
        ),
      ];
    }

    if (review.status == ReviewStatus.inProgress) {
      if (review.awaitingPayment) {
        return const [EdStamp('⏳ Awaiting Payment')];
      }
      // Diet/workout reviews go through the plan editor (modify-diet.html/
      // modify-workout.html equivalent) — it sets review_completed itself
      // once the expert saves, so there's no separate bare "Complete" here.
      // chat_only reviews have no plan to edit, so "Complete" still applies.
      final hasEditablePlan = review.reviewType == 'diet' || review.reviewType == 'workout';
      return [
        Row(
          children: [
            Expanded(
              child: EdActionButton(label: '💬 Chat', onPressed: onChat, filled: false),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: hasEditablePlan
                  ? EdActionButton(label: '✏️ Review & Send', onPressed: onEditPlan, busy: busy)
                  : EdActionButton(label: '✅ Complete', onPressed: onComplete, busy: busy),
            ),
          ],
        ),
      ];
    }

    if (review.status == ReviewStatus.rejected) {
      return const [EdStamp('✕ Rejected', color: ZitlasTokens.danger)];
    }

    return const [EdStamp('✅ Review Sent to Athlete', color: ZitlasTokens.success)];
  }
}
