import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../auth_visuals.dart';
import 'auth_icons.dart';

/// Native rebuild of the `.grm-backdrop`/`.grm-card` modal in
/// `login.html`/`login.css` — the role picker shown when a Google sign-in
/// has no matching `users/{uid}` doc yet. Visual source of truth: the
/// `#grmUserStrip`, `#grmOptAthlete`/`#grmOptExpert`, and `#grmConfirm`
/// markup/CSS in the website's login page.
Future<String?> showGoogleRolePicker(BuildContext context, User user) {
  return showModalBottomSheet<String>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (context) => _GoogleRolePickerSheet(user: user),
  );
}

class _GoogleRolePickerSheet extends StatefulWidget {
  const _GoogleRolePickerSheet({required this.user});
  final User user;

  @override
  State<_GoogleRolePickerSheet> createState() => _GoogleRolePickerSheetState();
}

class _GoogleRolePickerSheetState extends State<_GoogleRolePickerSheet> {
  String? _chosenRole;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Container(
          width: double.infinity,
          constraints: const BoxConstraints(maxWidth: 420),
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            color: AuthColors.cardSolid,
            borderRadius: BorderRadius.circular(kAuthRadiusXl),
            boxShadow: kAuthCardShadow,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // .grm-user-strip
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: const Color(0x0A111827),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 20,
                      backgroundColor: AuthColors.border,
                      backgroundImage:
                          widget.user.photoURL != null ? NetworkImage(widget.user.photoURL!) : null,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.user.displayName ?? 'User',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AuthColors.ink,
                              fontSize: 13.5,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          Text(
                            widget.user.email ?? '',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: AuthColors.muted, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0x1F00C2FF),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: const Text(
                        'Google',
                        style: TextStyle(
                          color: AuthColors.cyan,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              const Text(
                'Select Account Type',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AuthColors.ink,
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.4,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'How will you use ZITLAS?',
                textAlign: TextAlign.center,
                style: TextStyle(color: AuthColors.muted, fontSize: 13.5),
              ),
              const SizedBox(height: 20),
              _RoleOption(
                iconPath: AuthIconPaths.athlete,
                title: 'Athlete',
                subtitle: 'Track fitness, get AI diet plans, consult experts',
                selected: _chosenRole == 'athlete',
                onTap: () => setState(() => _chosenRole = 'athlete'),
              ),
              const SizedBox(height: 10),
              _RoleOption(
                iconPath: AuthIconPaths.expert,
                title: 'Expert',
                subtitle: 'Review plans, guide athletes, publish revisions',
                selected: _chosenRole == 'expert',
                onTap: () => setState(() => _chosenRole = 'expert'),
              ),
              const SizedBox(height: 20),
              SizedBox(
                height: 50,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    gradient: _chosenRole == null
                        ? null
                        : const LinearGradient(colors: [AuthColors.orange, AuthColors.orange2]),
                    color: _chosenRole == null ? AuthColors.border : null,
                    boxShadow: _chosenRole == null ? null : kAuthButtonGlow,
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: _chosenRole == null
                          ? null
                          : () => Navigator.of(context).pop(_chosenRole),
                      child: Center(
                        child: Text(
                          'Continue',
                          style: TextStyle(
                            color: _chosenRole == null ? AuthColors.muted : AuthColors.btnLoginText,
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// `.grm-option`
class _RoleOption extends StatelessWidget {
  const _RoleOption({
    required this.iconPath,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  final String iconPath;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: selected ? const Color(0x14FF8C00) : const Color(0x99FFFFFF),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: selected ? AuthColors.orange : AuthColors.border, width: 2),
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0x29FF8C00), Color(0x2400C2FF)],
                ),
              ),
              child: Center(child: AuthIcon(iconPath, size: 20, color: AuthColors.orange)),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(color: AuthColors.ink, fontSize: 14.5),
                  ),
                  Text(
                    subtitle,
                    style: const TextStyle(color: AuthColors.muted, fontSize: 12, height: 1.4),
                  ),
                ],
              ),
            ),
            AnimatedScale(
              duration: const Duration(milliseconds: 180),
              scale: selected ? 1 : 0.6,
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 180),
                opacity: selected ? 1 : 0,
                child: Container(
                  width: 22,
                  height: 22,
                  decoration: const BoxDecoration(color: AuthColors.orange, shape: BoxShape.circle),
                  child: AuthIcon(AuthIconPaths.check, size: 12, color: Colors.white, strokeWidth: 2.5),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
