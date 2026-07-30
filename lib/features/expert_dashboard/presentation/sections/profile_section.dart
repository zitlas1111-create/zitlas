import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/theme/zitlas_tokens.dart';
import '../../../auth/sign_out_action.dart';
import '../../expert_dashboard_controller.dart';
import '../../models/expert_models.dart';
import '../widgets/edit_profile_sheet.dart';
import '../widgets/expert_common.dart';

/// `#sectionProfile` — full expert profile, stats, fees, pricing card,
/// professional certificates, edit profile, logout and delete account.
class ExpertProfileSection extends StatelessWidget {
  const ExpertProfileSection({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.watch<ExpertDashboardController>();
    final p = c.profile;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        const EdSectionLabel('My Profile'),
        if (p == null)
          ZitlasCard(child: c.profileLoading ? const EdLoading() : const SizedBox(height: 60))
        else ...[
          _ProfileHeaderCard(profile: p),
          const SizedBox(height: 14),
          _StatsCard(profile: p),
          const SizedBox(height: 14),
          _FeesCard(profile: p),
          const SizedBox(height: 14),
          const _PricingCard(),
          const SizedBox(height: 20),
          const EdSectionLabel('Professional Certification'),
          _CertificatesCard(
            certificates: c.certificates,
            loading: c.certificatesLoading,
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton.icon(
              onPressed: () => showEditProfileSheet(context, c, p),
              icon: const Icon(Icons.edit_outlined, size: 17),
              label: const Text('Edit Profile'),
              style: ElevatedButton.styleFrom(
                backgroundColor: ZitlasTokens.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(kZitlasRadiusSm),
                ),
                textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
              ),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: OutlinedButton.icon(
              onPressed: () => performSignOut(context),
              icon: const Icon(Icons.logout_rounded, size: 17),
              label: const Text('Logout'),
              style: OutlinedButton.styleFrom(
                foregroundColor: ZitlasTokens.textSecondary,
                side: const BorderSide(color: ZitlasTokens.borderSub),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(kZitlasRadiusSm),
                ),
                textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
              ),
            ),
          ),
          const SizedBox(height: 10),
          const _DeleteAccountButton(),
        ],
      ],
    );
  }
}

class _ProfileHeaderCard extends StatelessWidget {
  const _ProfileHeaderCard({required this.profile});
  final ExpertProfile profile;

