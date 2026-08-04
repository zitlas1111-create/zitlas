import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/theme/zitlas_tokens.dart';
import '../../data/food_search_repository.dart';

/// Searchable picker over the real ZITLAS food database.
///
/// Used for both "Swap" (replace an existing item) and "Add Food". Returns the
/// chosen [FoodSearchResult], or null if dismissed.
Future<FoodSearchResult?> showFoodSearchSheet(
  BuildContext context, {
  required String title,
  FoodSearchRepository? repository,
  String? initialQuery,
}) {
  return showModalBottomSheet<FoodSearchResult>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _FoodSearchSheet(
      title: title,
      repository: repository ?? FoodSearchRepository(),
      initialQuery: initialQuery,
    ),
  );
}

class _FoodSearchSheet extends StatefulWidget {
  const _FoodSearchSheet({
    required this.title,
    required this.repository,
    this.initialQuery,
  });

  final String title;
  final FoodSearchRepository repository;
  final String? initialQuery;

  @override
  State<_FoodSearchSheet> createState() => _FoodSearchSheetState();
}

class _FoodSearchSheetState extends State<_FoodSearchSheet> {
  late final TextEditingController _query = TextEditingController(
    text: widget.initialQuery ?? '',
  );
  Timer? _debounce;

  List<FoodSearchResult> _results = const [];
  bool _loading = false;
  Object? _error;

  // Optional narrowing filters — all off by default so a plain name search
  // just works.
  String? _region;
  bool _highProtein = false;

  static const _regions = [
    'West',
    'North',
    'South',
    'East',
    'Northeast',
    'Central',
    'Pan-India',
  ];

  @override
  void initState() {
    super.initState();
    _search();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _query.dispose();
    super.dispose();
  }

  /// Debounced so typing a food name doesn't fire a request per keystroke.
  void _onQueryChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 320), _search);
  }

  Future<void> _search() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await widget.repository.search(
        query: _query.text.trim(),
        region: _region,
        minProtein: _highProtein ? 15 : null,
        limit: 40,
      );
      if (!mounted) return;
      setState(() {
        _results = results;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      // Material, not a plain Container: the result rows are ListTiles, and
      // they paint their ink splash onto the nearest Material ancestor. With
      // only a coloured DecoratedBox above them the ripple is painted behind
      // the background and never seen, so tapping a food looks unresponsive.
      child: Material(
        color: ZitlasTokens.bgCard,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        clipBehavior: Clip.antiAlias,
        child: Container(
          height: MediaQuery.of(context).size.height * 0.82,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Column(
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
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: ZitlasTokens.textPrimary,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(
                      Icons.close_rounded,
                      color: ZitlasTokens.textSecondary,
                    ),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _query,
                autofocus: true,
                onChanged: _onQueryChanged,
                onSubmitted: (_) => _search(),
                decoration: InputDecoration(
                  hintText: 'Search 4,500+ foods…',
                  prefixIcon: const Icon(Icons.search_rounded, size: 20),
                  isDense: true,
                  filled: true,
                  fillColor: ZitlasTokens.bgCardLight,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                height: 34,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    _Chip(
                      label: '💪 High protein',
                      selected: _highProtein,
                      onTap: () {
                        setState(() => _highProtein = !_highProtein);
                        _search();
                      },
                    ),
                    for (final r in _regions)
                      _Chip(
                        label: r,
                        selected: _region == r,
                        onTap: () {
                          setState(() => _region = _region == r ? null : r);
                          _search();
                        },
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Expanded(child: _resultsView()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _resultsView() {
    if (_loading && _results.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(color: ZitlasTokens.primary),
      );
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                "Couldn't load the food database.",
                style: TextStyle(color: ZitlasTokens.textSecondary),
              ),
              const SizedBox(height: 10),
              TextButton(onPressed: _search, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }
    if (_results.isEmpty) {
      return const Center(
        child: Text(
          'No foods match that search.',
          style: TextStyle(color: ZitlasTokens.textMuted),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.only(bottom: 20),
      itemCount: _results.length,
      separatorBuilder: (_, _) =>
          const Divider(height: 1, color: ZitlasTokens.borderSub),
      itemBuilder: (context, i) {
        final f = _results[i];
        return ListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 4,
            vertical: 2,
          ),
          title: Text(
            f.name,
            style: const TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w700,
              color: ZitlasTokens.textPrimary,
            ),
          ),
          subtitle: Text(
            [
              if (f.servingSize != null) f.servingSize!,
              if (f.calories != null) '${f.calories} kcal',
              if (f.protein != null) '${f.protein}g P',
              if (f.region != null) f.region!,
            ].join(' · '),
            style: const TextStyle(
              fontSize: 11.5,
              color: ZitlasTokens.textMuted,
            ),
          ),
          trailing: const Icon(
            Icons.add_circle_outline_rounded,
            size: 20,
            color: ZitlasTokens.primary,
          ),
          onTap: () => Navigator.of(context).pop(f),
        );
      },
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? ZitlasTokens.primary : ZitlasTokens.bgCardLight,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected ? ZitlasTokens.primary : ZitlasTokens.borderSub,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: selected ? Colors.white : ZitlasTokens.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}
