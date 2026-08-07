import '../data/models/exercise.dart';
import '../data/models/metric_entry.dart';
import 'app_services.dart';
import 'muscle_map.dart';
import 'trend_engine.dart';

/// One raw logged value for a comparison metric — deliberately unaggregated;
/// [fetch] returns every entry as logged, and each of the 3 comparison
/// plots aggregates it differently (see [sumPerDay]/[scatterPairs]) rather
/// than this service picking one aggregation for everyone up front.
class ComparisonEntry {
  final DateTime date;
  final double value;
  const ComparisonEntry(this.date, this.value);
}

/// Fetches and derives per-day data for the Metric Comparison screen
/// (`lib/screens/metrics/metric_comparison_screen.dart`). Pure read/derive —
/// no new schema, no persistence of its own; the two soreness-derived refs
/// ("soreness_part"/"soreness_total") are computed fresh every call from the
/// same `metrics_log` rows the regular soreness feature already writes.
abstract class ComparisonDataService {
  /// Same fixed order the Training Composition chart already uses for these
  /// 5 body parts (`TrainingCompositionService.bodyPartCategories`) — reused
  /// here so "soreness_part"'s category index lines up with
  /// `ComparisonMetricOption.bodyPartLabels`.
  static const bodyPartOrder = [
    ExerciseCategory.legs,
    ExerciseCategory.core,
    ExerciseCategory.chest,
    ExerciseCategory.arms,
    ExerciseCategory.back,
  ];

  static Future<List<ComparisonEntry>> fetch(
    String ref,
    DateTime cutoff,
  ) async {
    if (ref == 'steps') return _fromMetricType(MetricType.steps, cutoff);
    if (ref == 'sleep') return _fromMetricType(MetricType.sleepHours, cutoff);
    if (ref == 'weight') return _fromBodyweight(cutoff);
    if (ref == 'workoutDuration') return _fromWorkoutDuration(cutoff);
    if (ref == 'soreness_part') return _sorenessByPart(cutoff);
    if (ref == 'soreness_total') return _sorenessTotal(cutoff);
    if (ref.startsWith('custom:')) {
      final id = int.tryParse(ref.substring('custom:'.length));
      if (id != null) return _fromCustomMetric(id, cutoff);
    }
    return const [];
  }

  static Future<List<ComparisonEntry>> _fromMetricType(
    MetricType type,
    DateTime cutoff,
  ) async {
    final rows = await AppServices.metrics.getByType(type);
    return [
      for (final e in rows)
        if (DateTime.parse(e.date).isAfter(cutoff))
          ComparisonEntry(DateTime.parse(e.date), e.value),
    ];
  }

  /// Raw per-log-day weight — a deliberate, disclosed exception to
  /// `00_UX_DESIGN.md`'s "never a raw daily reading" bodyweight rule,
  /// specifically for this screen's scatter plot and calendar (see
  /// [weeklyAverage], applied only to the line chart's trend instead). The
  /// whole point of comparing weight against another day-to-day metric
  /// (e.g. "a heavy-calorie Tuesday preceded a jump on the scale") is lost
  /// if same-week readings get smoothed into one average before the
  /// comparison ever happens — the user's own explicit 2026-07-27 call.
  static Future<List<ComparisonEntry>> _fromBodyweight(DateTime cutoff) async {
    final rows = await AppServices.bodyweight.getAll();
    return [
      for (final e in rows)
        if (DateTime.parse(e.date).isAfter(cutoff))
          ComparisonEntry(DateTime.parse(e.date), e.weight),
    ];
  }

  static Future<List<ComparisonEntry>> _fromWorkoutDuration(
    DateTime cutoff,
  ) async {
    final sessions = await AppServices.lifts.getAllSessions();
    final plannedSessions = await AppServices.workoutPlans.getAllSessions();
    final byDate = TrendEngine.workoutDurationMinutesByDate(
      sessions,
      plannedSessions: plannedSessions,
    );
    return [
      for (final e in byDate.entries)
        if (DateTime.parse(e.key).isAfter(cutoff))
          ComparisonEntry(DateTime.parse(e.key), e.value),
    ];
  }

  static Future<List<ComparisonEntry>> _fromCustomMetric(
    int id,
    DateTime cutoff,
  ) async {
    final rows = await AppServices.customMetrics.getEntries(id);
    return [
      for (final e in rows)
        if (DateTime.parse(e.date).isAfter(cutoff))
          ComparisonEntry(DateTime.parse(e.date), e.value),
    ];
  }

  /// Every logged soreness entry (any of the 14 fine `SorenessRegion`
  /// types), still individual — no per-day merge here, since this feeds a
  /// non-ordinal categorical axis where a day with two different sore body
  /// parts is genuinely two separate points, not one value to average or
  /// sum (see `05_SCREEN_metrics.md` "Metric Comparison").
  static Future<List<ComparisonEntry>> _sorenessByPart(DateTime cutoff) async {
    final entries = <ComparisonEntry>[];
    for (final region in SorenessRegion.values) {
      final categoryIndex = _bodyPartIndexFor(region);
      if (categoryIndex == null) continue;
      final rows = await AppServices.metrics.getByType(
        MetricTypeKey.forSorenessRegion(region),
      );
      for (final e in rows) {
        final date = DateTime.parse(e.date);
        if (date.isAfter(cutoff)) {
          entries.add(ComparisonEntry(date, categoryIndex.toDouble()));
        }
      }
    }
    return entries;
  }

