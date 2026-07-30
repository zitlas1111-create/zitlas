/// Mirrors a doc at `users/{uid}/weight_log/{date}` (see `dashboard.js`'s
/// `_dashLoadWeightHistory()`/`_dashLogWeight()`).
class WeightEntry {
  const WeightEntry({required this.date, required this.weightKg});

  final DateTime date;
  final double weightKg;

  factory WeightEntry.fromMap(Map<String, dynamic> map) {
    final rawDate = map['date'];
    return WeightEntry(
      date: rawDate is String ? DateTime.parse(rawDate) : DateTime.now(),
      weightKg: (map['weightKg'] as num).toDouble(),
    );
  }
}
