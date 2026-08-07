import 'package:flutter/material.dart';

import '../data/models/custom_metric.dart';

/// The two fixed "slot" colors used everywhere on the Metric Comparison
/// screen — whichever metric is picked first always reads in
/// [comparisonSlotAColor], whichever is picked second in
/// [comparisonSlotBColor], across all three plots and the one shared legend
/// at the top of the screen (`05_SCREEN_metrics.md` "Metric Comparison"). A
/// deliberate monochrome-blue pair rather than two unrelated hues — chosen
/// for a more "techy" look on this one screen specifically; the two stay
/// tellable apart mainly by lightness (deep blue vs. bright cyan) rather
/// than hue, which matters since overlapping calendar dots depend on it.
const comparisonSlotAColor = Color(0xFF0066FF);
const comparisonSlotBColor = Color(0xFF00C2FF);

/// One pickable metric on the Metric Comparison screen
/// (`lib/screens/metrics/metric_comparison_screen.dart`) — built-ins, plus
/// two metrics derived purely for this screen from soreness logs (see
/// [ComparisonDataService] in `comparison_data_service.dart`), plus one per
/// user-defined custom metric. This is a separate type from
/// `MetricTrendOption` (Home/Metrics trend cards) rather than reusing it,
/// since it needs the two soreness-derived entries that don't otherwise
/// exist anywhere as a single-value series.
class ComparisonMetricOption {
  final String ref;
  final String label;
  final IconData icon;

  /// True only for "Soreness (by body part)" — the one non-ordinal
  /// categorical option (which of 5 body parts, no real order to it).
  /// Everything else, including "Soreness (total)" and every classes-kind
  /// custom metric (which *is* ordered, e.g. mood bad→great), is treated as
  /// a plain numeric series.
  final bool isCategorical;

  /// Fixed axis labels for a categorical option, in display order — only
  /// set when [isCategorical] is true.
  final List<String> categoryLabels;

  const ComparisonMetricOption(
    this.ref,
    this.label,
    this.icon, {
    this.isCategorical = false,
    this.categoryLabels = const [],
  });

  /// Same fixed order/labels the Training Composition chart already
  /// established for these 5 body parts (`TrainingCompositionService.
  /// bodyPartCategories`) — reused here rather than inventing a new order.
  static const bodyPartLabels = ['Legs', 'Core', 'Chest', 'Arms', 'Back'];

  static List<ComparisonMetricOption> all(List<CustomMetric> customMetrics) => [
    const ComparisonMetricOption('steps', 'Steps', Icons.directions_walk),
    const ComparisonMetricOption('sleep', 'Sleep', Icons.bed),
    const ComparisonMetricOption('weight', 'Weight', Icons.balance),
    const ComparisonMetricOption(
      'workoutDuration',
      'Workout Duration',
      Icons.timer_outlined,
    ),
    const ComparisonMetricOption(
      'soreness_part',
      'Soreness (by body part)',
      Icons.monitor_heart_outlined,
      isCategorical: true,
      categoryLabels: bodyPartLabels,
    ),
    const ComparisonMetricOption(
      'soreness_total',
      'Soreness (total)',
      Icons.local_fire_department_outlined,
    ),
    for (final m in customMetrics)
      if (m.id != null)
        ComparisonMetricOption('custom:${m.id}', m.name, Icons.insights),
  ];
}