  /// Every region's level, summed per day (e.g. legs 3 + core 2 = 5) — a
  /// real number, so unlike "by body part" this already *is* one value per
  /// day by definition, not a choice made downstream by whichever plot is
  /// drawing it.
  static Future<List<ComparisonEntry>> _sorenessTotal(DateTime cutoff) async {
    final sumByDate = <String, double>{};
    for (final region in SorenessRegion.values) {
      final rows = await AppServices.metrics.getByType(
        MetricTypeKey.forSorenessRegion(region),
      );
      for (final e in rows) {
        if (!DateTime.parse(e.date).isAfter(cutoff)) continue;
        sumByDate[e.date] = (sumByDate[e.date] ?? 0) + e.value;
      }
    }
    return [
      for (final entry in sumByDate.entries)
        ComparisonEntry(DateTime.parse(entry.key), entry.value),
    ];
  }

  static int? _bodyPartIndexFor(SorenessRegion region) {
    final muscle = MuscleMap.sorenessRegionGroups[region]?.first;
    if (muscle == null) return null;
    final category = MuscleMap.categoryForMuscle(muscle);
    if (category == null) return null;
    final index = bodyPartOrder.indexOf(category);
    return index == -1 ? null : index;
  }

  /// What the line chart and calendar should plot for one series: every
  /// other metric collapses same-day entries into one summed value
  /// ([sumPerDay]), but a non-ordinal categorical series (e.g. "Soreness (by
  /// body part)") stores a *category index* per entry, not a magnitude —
  /// summing two indices together (legs=0 + chest=2 = 2, colliding with
  /// chest's own index) is meaningless. For those, every raw entry stays its
  /// own point: a day with both legs and chest sore genuinely is two points
  /// at that date, not one. This is deliberately unconventional for a line
  /// chart (multiple points at the same x, connected in sequence) but is
  /// what the category data actually calls for. The calendar always uses
  /// this result as-is; the line chart applies one further step for weight
  /// specifically — see [weeklyAverage].
  static List<ComparisonEntry> aggregateForCharts(
    List<ComparisonEntry> raw,
    bool isCategorical,
  ) {
    if (isCategorical) {
      return [...raw]..sort((a, b) => a.date.compareTo(b.date));
    }
    return sumPerDay(raw);
  }

  /// Averages an already-aggregated series into one point per calendar
  /// week — applied only to the line chart's "weight" series (never the
  /// scatter plot or calendar, which keep raw daily weight, see
  /// [_fromBodyweight]), so the trend still reads as a smoothed long-term
  /// shape rather than every individual logged number, matching every other
  /// bodyweight chart in the app (`00_UX_DESIGN.md`).
  static List<ComparisonEntry> weeklyAverage(List<ComparisonEntry> series) {
    final byWeek = <DateTime, List<double>>{};
    for (final e in series) {
      final weekStart = e.date.subtract(Duration(days: e.date.weekday - 1));
      final key = DateTime(weekStart.year, weekStart.month, weekStart.day);
      byWeek.putIfAbsent(key, () => []).add(e.value);
    }
    final result = [
      for (final entry in byWeek.entries)
        ComparisonEntry(
          entry.key,
          entry.value.reduce((a, b) => a + b) / entry.value.length,
        ),
    ]..sort((a, b) => a.date.compareTo(b.date));
    return result;
  }

  /// Collapses same-day entries into one value per day, summed — used by
  /// the line chart and calendar (never the scatter plot, which keeps every
  /// raw entry as its own point). Matches the user's own stated lean for a
  /// metric logged more than once a day ("maybe just sum them ... average
  /// seems less useful for something like time worked out"). Not meaningful
  /// for a non-ordinal categorical series — see [aggregateForCharts].
  static List<ComparisonEntry> sumPerDay(List<ComparisonEntry> raw) {
    final byDate = <String, (DateTime, double)>{};
    for (final e in raw) {
      final key = _dateKey(e.date);
      final existing = byDate[key];
      byDate[key] = (e.date, (existing?.$2 ?? 0) + e.value);
    }
    final result = [
      for (final entry in byDate.values) ComparisonEntry(entry.$1, entry.$2),
    ]..sort((a, b) => a.date.compareTo(b.date));
    return result;
  }

  /// Every (valueA, valueB) pair for a date both metrics have data on — a
  /// day with multiple entries on either side produces one pair per
  /// combination (e.g. 2 mood logs + 1 sleep log on the same day makes 2
  /// scatter points, sleep's value repeated for each), never merged into a
  /// single point. This is the literal per-entry behavior the user asked
  /// for specifically for the scatter plot.
  static List<(double, double)> scatterPairs(
    List<ComparisonEntry> a,
    List<ComparisonEntry> b,
  ) {
    final byDateA = <String, List<double>>{};
    for (final e in a) {
      byDateA.putIfAbsent(_dateKey(e.date), () => []).add(e.value);
    }
    final byDateB = <String, List<double>>{};
    for (final e in b) {
      byDateB.putIfAbsent(_dateKey(e.date), () => []).add(e.value);
    }
    final pairs = <(double, double)>[];
    for (final entry in byDateA.entries) {
      final bValues = byDateB[entry.key];
      if (bValues == null) continue;
      for (final av in entry.value) {
        for (final bv in bValues) {
          pairs.add((av, bv));
        }
      }
    }
    return pairs;
  }

  static String _dateKey(DateTime d) => d.toIso8601String().substring(0, 10);
}
