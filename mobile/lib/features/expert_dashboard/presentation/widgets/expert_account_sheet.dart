import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../app/theme.dart';
import '../../../auth/auth_state.dart';
import '../../../auth/sign_out_action.dart';

/// Account menu opened from the profile icon in the Expert Dashboard's
/// AppBar — expert name/email plus a single Sign Out action. Uses the same
/// [performSignOut] every authenticated role signs out through.
Future<void> showExpertAccountSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: ZitlasColors.bgCard,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (context) => const _ExpertAccountSheet(),
  );
}

class _ExpertAccountSheet extends StatelessWidget {
  const _ExpertAccountSheet();

  @override
  Widget build(BuildContext context) {
    final profile = context.watch<AuthState>().profile;
    final name = profile?.name?.trim();
    final email = profile?.email ?? '';

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 22,
                  backgroundColor: ZitlasColors.bgCardLight,
                  child: Text(
                    _initials(name, email),
                    style: const TextStyle(
                      color: ZitlasColors.primary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (name != null && name.isNotEmpty)
                        Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: ZitlasColors.textPrimary,
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      Text(
                        email,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: ZitlasColors.textSecondary,
                          fontSize: name != null && name.isNotEmpty ? 13 : 15,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Divider(color: ZitlasColors.border, height: 1),
            const SizedBox(height: 4),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.logout_rounded, color: ZitlasColors.error),
              title: const Text(
                'Sign Out',
                style: TextStyle(color: ZitlasColors.error, fontWeight: FontWeight.w600),
              ),
              onTap: () async {
                Navigator.of(context).pop();
                await performSignOut(context);
              },
            ),
          ],
        ),
      ),
    );
  }

  String _initials(String? name, String email) {
    if (name != null && name.isNotEmpty) {
      final parts = name.trim().split(RegExp(r'\s+'));
      if (parts.length == 1) return parts[0].substring(0, 1).toUpperCase();
      return (parts[0].substring(0, 1) + parts[1].substring(0, 1)).toUpperCase();
    }
    if (email.isNotEmpty) return email.substring(0, 1).toUpperCase();
    return '?';
  }
}
