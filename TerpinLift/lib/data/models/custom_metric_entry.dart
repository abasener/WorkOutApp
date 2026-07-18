/// One logged value for a [CustomMetric]. What [value] means depends on the
/// parent metric's `kind`: a plain number, a 0-scaleMax level, or an index
/// into `classLabels`.
class CustomMetricEntry {
  final int? id;
  final int customMetricId;
  final String date;
  final double value;
  final String loggedAt;

  const CustomMetricEntry({
    this.id,
    required this.customMetricId,
    required this.date,
    required this.value,
    required this.loggedAt,
  });

  factory CustomMetricEntry.fromMap(Map<String, dynamic> m) => CustomMetricEntry(
        id: m['id'] as int?,
        customMetricId: m['custom_metric_id'] as int,
        date: m['date'] as String,
        value: (m['value'] as num).toDouble(),
        loggedAt: m['logged_at'] as String,
      );

  Map<String, dynamic> toMap() => {
        'custom_metric_id': customMetricId,
        'date': date,
        'value': value,
        'logged_at': loggedAt,
      };
}
