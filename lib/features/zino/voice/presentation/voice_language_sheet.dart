import 'package:flutter/material.dart';

import '../../../../core/theme/zitlas_tokens.dart';
import '../../../../core/voice/voice_language.dart';

/// "Choose Your Preferred Language" — shown ONCE, the first time an athlete
/// opens Talk with Zino.
///
/// [current] pre-selects the existing choice when this is opened from Profile
/// to CHANGE the language rather than to set it initially.
Future<VoiceLanguage?> showVoiceLanguageSheet(
  BuildContext context, {
  VoiceLanguage? current,
  bool dismissible = true,
}) {
  return showModalBottomSheet<VoiceLanguage>(
    context: context,
    isScrollControlled: true,
    isDismissible: dismissible,
    enableDrag: dismissible,
    backgroundColor: Colors.transparent,
    builder: (_) => _VoiceLanguageSheet(current: current, dismissible: dismissible),
  );
}

class _VoiceLanguageSheet extends StatelessWidget {
  const _VoiceLanguageSheet({required this.current, required this.dismissible});

  final VoiceLanguage? current;
  final bool dismissible;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // On first run there's no sensible "no language" state to fall back to,
      // so the sheet must be answered rather than dismissed.
      canPop: dismissible,
      child: Container(
        decoration: const BoxDecoration(
          color: ZitlasTokens.bgCard,
          borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
        ),
        padding: const EdgeInsets.fromLTRB(22, 14, 22, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: ZitlasTokens.borderSub,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
            const SizedBox(height: 22),
            const Text(
              'Choose Your Preferred Language',
              style: TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w800,
                color: ZitlasTokens.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              "This is how I'll talk with you. You can change it any time in Profile.",
              style: TextStyle(fontSize: 13, height: 1.5, color: ZitlasTokens.textSecondary),
            ),
            const SizedBox(height: 18),
            for (final lang in VoiceLanguage.values)
              _LanguageTile(
                language: lang,
                selected: lang == current,
                onTap: () => Navigator.of(context).pop(lang),
              ),
          ],
        ),
      ),
    );
  }
}

class _LanguageTile extends StatelessWidget {
  const _LanguageTile({
    required this.language,
    required this.selected,
    required this.onTap,
  });

  final VoiceLanguage language;
  final bool selected;
  final VoidCallback onTap;

  /// A one-line sample in the language itself — far more informative than the
  /// name alone, especially for Hinglish, which people recognise instantly
  /// when they see it but may not know by label.
  String get _sample => switch (language) {
        VoiceLanguage.english => "Let's crush today's workout.",
        VoiceLanguage.hindi => 'चलिए, आज का वर्कआउट शुरू करते हैं।',
        VoiceLanguage.hinglish => 'Chalo, aaj ka workout shuru karte hain.',
      };

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: selected
            ? ZitlasTokens.primary.withValues(alpha: 0.10)
            : ZitlasTokens.bgCardLight,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: selected ? ZitlasTokens.primary : ZitlasTokens.borderSub,
                width: selected ? 1.6 : 1,
              ),
            ),
            child: Row(
              children: [
                Text(language.flag, style: const TextStyle(fontSize: 22)),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            language.label,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: ZitlasTokens.textPrimary,
                            ),
                          ),
                          if (language.recommended) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                              decoration: BoxDecoration(
                                color: ZitlasTokens.primary,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: const Text(
                                'Recommended',
                                style: TextStyle(
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _sample,
                        style: const TextStyle(fontSize: 12, color: ZitlasTokens.textMuted),
                      ),
                    ],
                  ),
                ),
                if (selected)
                  const Icon(Icons.check_circle_rounded,
                      size: 20, color: ZitlasTokens.primary),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
