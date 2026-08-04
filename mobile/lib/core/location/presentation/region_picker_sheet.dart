import 'package:flutter/material.dart';

import '../../theme/zitlas_tokens.dart';
import '../indian_states.dart';

/// Part E — manual region selector. Search box + the exact backend-supported
/// state/UT list (`kSupportedDietRegions`) — never an invented label.
Future<String?> showRegionPickerSheet(BuildContext context, {String? current}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _RegionPickerSheet(current: current),
  );
}

class _RegionPickerSheet extends StatefulWidget {
  const _RegionPickerSheet({this.current});
  final String? current;

  @override
  State<_RegionPickerSheet> createState() => _RegionPickerSheetState();
}

class _RegionPickerSheetState extends State<_RegionPickerSheet> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final filtered = kSupportedDietRegions.where((s) => s.toLowerCase().contains(_query.toLowerCase())).toList();
    return Container(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.8),
      decoration: const BoxDecoration(color: ZitlasTokens.bgCard, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      padding: EdgeInsets.fromLTRB(20, 16, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: ZitlasTokens.borderSub, borderRadius: BorderRadius.circular(4)))),
          const SizedBox(height: 16),
          const Text('Preferred Food Region', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: ZitlasTokens.textPrimary)),
          const SizedBox(height: 12),
          TextField(
            autofocus: true,
            onChanged: (v) => setState(() => _query = v),
            decoration: InputDecoration(
              hintText: 'Search state...',
              hintStyle: const TextStyle(color: ZitlasTokens.textMuted, fontSize: 13.5),
              prefixIcon: const Icon(Icons.search, color: ZitlasTokens.textMuted, size: 20),
              filled: true,
              fillColor: ZitlasTokens.bgCardLight,
              contentPadding: const EdgeInsets.symmetric(vertical: 10),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            ),
          ),
          const SizedBox(height: 8),
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: filtered.length,
              itemBuilder: (context, i) {
                final state = filtered[i];
                final selected = state == widget.current;
                return ListTile(
                  title: Text(state, style: TextStyle(fontSize: 14, color: ZitlasTokens.textPrimary, fontWeight: selected ? FontWeight.w800 : FontWeight.w500)),
                  trailing: selected ? const Icon(Icons.check_circle, color: ZitlasTokens.primary, size: 18) : null,
                  onTap: () => Navigator.of(context).pop(state),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
