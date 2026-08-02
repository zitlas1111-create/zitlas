import 'package:flutter/material.dart';

import '../../../../core/steps/step_history.dart';
import '../../../../core/steps/step_metrics.dart';
import '../../../dashboard/presentation/dashboard_visuals.dart';

/// Step History — Today, Yesterday, Last 7 Days, Last 30 Days.
///
/// Reads only what was actually recorded. A day with no record renders as
/// "No data", never as a zero: a day the phone was off, or before ZITLAS was
/// installed, is unknown, and drawing it as a flat 0 would tell the athlete
/// they didn't move when the truth is nobody was counting.
class StepHistoryScreen extends StatelessWidget {
  const StepHistoryScreen({
    super.key,
    required this.history,
    this.heightCm,
    this.weightKg,
    this.now,
  });

  final StepHistory history;

  /// Real profile values where they exist — distance and calories fall back to
  /// adult averages when they don't, and the footnote says so.
  final double? heightCm;
  final double? weightKg;

  /// Injectable for tests.
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final today = now ?? DateTime.now();
    final entries = history.window(today: today, count: 30);

    return DefaultTabController(
      length: 4,
      child: Scaffold(
        backgroundColor: DashboardColors.bgStart,
        appBar: AppBar(
          backgroundColor: DashboardColors.bgCard,
          elevation: 0,
          title: const Text(
            'Step History',
            style: TextStyle(
              color: DashboardColors.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
          iconTheme: const IconThemeData(color: DashboardColors.textPrimary),
          bottom: const TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            labelColor: DashboardColors.primary,
            unselectedLabelColor: DashboardColors.textSecondary,
            indicatorColor: DashboardColors.primary,
            labelStyle: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800),
            tabs: [
              Tab(text: 'Today'),
              Tab(text: 'Yesterday'),
              Tab(text: 'Last 7 Days'),
              Tab(text: 'Last 30 Days'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _DayView(entry: entries.first, heightCm: heightCm, weightKg: weightKg),
            if (entries.length > 1)
              _DayView(entry: entries[1], heightCm: heightCm, weightKg: weightKg)
            else
              const _EmptyState(message: 'No record for yesterday yet.'),
            _RangeView(
              entries: entries.take(7).toList(),
              heightCm: heightCm,
              weightKg: weightKg,
            ),
            _RangeView(entries: entries, heightCm: heightCm, weightKg: weightKg),
          ],
        ),
      ),
    );
  }
}

/// One day in full: every figure the task asks for, each labelled with where
/// it came from.
class _DayView extends StatelessWidget {
  const _DayView({required this.entry, this.heightCm, this.weightKg});

  final StepHistoryEntry entry;
  final double? heightCm;
  final double? weightKg;