  @override
  Widget build(BuildContext context) {
    return ZitlasCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(child: EdAvatar(name: profile.name, size: 76, photoUrl: profile.photo)),
          const SizedBox(height: 12),
          Center(
            child: Text(
              profile.name,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: ZitlasTokens.textPrimary,
                fontSize: 20,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          Center(
            child: Text(
              profile.specialization,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: ZitlasTokens.primary,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          if (profile.title.isNotEmpty) ...[
            const SizedBox(height: 3),
            Center(
              child: Text(
                profile.title,
                textAlign: TextAlign.center,
                style: const TextStyle(color: ZitlasTokens.textMuted, fontSize: 12),
              ),
            ),
          ],
          if (profile.bio.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text(
              profile.bio,
              style: const TextStyle(
                color: ZitlasTokens.textSecondary,
                fontSize: 13,
                height: 1.5,
              ),
            ),
          ],
          if (profile.quote.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              decoration: BoxDecoration(
                color: ZitlasTokens.bgCardLight,
                borderRadius: BorderRadius.circular(kZitlasRadiusSm),
                border: const Border(
                  left: BorderSide(color: ZitlasTokens.primary, width: 3),
                ),
              ),
              child: Text(
                '"${profile.quote}"',
                style: const TextStyle(
                  color: ZitlasTokens.textSecondary,
                  fontSize: 12.5,
                  fontStyle: FontStyle.italic,
                  height: 1.45,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _StatsCard extends StatelessWidget {
  const _StatsCard({required this.profile});
  final ExpertProfile profile;

  @override
  Widget build(BuildContext context) {
    final items = [
      (profile.sessions, 'Sessions'),
      (profile.clients, 'Clients'),
      (profile.successRate, 'Success Rate'),
      (profile.experience, 'Experience'),
    ];
    return ZitlasCard(
      child: Row(
        children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0)
              const SizedBox(
                height: 34,
                child: VerticalDivider(color: ZitlasTokens.borderSub, width: 1),
              ),
            Expanded(
              child: Column(
                children: [
                  Text(
                    items[i].$1,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: ZitlasTokens.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    items[i].$2,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: ZitlasTokens.textMuted, fontSize: 9.5),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _FeesCard extends StatelessWidget {
  const _FeesCard({required this.profile});
  final ExpertProfile profile;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: ZitlasCard(
            radius: kZitlasRadiusMd,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Review Fee',
                  style: TextStyle(color: ZitlasTokens.textMuted, fontSize: 11),
                ),
                const SizedBox(height: 3),
                Text(
                  '₹${profile.fee}',
                  style: const TextStyle(
                    color: ZitlasTokens.textPrimary,
                    fontSize: 19,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: ZitlasCard(
            radius: kZitlasRadiusMd,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Session',
                  style: TextStyle(color: ZitlasTokens.textMuted, fontSize: 11),
                ),
                const SizedBox(height: 3),
                Text(
                  '${profile.sessionDuration} Min',
                  style: const TextStyle(
                    color: ZitlasTokens.textPrimary,
                    fontSize: 19,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// `.pricing-premium-card` — on the website this navigates to
/// `pricing.html`, a separate page whose migration is a later phase. The
/// card itself is reproduced (it's dashboard-facing content); tapping it
/// explains that pricing is currently managed on the web portal rather than
/// silently doing nothing.
class _PricingCard extends StatelessWidget {
  const _PricingCard();

  @override
  Widget build(BuildContext context) {
    return ZitlasCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('💰', style: TextStyle(fontSize: 22)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Pricing & Services',
                      style: TextStyle(
                        color: ZitlasTokens.textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    const Text(
                      'Configure how much you charge for your services.',
                      style: TextStyle(
                        color: ZitlasTokens.textMuted,
                        fontSize: 11.5,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          for (final item in const [
            'Review Verification',
            'Expert Chat',
            'Personal Coaching',
          ])
            Padding(
              padding: const EdgeInsets.only(bottom: 5),
              child: Row(
                children: [
                  const Text('✔', style: TextStyle(color: ZitlasTokens.success, fontSize: 12)),
                  const SizedBox(width: 8),
                  Text(
                    item,
                    style: const TextStyle(
                      color: ZitlasTokens.textSecondary,
                      fontSize: 12.5,
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            height: 42,
            child: OutlinedButton(
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Detailed pricing setup is on the ZITLAS web portal for now. '
                      'Your review fee is editable here under Edit Profile.',
                    ),
                  ),
                );
              },
              style: OutlinedButton.styleFrom(
                foregroundColor: ZitlasTokens.primary,
                side: const BorderSide(color: ZitlasTokens.border),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(kZitlasRadiusSm),
                ),
                textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
              ),
              child: const Text('Set Pricing  →'),
            ),
          ),
        ],
      ),
    );
  }
}

/// `#certListWrap` — live `expert_certificates` list. Uploading is deferred
/// (it needs multi-format file picking incl. PDF, which `file_picker` would
/// provide but is excluded from this project); viewing status is the
/// dashboard-facing half and works here.
class _CertificatesCard extends StatelessWidget {
  const _CertificatesCard({required this.certificates, required this.loading});

  final List<ExpertCertificate> certificates;
  final bool loading;

  Color _statusColor(String status) {
    switch (status) {
      case 'verified':
        return ZitlasTokens.success;
      case 'rejected':
        return ZitlasTokens.danger;
      default:
        return ZitlasTokens.primary;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (loading) return const ZitlasCard(child: EdLoading());

    if (certificates.isEmpty) {
      return const ZitlasCard(
        padding: EdgeInsets.zero,
        child: EdEmptyState(
          icon: '🎓',
          title: 'No certificates uploaded yet',
          subtitle:
              'Upload one from the ZITLAS web portal to earn the Verified Expert badge.',
        ),
      );
    }

    return Column(
      children: [
        for (final cert in certificates)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: ZitlasCard(
              radius: kZitlasRadiusMd,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          cert.certificateName ?? 'Certificate',
                          style: const TextStyle(
                            color: ZitlasTokens.textPrimary,
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: _statusColor(cert.verificationStatus).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          cert.statusLabel,
                          style: TextStyle(
                            color: _statusColor(cert.verificationStatus),
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (cert.issuingOrganization != null) ...[
                    const SizedBox(height: 3),
                    Text(
                      cert.issuingOrganization!,
                      style: const TextStyle(
                        color: ZitlasTokens.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 16,
                    runSpacing: 4,
                    children: [
                      if (cert.certificateNumber != null)
                        _MetaBit(label: 'Certificate ID', value: cert.certificateNumber!),
                      if (cert.issuedDate != null)
                        _MetaBit(label: 'Issued', value: cert.issuedDate!),
                      if (cert.expiryDate != null)
                        _MetaBit(label: 'Expires', value: cert.expiryDate!),
                      if (cert.verificationScore != null)
                        _MetaBit(label: 'Score', value: '${cert.verificationScore}%'),
                    ],
                  ),
                  if (cert.rejectionReason != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      cert.rejectionReason!,
                      style: const TextStyle(
                        color: ZitlasTokens.danger,
                        fontSize: 11.5,
                        height: 1.4,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _MetaBit extends StatelessWidget {
  const _MetaBit({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: const TextStyle(color: ZitlasTokens.textMuted, fontSize: 9.5)),
        Text(
          value,
          style: const TextStyle(
            color: ZitlasTokens.textPrimary,
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

/// Two-step destructive confirm, matching the website's own
/// `#edDeleteAccountBackdrop` → `#edDeleteAccountBackdrop2` flow.
class _DeleteAccountButton extends StatefulWidget {
  const _DeleteAccountButton();

  @override
  State<_DeleteAccountButton> createState() => _DeleteAccountButtonState();
}

class _DeleteAccountButtonState extends State<_DeleteAccountButton> {
  bool _busy = false;

  Future<void> _start() async {
    final c = context.read<ExpertDashboardController>();

    final step1 = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ZitlasTokens.bgCard,
        title: const Text('⚠️ Delete Expert Account?'),
        content: const Text(
          'This action is permanent. Deleting your account will remove your expert '
          'profile, availability and ratings.\n\nThis cannot be undone.',
          style: TextStyle(height: 1.5),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Delete Permanently',
              style: TextStyle(color: ZitlasTokens.danger),
            ),
          ),
        ],
      ),
    );
    if (step1 != true || !mounted) return;

    final step2 = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ZitlasTokens.bgCard,
        title: const Text('Are you absolutely sure?'),
        content: const Text(
          'This is your last chance to cancel. Your expert account will be '
          'permanently deleted immediately.',
          style: TextStyle(height: 1.5),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Yes, Delete Forever',
              style: TextStyle(color: ZitlasTokens.danger),
            ),
          ),
        ],
      ),
    );
    if (step2 != true || !mounted) return;

    setState(() => _busy = true);
    final ok = await c.deleteAccount();
    if (!mounted) return;
    setState(() => _busy = false);

    if (ok) {
      await performSignOut(context);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            "Couldn't delete your account. Please try again, or contact support.",
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: OutlinedButton.icon(
        onPressed: _busy ? null : _start,
        icon: _busy
            ? const SizedBox(
                width: 15,
                height: 15,
                child: CircularProgressIndicator(strokeWidth: 2, color: ZitlasTokens.danger),
              )
            : const Icon(Icons.delete_outline_rounded, size: 17),
        label: const Text('Delete Account'),
        style: OutlinedButton.styleFrom(
          foregroundColor: ZitlasTokens.danger,
          side: BorderSide(color: ZitlasTokens.danger.withValues(alpha: 0.4)),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(kZitlasRadiusSm)),
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}
