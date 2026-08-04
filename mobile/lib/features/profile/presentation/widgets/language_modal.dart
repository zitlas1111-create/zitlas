import 'package:flutter/material.dart';

import '../../../../core/storage/local_storage_service.dart';
import '../../../../core/theme/zitlas_tokens.dart';

/// `#languageModal` (profile.html/js) — exact copy and options
/// (`lang_modal_title`/`lang_modal_sub`/`lang_english`/`lang_hindi` from
/// `assets/js/i18n.js`). The website's i18n system retranslates ~150
/// `data-i18n` strings across many pages when Hindi is selected; reproducing
/// that as full app-wide localization is a separate, much larger
/// infrastructure effort out of scope for the Profile screen itself (see
/// docs/MIGRATION_INVENTORY.md Phase 9) — this modal persists the same
/// device-scoped preference key (`zitlas_language`, already carved out as
/// surviving account switches in `AccountGuard._deviceKeys`) and shows the
/// exact toast copy, but does not yet retranslate the rest of the app.
const _kLanguageKey = 'zitlas_language';

Future<void> showLanguageModal(BuildContext context) {
  return showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (_) => const _LanguageModal(),
  );
}

class _LanguageModal extends StatefulWidget {
  const _LanguageModal();

  @override
  State<_LanguageModal> createState() => _LanguageModalState();
}

class _LanguageModalState extends State<_LanguageModal> {
  late String _selected = LocalStorageService.instance.getString(_kLanguageKey) ?? 'en';

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
      decoration: const BoxDecoration(color: ZitlasTokens.bgCard, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Language', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: ZitlasTokens.textPrimary)),
              IconButton(icon: const Icon(Icons.close, color: ZitlasTokens.textSecondary), onPressed: () => Navigator.pop(context)),
            ],
          ),
          const Text('Choose your preferred language', style: TextStyle(fontSize: 13.5, color: ZitlasTokens.textSecondary)),
          const SizedBox(height: 16),
          _option('en', '🇬🇧', 'English'),
          const SizedBox(height: 10),
          _option('hi', '🇮🇳', 'हिन्दी'),
        ],
      ),
    );
  }

  Widget _option(String code, String flag, String label) {
    final selected = _selected == code;
    return Material(
      color: selected ? ZitlasTokens.primary.withValues(alpha: 0.08) : ZitlasTokens.bgCardLight,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => _select(code),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), border: Border.all(color: selected ? ZitlasTokens.primary : ZitlasTokens.borderSub)),
          child: Row(
            children: [
              Text(flag, style: const TextStyle(fontSize: 20)),
              const SizedBox(width: 12),
              Expanded(child: Text(label, style: const TextStyle(fontSize: 14.5, color: ZitlasTokens.textPrimary))),
              if (selected) const Icon(Icons.check_circle, size: 18, color: ZitlasTokens.primary),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _select(String code) async {
    setState(() => _selected = code);
    await LocalStorageService.instance.setString(_kLanguageKey, code);
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    await Future<void>.delayed(const Duration(milliseconds: 350));
    if (!mounted) return;
    Navigator.pop(context);
    messenger.showSnackBar(
      SnackBar(content: Text(code == 'hi' ? 'भाषा हिन्दी में बदली गई' : 'Language set to English')),
    );
  }
}