  @override
  Widget build(BuildContext context) {
    if (!entry.hasData) {
      return _EmptyState(message: 'No steps recorded on ${_longDate(entry.date)}.');
    }
    final steps = entry.steps;
    final goal = entry.goal;
    final pct = completionPercent(steps: steps, goal: goal);
    final km = distanceKm(steps: steps, heightCm: heightCm);
    final kcal = estimatedCalories(steps: steps, weightKg: weightKg, heightCm: heightCm);
    final active = estimatedActiveMinutes(steps: steps);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
      children: [
        _Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _longDate(entry.date),
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: DashboardColors.textSecondary,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    _thousands(steps),
                    style: const TextStyle(
                      fontSize: 38,
                      fontWeight: FontWeight.w900,
                      color: DashboardColors.textPrimary,
                    ),
                  ),
                  const SizedBox(width: 6),
                  const Text(
                    'steps',
                    style: TextStyle(fontSize: 13, color: DashboardColors.textSecondary),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: (pct / 100).clamp(0.0, 1.0),
                  minHeight: 8,
                  backgroundColor: DashboardColors.borderSub,
                  valueColor: AlwaysStoppedAnimation(
                    entry.completed ? DashboardColors.success : DashboardColors.primary,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                goal > 0
                    ? '${completionPercentUncapped(steps: steps, goal: goal)}% '
                        'of a ${_thousands(goal)} step goal'
                    : 'Goal paused for this day',
                style: const TextStyle(fontSize: 12, color: DashboardColors.textSecondary),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _Card(
          child: Column(
            children: [
              _MetricRow(icon: '📏', label: 'Distance', value: '${km.toStringAsFixed(2)} km'),
              const Divider(height: 18, color: DashboardColors.borderSub),
              _MetricRow(icon: '🔥', label: 'Calories', value: '$kcal kcal'),
              const Divider(height: 18, color: DashboardColors.borderSub),
              _MetricRow(
                icon: '⏱',
                label: 'Time active',
                value: active == null
                    ? 'Not enough movement'
                    : (active >= 60 ? '${active ~/ 60}h ${active % 60}m' : '${active}m'),
              ),
              const Divider(height: 18, color: DashboardColors.borderSub),
              _MetricRow(
                icon: entry.completed ? '✅' : '⏳',
                label: 'Goal',
                value: entry.completed ? 'Completed' : 'Not reached',
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Text(
          heightCm == null || weightKg == null
              ? 'Distance and calories are estimated from your step count using '
                  'average adult height and weight — add yours in Profile for a '
                  'closer figure. Active time is estimated from walking cadence.'
              : 'Distance and calories are estimated from your step count, '
                  'height and weight. Active time is estimated from walking cadence.',
          style: const TextStyle(
            fontSize: 11,
            height: 1.5,
            color: DashboardColors.textMuted,
          ),
        ),
      ],
    );
  }
}

/// A range: the totals up top, then one row per calendar day.
class _RangeView extends StatelessWidget {
  const _RangeView({required this.entries, this.heightCm, this.weightKg});

  final List<StepHistoryEntry> entries;
  final double? heightCm;
  final double? weightKg;

  @override
  Widget build(BuildContext context) {
    final recorded = entries.where((e) => e.hasData).toList();
    if (recorded.isEmpty) {
      return const _EmptyState(message: 'No steps recorded in this period yet.');
    }
    final total = recorded.fold<int>(0, (sum, e) => sum + e.steps);
    final average = (total / recorded.length).round();
    final completed = recorded.where((e) => e.completed).length;
    final best = recorded.map((e) => e.steps).reduce((a, b) => a > b ? a : b);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
      children: [
        _Card(
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(child: _Stat(label: 'Daily average', value: _thousands(average))),
                  Expanded(child: _Stat(label: 'Best day', value: _thousands(best))),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(child: _Stat(label: 'Total steps', value: _thousands(total))),
                  Expanded(
                    child: _Stat(
                      label: 'Goals hit',
                      value: '$completed of ${recorded.length}',
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        // Averages divide by DAYS WITH DATA, not by the length of the window —
        // an unmeasured day is unknown, and counting it as a zero would report
        // a lower average than the athlete actually walked.
        if (recorded.length < entries.length)
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 6, 4, 2),
            child: Text(
              'Averaged over the ${recorded.length} recorded '
              '${recorded.length == 1 ? "day" : "days"} — days with no data are '
              'left out rather than counted as zero.',
              style: const TextStyle(
                fontSize: 11,
                height: 1.45,
                color: DashboardColors.textMuted,
              ),
            ),
          ),
        const SizedBox(height: 8),
        for (final entry in entries) _HistoryRow(entry: entry, heightCm: heightCm),
      ],
    );
  }
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({required this.entry, this.heightCm});

  final StepHistoryEntry entry;
  final double? heightCm;

  @override
  Widget build(BuildContext context) {
    final pct = entry.hasData
        ? completionPercent(steps: entry.steps, goal: entry.goal)
        : 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: DashboardColors.bgCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: DashboardColors.borderSub),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 74,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _weekday(entry.date),
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                    color: DashboardColors.textPrimary,
                  ),
                ),
                Text(
                  _shortDate(entry.date),
                  style: const TextStyle(fontSize: 11, color: DashboardColors.textMuted),
                ),
              ],
            ),
          ),
          Expanded(
            child: entry.hasData
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${_thousands(entry.steps)} steps  ·  '
                        '${distanceKm(steps: entry.steps, heightCm: heightCm).toStringAsFixed(1)} km',
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: DashboardColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 5),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: LinearProgressIndicator(
                          value: (pct / 100).clamp(0.0, 1.0),
                          minHeight: 5,
                          backgroundColor: DashboardColors.borderSub,
                          valueColor: AlwaysStoppedAnimation(
                            entry.completed
                                ? DashboardColors.success
                                : DashboardColors.primary,
                          ),
                        ),
                      ),
                    ],
                  )
                : const Text(
                    'No data',
                    style: TextStyle(fontSize: 12.5, color: DashboardColors.textMuted),
                  ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 44,
            child: Text(
              entry.hasData ? '$pct%' : '—',
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
                color: entry.completed
                    ? DashboardColors.success
                    : DashboardColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});
  final String label, value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: const TextStyle(
            fontSize: 19,
            fontWeight: FontWeight.w900,
            color: DashboardColors.textPrimary,
          ),
        ),
        Text(
          label,
          style: const TextStyle(fontSize: 11, color: DashboardColors.textSecondary),
        ),
      ],
    );
  }
}

class _MetricRow extends StatelessWidget {
  const _MetricRow({required this.icon, required this.label, required this.value});
  final String icon, label, value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(icon, style: const TextStyle(fontSize: 14)),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(fontSize: 12.5, color: DashboardColors.textSecondary),
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w800,
            color: DashboardColors.textPrimary,
          ),
        ),
      ],
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: DashboardColors.bgCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: DashboardColors.borderSub),
      ),
      child: child,
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('👣', style: TextStyle(fontSize: 30)),
            const SizedBox(height: 10),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13,
                height: 1.5,
                color: DashboardColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

String _weekday(DateTime d) {
  final today = DateTime.now();
  if (d.year == today.year && d.month == today.month && d.day == today.day) {
    return 'Today';
  }
  final yesterday = DateTime(today.year, today.month, today.day - 1);
  if (d.year == yesterday.year && d.month == yesterday.month && d.day == yesterday.day) {
    return 'Yesterday';
  }
  return _weekdays[d.weekday - 1];
}

String _shortDate(DateTime d) => '${d.day} ${_months[d.month - 1]}';

String _longDate(DateTime d) =>
    '${_weekdays[d.weekday - 1]}, ${d.day} ${_months[d.month - 1]} ${d.year}';

String _thousands(int n) {
  final s = n.toString();
  final buf = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
    buf.write(s[i]);
  }
  return buf.toString();
}
