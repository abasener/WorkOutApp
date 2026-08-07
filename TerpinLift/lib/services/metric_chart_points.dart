import '../data/models/bodyweight_entry.dart';
import '../data/models/custom_metric.dart';
import '../data/models/custom_metric_entry.dart';
import '../data/models/metric_entry.dart';
import '../widgets/labeled_trend_chart.dart';

/// Shared point/formatter computation for metric trend charts — used by
/// both the Metrics screen's Overview tab and Home's Metric Trend cards, so
/// the two never end up computing "the same chart" two different ways.
abstract class MetricChartPoints {
  static List<ChartPoint> forEntries(
    List<MetricEntry> entries,
    DateTime cutoff,
  ) {
    return entries
        .where((e) => DateTime.parse(e.date).isAfter(cutoff))
        .map((e) => ChartPoint(DateTime.parse(e.date), e.value))
        .toList();
  }

  /// One point per date with any timed lift session — derived from
  /// `lift_sessions.started_at`/`completed_at`, not a manually-logged metric.
  static List<ChartPoint> workoutDuration(
    Map<String, double> byDate,
    DateTime cutoff,
  ) {
    return byDate.entries
        .where((e) => DateTime.parse(e.key).isAfter(cutoff))
        .map((e) => ChartPoint(DateTime.parse(e.key), e.value))
        .toList()
      ..sort((a, b) => a.date.compareTo(b.date));
  }

  /// One dot per week (average of that week's entries) so no single raw
  /// bodyweight reading is ever directly exposed — see designFiles/00_UX_DESIGN.md.
  static List<ChartPoint> weeklyBodyweight(
    List<BodyweightEntry> entries,
    DateTime cutoff,
  ) {
    final byWeek = <DateTime, List<double>>{};
    for (final e in entries) {
      final date = DateTime.parse(e.date);
      if (!date.isAfter(cutoff)) continue;
      final weekStart = date.subtract(Duration(days: date.weekday - 1));
      final key = DateTime(weekStart.year, weekStart.month, weekStart.day);
      byWeek.putIfAbsent(key, () => []).add(e.weight);
    }
    final points =
        byWeek.entries
            .map(
              (e) => ChartPoint(
                e.key,
                e.value.reduce((a, b) => a + b) / e.value.length,
              ),
            )
            .toList()
          ..sort((a, b) => a.date.compareTo(b.date));
    return points;
  }

  static List<ChartPoint> customMetric(
    List<CustomMetricEntry> entries,
    DateTime cutoff,
  ) {
    return entries
        .where((e) => DateTime.parse(e.date).isAfter(cutoff))
        .map((e) => ChartPoint(DateTime.parse(e.date), e.value))
        .toList();
  }

  /// Raw daily entries, one point per logged date — the opt-in exception to
  /// [weeklyBodyweight]'s usual smoothing (designFiles/00_UX_DESIGN.md,
  /// disclosed 2026-07-27 as a deliberate per-card override, not a change
  /// to the default).
  static List<ChartPoint> dailyBodyweight(
    List<BodyweightEntry> entries,
    DateTime cutoff,
  ) {
    return entries
        .where((e) => DateTime.parse(e.date).isAfter(cutoff))
        .map((e) => ChartPoint(DateTime.parse(e.date), e.weight))
        .toList()
      ..sort((a, b) => a.date.compareTo(b.date));
  }

  static String Function(double)? customYFormatter(CustomMetric metric) {
    // Masked first, regardless of kind — trend *shape* stays fully visible
    // (real values still drive point positions), only the printed axis
    // number is hidden. Same convention as `Units.formatMaskable`.
    if (metric.hideValue) return (_) => '---';
    if (metric.kind != CustomMetricKind.classes) return null;
    return (v) {
      final i = v.round().clamp(0, metric.classLabels.length - 1);
      return metric.classLabels.isEmpty ? '' : metric.classLabels[i];
    };
  }
}
