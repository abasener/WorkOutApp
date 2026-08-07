/// How a [CustomMetric]'s entries are captured and displayed — the "metric
/// builder"'s 3 input shapes, chosen once when the metric is created.
enum CustomMetricKind { number, scale, classes }

extension CustomMetricKindKey on CustomMetricKind {
  String get key => name;
  static CustomMetricKind fromKey(String key) =>
      CustomMetricKind.values.firstWhere((k) => k.name == key);
}

/// Which icon renders a [CustomMetricKind.scale] metric's 0-[CustomMetric.
/// scaleMax] level — same idea as the muscle-soreness flame picker, just a
/// user-chosen icon instead of always a flame. Deliberately multi-use
/// (heart for heart rate *or* general mood/how-good-it-felt, bolt for
/// energy, moon for sleep quality, drop for hydration) rather than one icon
/// per specific tracked thing — thumbs-up was considered and dropped, it
/// didn't read clearly at this icon size/style.
enum ScaleIcon { flame, star, dot, heart, bolt, moon, drop }

extension ScaleIconKey on ScaleIcon {
  String get key => name;
  static ScaleIcon fromKey(String key) =>
      ScaleIcon.values.firstWhere((i) => i.name == key);
}

/// A user-defined metric (the "metric builder", designFiles/05_SCREEN_
/// metrics.md) — no limit on how many an install can have. [kind] decides
/// which of [scaleMax]/[scaleIcon]/[classLabels] are actually used:
/// - [CustomMetricKind.number]: none of them — entries are a plain value.
/// - [CustomMetricKind.scale]: [scaleMax] (the top of a 0-max level) and
///   [scaleIcon] (which icon draws it).
/// - [CustomMetricKind.classes]: [classLabels], an ordered list (e.g. "Sad"
///   .."Great") — entries store the chosen label's index into this list.
class CustomMetric {
  final int? id;
  final String name;
  final CustomMetricKind kind;
  final int? scaleMax;
  final ScaleIcon? scaleIcon;
  final List<String> classLabels;
  final String created;

  /// Whether a second entry on a date it's already been logged adds a new
  /// row (soreness-style — some things genuinely happen more than once a
  /// day) or replaces the existing one (most simple daily trackers — mood,
  /// a temperature reading, anything you only mean to log once). Defaults
  /// to `false` (once-per-day, replace) since that matches most custom
  /// metrics better and avoids silently piling up accidental duplicate
  /// entries; a metric that genuinely wants multiples (e.g. mid-day energy
  /// checks) opts in explicitly when it's built.
  final bool allowMultiplePerDay;

  /// Optional target value, `kind == number` only (see designFiles/
  /// 05_SCREEN_metrics.md "Goals" — a `scale` metric is already bounded
  /// 0-`scaleMax` with its own gauge, and `classes` has no numeric meaning).
  /// Drives that metric's dashed trend-chart goal line and lets it be
  /// picked for a "This Week" ring row, same as the weight/sleep goals in
  /// Settings. `null` = no goal set.
  final double? goal;

  /// Masks this metric's logged values wherever they're displayed (history
  /// rows, trend-chart axis labels) the same way `Units.hideWeight` masks
  /// bodyweight — a "---" placeholder in place of the real number, trend
  /// *shape* still fully visible. For a metric that can be sensitive to see
  /// as a plain number (e.g. calories, for someone with a history of
  /// disordered eating) without needing to stop tracking it entirely.
  /// Doesn't touch entry/edit forms — the real value still shows while
  /// logging or correcting one, only passive display is masked. Off by
  /// default.
  final bool hideValue;

  const CustomMetric({
    this.id,
    required this.name,
    required this.kind,
    this.scaleMax,
    this.scaleIcon,
    this.classLabels = const [],
    required this.created,
    this.allowMultiplePerDay = false,
    this.goal,
    this.hideValue = false,
  });

  CustomMetric copyWith({bool? hideValue}) => CustomMetric(
    id: id,
    name: name,
    kind: kind,
    scaleMax: scaleMax,
    scaleIcon: scaleIcon,
    classLabels: classLabels,
    created: created,
    allowMultiplePerDay: allowMultiplePerDay,
    goal: goal,
    hideValue: hideValue ?? this.hideValue,
  );

  factory CustomMetric.fromMap(Map<String, dynamic> m) => CustomMetric(
    id: m['id'] as int?,
    name: m['name'] as String,
    kind: CustomMetricKindKey.fromKey(m['kind'] as String),
    scaleMax: m['scale_max'] as int?,
    scaleIcon: m['scale_icon'] == null
        ? null
        : ScaleIconKey.fromKey(m['scale_icon'] as String),
    classLabels: ((m['class_labels'] as String?) ?? '')
        .split(',')
        .where((s) => s.isNotEmpty)
        .toList(),
    created: m['created'] as String,
    allowMultiplePerDay: (m['allow_multiple_per_day'] as int?) == 1,
    goal: (m['goal'] as num?)?.toDouble(),
    hideValue: (m['hide_value'] as int?) == 1,
  );

  Map<String, dynamic> toMap() => {
    'name': name,
    'kind': kind.key,
    'scale_max': scaleMax,
    'scale_icon': scaleIcon?.key,
    'class_labels': classLabels.join(','),
    'created': created,
    'allow_multiple_per_day': allowMultiplePerDay ? 1 : 0,
    'goal': goal,
    'hide_value': hideValue ? 1 : 0,
  };

  /// A logged [value] as plain text, in whichever shape [kind] calls for —
  /// shared by the trend-chart y-axis, the entry-log/history sheet, and
  /// anywhere else a raw stored number needs to read back as what the user
  /// actually picked.
  String formatValue(double value) {
    switch (kind) {
      case CustomMetricKind.number:
        return value == value.roundToDouble()
            ? value.round().toString()
            : value.toStringAsFixed(1);
      case CustomMetricKind.scale:
        return '${value.round()}/${scaleMax ?? 5}';
      case CustomMetricKind.classes:
        if (classLabels.isEmpty) return '';
        final i = value.round().clamp(0, classLabels.length - 1);
        return classLabels[i];
    }
  }

  /// [formatValue], but masked to `'---'` when [hideValue] is on — use this
  /// at passive-display sites (history rows, chart axis labels); entry/edit
  /// forms should keep using [formatValue] directly so editing still shows
  /// the real value.
  String formatMaskedValue(double value) =>
      hideValue ? '---' : formatValue(value);
}
