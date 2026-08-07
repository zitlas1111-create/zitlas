import 'package:flutter/material.dart';

import '../../../../core/theme/zitlas_tokens.dart';
import '../../../../core/utils/safe_image.dart';
import '../../../expert_dashboard/models/expert_models.dart' show ExpertProfile;
import '../../diet_controller.dart';

/// Expert picker + submit action for `submitVerifyRequest()` — sourced from
/// the live `experts` Firestore collection (approved-only) rather than the
/// website's `zitlas_nutritionists` localStorage cache, which depends on
/// browsing a marketplace page not yet built in this app. Same underlying
/// data the marketplace itself would read.
Future<void> showRequestReviewSheet(
  BuildContext context, {
  required DietController controller,
  required String userName,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _RequestReviewSheet(controller: controller, userName: userName),
  );
}

class _RequestReviewSheet extends StatefulWidget {
  const _RequestReviewSheet({required this.controller, required this.userName});

  final DietController controller;
  final String userName;

  @override
  State<_RequestReviewSheet> createState() => _RequestReviewSheetState();
}

class _RequestReviewSheetState extends State<_RequestReviewSheet> {
  String? _selectedExpertId;
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    widget.controller.loadApprovedExperts();
  }

  Future<void> _submit(ExpertProfile expert) async {
    setState(() {
      _submitting = true;
      _error = null;
      _selectedExpertId = expert.uid;
    });
    await widget.controller.requestReview(
      expertId: expert.uid,
      expertName: expert.name,
      expertRole: expert.specialization,
      userName: widget.userName,
      totalPrice: expert.fee,
    );
    if (!mounted) return;
    if (widget.controller.reviewError != null) {
      setState(() {
        _submitting = false;
        _error = 'Could not send the review request. Please try again.';
      });
    } else {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Review request sent to ${expert.name}.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final experts = widget.controller.approvedExperts;
        return Container(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.75),
          decoration: const BoxDecoration(
            color: ZitlasTokens.bgCard,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(color: ZitlasTokens.borderSub, borderRadius: BorderRadius.circular(4)),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Ask an Expert to Review',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: ZitlasTokens.textPrimary),
              ),
              const SizedBox(height: 4),
              const Text(
                'Choose an expert to review your current plan.',
                style: TextStyle(fontSize: 12.5, color: ZitlasTokens.textSecondary),
              ),
              const SizedBox(height: 14),
              if (widget.controller.loadingExperts)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (experts.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                    child: Text(
                      'No approved experts are available right now.',
                      style: TextStyle(fontSize: 13, color: ZitlasTokens.textMuted),
                    ),
                  ),
                )
              else
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: experts.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final expert = experts[index];
                      final busy = _submitting && _selectedExpertId == expert.uid;
                      return Material(
                        color: ZitlasTokens.bgCardLight,
                        borderRadius: BorderRadius.circular(16),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(16),
                          onTap: _submitting ? null : () => _submit(expert),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Row(
                              children: [
                                CircleAvatar(
                                  radius: 20,
                                  backgroundColor: ZitlasTokens.border,
                                  backgroundImage: safeImageProvider(expert.photo),
                                  child: expert.photo == null
                                      ? Text(expert.name.isNotEmpty ? expert.name[0].toUpperCase() : '?')
                                      : null,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        expert.name,
                                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: ZitlasTokens.textPrimary),
                                      ),
                                      Text(
                                        expert.specialization,
                                        style: const TextStyle(fontSize: 11.5, color: ZitlasTokens.textSecondary),
                                      ),
                                    ],
                                  ),
                                ),
                                if (busy)
                                  const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                else
                                  Text(
                                    '₹${expert.fee}',
                                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: ZitlasTokens.primaryDark),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(_error!, style: const TextStyle(fontSize: 12, color: ZitlasTokens.danger)),
              ],
            ],
          ),
        );
      },
    );
  }
}
