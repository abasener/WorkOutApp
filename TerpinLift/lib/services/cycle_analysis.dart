import '../data/models/cycle_entry.dart';

class CycleStats {
  final List<int> periodLengths; // days per period, oldest first
  final List<int> cycleLengths; // days between period starts, oldest first
  final double? avgPeriodLength;
  final double? avgCycleLength;

  const CycleStats({
    required this.periodLengths,
    required this.cycleLengths,
    this.avgPeriodLength,
    this.avgCycleLength,
  });
}

/// Derives period episodes and cycle lengths from raw flow entries — there's
/// no separate "period start/end" record, a period is just a run of
/// consecutive days with flow > 0. See designFiles/01_DATA_MODEL.md.
class CycleAnalysis {
  static CycleStats compute(List<CycleEntry> flowEntries) {
    final periodDays = flowEntries
        .where((e) => (e.flowValue ?? 0) > 0)
        .map((e) => DateTime.parse(e.date))
        .toList()
      ..sort();

    if (periodDays.isEmpty) {
      return const CycleStats(periodLengths: [], cycleLengths: []);
    }

    final episodes = <List<DateTime>>[];
    var current = <DateTime>[periodDays.first];
    for (var i = 1; i < periodDays.length; i++) {
      final prev = periodDays[i - 1];
      final day = periodDays[i];
      if (day.difference(prev).inDays <= 1) {
        current.add(day);
      } else {
        episodes.add(current);
        current = [day];
      }
    }
    episodes.add(current);

    final periodLengths = episodes.map((ep) => ep.length).toList();
    final starts = episodes.map((ep) => ep.first).toList();
    final cycleLengths = <int>[
      for (var i = 1; i < starts.length; i++) starts[i].difference(starts[i - 1]).inDays,
    ];

    double? avg(List<int> xs) => xs.isEmpty ? null : xs.reduce((a, b) => a + b) / xs.length;

    return CycleStats(
      periodLengths: periodLengths,
      cycleLengths: cycleLengths,
      avgPeriodLength: avg(periodLengths),
      avgCycleLength: avg(cycleLengths),
    );
  }
}
