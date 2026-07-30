import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/theme/zitlas_tokens.dart';
import '../../data/expert_repository.dart';
import '../../expert_dashboard_controller.dart';
import '../../models/expert_models.dart';
import '../widgets/expert_common.dart';

/// `#sectionCoaching` — Personal Coaching requests with Pending / Active /
/// Past Clients tabs. Accept and decline are server-authoritative: they call
/// `/api/coaching/accept|reject` with a Firebase ID token, exactly as
/// `_pcUpdateRequestStatus` does (ED:1529-1559). The client never writes
/// these Firestore docs itself.
class ExpertCoachingSection extends StatefulWidget {
  const ExpertCoachingSection({super.key, required this.onOpenChat});

  final void Function(CoachingRequest) onOpenChat;

  @override
  State<ExpertCoachingSection> createState() => _ExpertCoachingSectionState();
}

class _ExpertCoachingSectionState extends State<ExpertCoachingSection> {
  int _tab = 0;
  final _busy = <String>{};

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _respond(
    ExpertDashboardController c,
    CoachingRequest req, {
    required bool accept,
  }) async {
    if (!accept) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: ZitlasTokens.bgCard,
          title: const Text('Decline this request?'),
          content: Text(
            "${req.athleteName ?? 'The athlete'}'s reserved payment will be released.",
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Decline', style: TextStyle(color: ZitlasTokens.danger)),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }

    setState(() => _busy.add(req.id));
    final result = await c.respondToCoaching(req, accept: accept);
    if (!mounted) return;
    setState(() => _busy.remove(req.id));

    // Result messages verbatim from ED:1544-1553.
    switch (result) {
      case CoachingActionResult.success:
        _toast(accept
            ? '✅ Accepted — payment auto-debited, coaching is now active.'
            : 'Request declined — reservation released.');
      case CoachingActionResult.alreadyHandled:
        _toast('This request was already handled.');
      case CoachingActionResult.failed:
        _toast('Could not update the request. Please try again.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<ExpertDashboardController>();
    final buckets = [c.pendingCoaching, c.activeCoaching, c.pastCoaching];
    final list = buckets[_tab];

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
      children: [
        const EdSectionLabel('Personal Coaching'),
        EdTabStrip(
          labels: const ['Pending', 'Active', 'Past Clients'],
          badges: [c.pendingCoaching.length, 0, 0],
          activeIndex: _tab,
          onChanged: (i) => setState(() => _tab = i),
        ),
        const SizedBox(height: 14),
        if (c.coachingLoading)
          const EdLoading()
        else if (c.coachingError != null)
          ZitlasCard(
            child: EdErrorState(
              message: edErrorMessage(c.coachingError, what: 'coaching requests'),
            ),
          )
        else if (list.isEmpty)
          const ZitlasCard(
            padding: EdgeInsets.zero,
            child: EdEmptyState(
              icon: '👨‍🏫',
              title: 'No coaching requests',
              subtitle:
                  'Athletes who request Personal Coaching with you will appear here.',
            ),
          )
        else
          for (final req in list)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _CoachingCard(
                req: req,
                busy: _busy.contains(req.id),
                onAccept: () => _respond(c, req, accept: true),
                onDecline: () => _respond(c, req, accept: false),
                onChat: () => widget.onOpenChat(req),
              ),
            ),
      ],
    );
  }
}

/// The coaching request card (ED:1459-1520).
class _CoachingCard extends StatelessWidget {
  const _CoachingCard({
    required this.req,
    required this.busy,
    required this.onAccept,
    required this.onDecline,
    required this.onChat,
  });

  final CoachingRequest req;
  final bool busy;
  final VoidCallback onAccept;
  final VoidCallback onDecline;
  final VoidCallback onChat;

  @override
  Widget build(BuildContext context) {
    final planLine = [
      req.planLabel ?? req.planType ?? 'Personal Coaching',
      if (req.price != null) '₹${req.price}/mo',
    ].join(' · ');

    return ZitlasCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              EdAvatar(name: req.athleteName ?? 'Athlete', size: 42),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            req.athleteName ?? 'Athlete',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: ZitlasTokens.textPrimary,
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        if (req.isPremium) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: ZitlasTokens.primary,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: const Text(
                              '⭐ PRIORITY',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 8.5,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${req.planIcon} $planLine',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: ZitlasTokens.textSecondary,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      req.statusLine,
                      maxLines: 2,
                      style: TextStyle(
                        color: req.status == 'pending'
                            ? ZitlasTokens.success
                            : ZitlasTokens.textMuted,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (req.status == 'pending') ...[
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: EdActionButton(
                    label: 'Decline',
                    onPressed: onDecline,
                    filled: false,
                    danger: true,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: EdActionButton(label: 'Accept', onPressed: onAccept, busy: busy),
                ),
              ],
            ),
          ] else if (req.status == 'active' || req.status == 'ended') ...[
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: EdActionButton(
                label: req.status == 'active' ? 'Chat' : 'View Chat',
                onPressed: onChat,
                filled: false,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
