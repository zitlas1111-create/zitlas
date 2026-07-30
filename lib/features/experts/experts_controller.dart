import 'dart:async';

import 'package:flutter/foundation.dart';

import 'data/experts_repository.dart';
import 'models/expert_listing.dart';

enum ExpertSort { rated, price, available }

const _specialtyKeywords = <String, List<String>>{
  'Weight Loss': ['weight loss', 'fat loss'],
  'Muscle Gain': ['muscle gain', 'strength', 'bodybuilding'],
  'PCOS': ['pcos', 'pcod'],
  'Diabetes': ['diabetes', 'diabetic'],
  'General Fitness': ['general fitness', 'fitness'],
};

/// Mirrors `coaches.js`'s marketplace state machine: `loadExpertsFromFirebase()`
/// (one-time fetch, no live listener — matches the website), `getFiltered()`
/// (specialty filter → text search → sort), and the sort comparators.
class ExpertsController extends ChangeNotifier {
  ExpertsController({required ExpertsRepository repository}) : _repository = repository {
    unawaited(load());
  }

  final ExpertsRepository _repository;
  bool _disposed = false;

  bool loading = true;
  Object? error;
  List<ExpertListing> _all = const [];

  String searchQuery = '';
  String specialty = 'All';
  ExpertSort sort = ExpertSort.rated;

  Future<void> load() async {
    loading = true;
    error = null;
    _safeNotify();
    try {
      _all = await _repository.fetchExperts();
    } catch (e) {
      error = e;
      _all = const [];
    } finally {
      loading = false;
      _safeNotify();
    }
  }

  void setSearch(String q) {
    searchQuery = q;
    _safeNotify();
  }

  void setSpecialty(String s) {
    specialty = s;
    _safeNotify();
  }

  void setSort(ExpertSort s) {
    sort = s;
    _safeNotify();
  }

  bool get hasAnyExperts => _all.isNotEmpty;

  /// `getFiltered()` (coaches.js:206-244).
  List<ExpertListing> get filtered {
    var list = _all;

    if (specialty != 'All') {
      final keywords = _specialtyKeywords[specialty] ?? [specialty.toLowerCase()];
      list = list.where((e) {
        final haystack = ('${e.role} ${e.expertise.join(' ')}').toLowerCase();
        return keywords.any(haystack.contains);
      }).toList();
    }

    final q = searchQuery.trim().toLowerCase();
    if (q.isNotEmpty) {
      list = list.where((e) {
        final haystack = ('${e.name} ${e.role} ${e.expertise.join(' ')}').toLowerCase();
        return haystack.contains(q);
      }).toList();
    }

    final sorted = List<ExpertListing>.of(list);
    switch (sort) {
      case ExpertSort.rated:
        sorted.sort((a, b) {
          final r = b.ratingValue.compareTo(a.ratingValue);
          return r != 0 ? r : b.reviewCount.compareTo(a.reviewCount);
        });
        break;
      case ExpertSort.price:
        sorted.sort(
          (a, b) => a.pricing.lowestReviewPrice.compareTo(b.pricing.lowestReviewPrice),
        );
        break;
      case ExpertSort.available:
        sorted.sort((a, b) {
          if (a.availableToday != b.availableToday) return a.availableToday ? -1 : 1;
          return b.ratingValue.compareTo(a.ratingValue);
        });
        break;
    }
    return sorted;
  }

  void _safeNotify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
