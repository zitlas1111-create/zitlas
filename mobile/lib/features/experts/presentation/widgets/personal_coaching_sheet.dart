import 'package:flutter/material.dart';

import '../../../../core/theme/zitlas_tokens.dart';
import '../../data/experts_repository.dart';
import '../../expert_profile_controller.dart';

/// `initPersonalCoaching()`'s request sheet (cprofile.js:3892+) — 2-step:
/// plan selection (Diet / Training / Complete "Most Popular") then a
/// confirmation summary. No payment is taken here — the reservation charge
/// only happens server-side once the expert accepts, exactly like the
/// review-request flow.
Future<void> showPersonalCoachingSheet(BuildContext context, {required ExpertProfileController controller}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _PersonalCoachingSheet(controller: controller),
  );
}

class _PersonalCoachingSheet extends StatefulWidget {
  const _PersonalCoachingSheet({required this.controller});
  final ExpertProfileController controller;

  @override
  State<_PersonalCoachingSheet> createState() => _PersonalCoachingSheetState();
}

class _PersonalCoachingSheetState extends State<_PersonalCoachingSheet> {
  String? _planType; // 'diet' | 'training' | 'complete'
  bool _confirming = false;
  bool _submitting = false;

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final rel = c.myCoachingRelationship;
    final pendingReq = c.myCoachingRequests.where((r) => r.status == 'pending').isNotEmpty
        ? c.myCoachingRequests.firstWhere((r) => r.status == 'pending')
        : null;

    if (rel != null && rel.isActive) {
      return _infoSheet(
        title: 'Already coaching with ${c.expert!.firstName}',
        body: 'Your ${rel.planLabel ?? 'coaching'} plan is active${rel.daysRemaining != null ? ' — ${rel.daysRemaining} days remaining' : ''}.',
      );
    }
    if (pendingReq != null) {
      return _infoSheet(
        title: 'Request already sent',
        body: '🟢 Payment Reserved — awaiting ${c.expert!.firstName}\'s response.',
      );
    }

    final p = c.expert!.pricing;
    final plans = [
      ('diet', '🥗 Diet Coaching', p.coachingDietPrice, false),
      ('training', '💪 Training Coaching', p.coachingTrainingPrice, false),
      ('complete', '🏆 Complete Coaching', p.coachingCompletePrice, true),
    ];

    return Container(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
      decoration: const BoxDecoration(color: ZitlasTokens.bgCard, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      padding: EdgeInsets.fromLTRB(20, 16, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: ZitlasTokens.borderSub, borderRadius: BorderRadius.circular(4)))),
            const SizedBox(height: 16),
            if (!_confirming) ...[
              const Text('Personal Coaching', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: ZitlasTokens.textPrimary)),
              const SizedBox(height: 4),
              const Text('Choose a monthly coaching plan.', style: TextStyle(fontSize: 12.5, color: ZitlasTokens.textSecondary)),
              const SizedBox(height: 14),
              ...plans.map((pl) => _planTile(pl.$1, pl.$2, pl.$3, pl.$4)),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: ZitlasTokens.primary, padding: const EdgeInsets.symmetric(vertical: 13), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                  onPressed: _planType == null ? null : () => setState(() => _confirming = true),
                  child: const Text('Continue', style: TextStyle(fontWeight: FontWeight.w800, color: Colors.white)),
                ),
              ),
            ] else ...[
              const Text('Confirm Request', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: ZitlasTokens.textPrimary)),
              const SizedBox(height: 12),
              _summaryRow('Expert', c.expert!.name),
              _summaryRow('Plan', _planLabel(_planType!)),
              _summaryRow('Price', '₹${_planPrice(p)}/mo'),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: ZitlasTokens.bgCardLight, borderRadius: BorderRadius.circular(10)),
                child: const Text(
                  'No payment now — you\'ll pay only after the expert accepts.',
                  style: TextStyle(fontSize: 11.5, color: ZitlasTokens.textSecondary),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _submitting ? null : () => setState(() => _confirming = false),
                      child: const Text('Back'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      style: FilledButton.styleFrom(backgroundColor: ZitlasTokens.primary, padding: const EdgeInsets.symmetric(vertical: 13), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                      onPressed: _submitting ? null : _submit,
                      child: _submitting
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Text('Send Request', style: TextStyle(fontWeight: FontWeight.w800, color: Colors.white)),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _infoSheet({required String title, required String body}) {
    return Container(
      decoration: const BoxDecoration(color: ZitlasTokens.bgCard, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: ZitlasTokens.textPrimary)),
          const SizedBox(height: 8),
          Text(body, style: const TextStyle(fontSize: 12.5, color: ZitlasTokens.textSecondary)),
        ],
      ),
    );
  }

  Widget _summaryRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 12.5, color: ZitlasTokens.textSecondary)),
          Text(value, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: ZitlasTokens.textPrimary)),
        ],
      ),
    );
  }

  String _planLabel(String type) => switch (type) {
    'diet' => '🥗 Diet Coaching',
    'training' => '💪 Training Coaching',
    _ => '🏆 Complete Coaching',
  };

  num _planPrice(dynamic p) => switch (_planType) {
    'diet' => p.coachingDietPrice,
    'training' => p.coachingTrainingPrice,
    _ => p.coachingCompletePrice,
  };

  Widget _planTile(String value, String title, num price, bool popular) {
    final selected = _planType == value;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: selected ? ZitlasTokens.primary.withValues(alpha: 0.08) : ZitlasTokens.bgCardLight,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => setState(() => _planType = value),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: selected ? ZitlasTokens.primary : ZitlasTokens.borderSub)),
            child: Row(
              children: [
                Icon(selected ? Icons.radio_button_checked : Icons.radio_button_unchecked, size: 18, color: selected ? ZitlasTokens.primary : ZitlasTokens.textMuted),
                const SizedBox(width: 10),
                Expanded(
                  child: Row(
                    children: [
                      Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: ZitlasTokens.textPrimary)),
                      if (popular) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(color: ZitlasTokens.primary, borderRadius: BorderRadius.circular(20)),
                          child: const Text('Most Popular', style: TextStyle(fontSize: 9, color: Colors.white, fontWeight: FontWeight.w700)),
                        ),
                      ],
                    ],
                  ),
                ),
                Text('₹$price/mo', style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: ZitlasTokens.primaryDark)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _submit() async {
    setState(() => _submitting = true);
    final ok = await widget.controller.submitCoachingRequest(planType: _planType!);
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Coaching request sent.')));
    } else {
      setState(() => _submitting = false);
      // The backend's refusals are specific (already have a pending request,
      // already have a coach, coach gone, not enough balance) and mostly
      // unretryable — show the real reason rather than a "try again" that
      // cannot work. Held long enough to read a full sentence.
      final error = widget.controller.submitError;
      final message = error is CoachingRequestException
          ? error.message
          : 'Could not send your request. Please check your connection and try again.';
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          content: Text(message),
          duration: const Duration(seconds: 6),
        ));
    }
  }
}
