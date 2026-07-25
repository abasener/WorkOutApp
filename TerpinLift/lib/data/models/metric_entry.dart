/// Soreness sub-regions — finer than the 5 broad `ExerciseCategory` groups,
/// grouped by common lift-pattern differences rather than exhaustive
/// anatomy (e.g. deadlift/good-morning soreness vs. pulldown/pull-up
/// soreness are both "back" but genuinely different tissue). Chest stays a
/// single region — no common-pattern split volunteered for it. See
/// designFiles/05_SCREEN_metrics.md.
enum SorenessRegion {
  chest,
  coreCenter,
  coreSides,
  upperBack,
  lowerBack,
  biceps,
  triceps,
  shoulders,
  forearms,
  quads,
  hamstrings,
  glutes,
  calves,
  innerThigh,
}

extension SorenessRegionLabel on SorenessRegion {
  String get label {
    switch (this) {
      case SorenessRegion.chest:
        return 'Chest';
      case SorenessRegion.coreCenter:
        return 'Abs';
      case SorenessRegion.coreSides:
        return 'Obliques';
      case SorenessRegion.upperBack:
        return 'Upper Back';
      case SorenessRegion.lowerBack:
        return 'Lower Back';
      case SorenessRegion.biceps:
        return 'Biceps';
      case SorenessRegion.triceps:
        return 'Triceps';
      case SorenessRegion.shoulders:
        return 'Shoulders';
      case SorenessRegion.forearms:
        return 'Forearms';
      case SorenessRegion.quads:
        return 'Quads';
      case SorenessRegion.hamstrings:
        return 'Hamstrings';
      case SorenessRegion.glutes:
        return 'Glutes';
      case SorenessRegion.calves:
        return 'Calves';
      case SorenessRegion.innerThigh:
        return 'Inner Thigh';
    }
  }
}

/// Which half of the day a soreness entry is for — lets logging twice a day
/// (morning/evening) target a specific entry to correct rather than only
/// ever appending a new one. Only ever set on soreness entries; steps/sleep
/// never use it.
enum SorenessTimeSlot { am, pm }

extension SorenessTimeSlotKey on SorenessTimeSlot {
  String get key => this == SorenessTimeSlot.am ? 'AM' : 'PM';

  static SorenessTimeSlot? fromKey(String? key) => switch (key) {
    'AM' => SorenessTimeSlot.am,
    'PM' => SorenessTimeSlot.pm,
    _ => null,
  };
}

enum MetricType {
  steps,
  sleepHours,
  sorenessChest,
  sorenessCoreCenter,
  sorenessCoreSides,
  sorenessUpperBack,
  sorenessLowerBack,
  sorenessBiceps,
  sorenessTriceps,
  sorenessShoulders,
  sorenessForearms,
  sorenessQuads,
  sorenessHamstrings,
  sorenessGlutes,
  sorenessCalves,
  sorenessInnerThigh,
}

extension MetricTypeKey on MetricType {
  String get key {
    switch (this) {
      case MetricType.steps:
        return 'steps';
      case MetricType.sleepHours:
        return 'sleep_hours';
      case MetricType.sorenessChest:
        return 'soreness_chest';
      case MetricType.sorenessCoreCenter:
        return 'soreness_core_center';
      case MetricType.sorenessCoreSides:
        return 'soreness_core_sides';
      case MetricType.sorenessUpperBack:
        return 'soreness_upper_back';
      case MetricType.sorenessLowerBack:
        return 'soreness_lower_back';
      case MetricType.sorenessBiceps:
        return 'soreness_biceps';
      case MetricType.sorenessTriceps:
        return 'soreness_triceps';
      case MetricType.sorenessShoulders:
        return 'soreness_shoulders';
      case MetricType.sorenessForearms:
        return 'soreness_forearms';
      case MetricType.sorenessQuads:
        return 'soreness_quads';
      case MetricType.sorenessHamstrings:
        return 'soreness_hamstrings';
      case MetricType.sorenessGlutes:
        return 'soreness_glutes';
      case MetricType.sorenessCalves:
        return 'soreness_calves';
      case MetricType.sorenessInnerThigh:
        return 'soreness_inner_thigh';
    }
  }

  String get label {
    switch (this) {
      case MetricType.steps:
        return 'Steps';
      case MetricType.sleepHours:
        return 'Sleep';
      default:
        return '${sorenessRegion!.label} Soreness';
    }
  }

  bool get isSoreness => sorenessRegion != null;

  /// The soreness sub-region this metric tracks, or null for non-soreness
  /// metrics (steps, sleep).
  SorenessRegion? get sorenessRegion {
    switch (this) {
      case MetricType.sorenessChest:
        return SorenessRegion.chest;
      case MetricType.sorenessCoreCenter:
        return SorenessRegion.coreCenter;
      case MetricType.sorenessCoreSides:
        return SorenessRegion.coreSides;
      case MetricType.sorenessUpperBack:
        return SorenessRegion.upperBack;
      case MetricType.sorenessLowerBack:
        return SorenessRegion.lowerBack;
      case MetricType.sorenessBiceps:
        return SorenessRegion.biceps;
      case MetricType.sorenessTriceps:
        return SorenessRegion.triceps;
      case MetricType.sorenessShoulders:
        return SorenessRegion.shoulders;
      case MetricType.sorenessForearms:
        return SorenessRegion.forearms;
      case MetricType.sorenessQuads:
        return SorenessRegion.quads;
      case MetricType.sorenessHamstrings:
        return SorenessRegion.hamstrings;
      case MetricType.sorenessGlutes:
        return SorenessRegion.glutes;
      case MetricType.sorenessCalves:
        return SorenessRegion.calves;
      case MetricType.sorenessInnerThigh:
        return SorenessRegion.innerThigh;
      case MetricType.steps:
      case MetricType.sleepHours:
        return null;
    }
  }

  static MetricType fromKey(String key) =>
      MetricType.values.firstWhere((t) => t.key == key);

  static MetricType forSorenessRegion(SorenessRegion region) {
    switch (region) {
      case SorenessRegion.chest:
        return MetricType.sorenessChest;
      case SorenessRegion.coreCenter:
        return MetricType.sorenessCoreCenter;
      case SorenessRegion.coreSides:
        return MetricType.sorenessCoreSides;
      case SorenessRegion.upperBack:
        return MetricType.sorenessUpperBack;
      case SorenessRegion.lowerBack:
        return MetricType.sorenessLowerBack;
      case SorenessRegion.biceps:
        return MetricType.sorenessBiceps;
      case SorenessRegion.triceps:
        return MetricType.sorenessTriceps;
      case SorenessRegion.shoulders:
        return MetricType.sorenessShoulders;
      case SorenessRegion.forearms:
        return MetricType.sorenessForearms;
      case SorenessRegion.quads:
        return MetricType.sorenessQuads;
      case SorenessRegion.hamstrings:
        return MetricType.sorenessHamstrings;
      case SorenessRegion.glutes:
        return MetricType.sorenessGlutes;
      case SorenessRegion.calves:
        return MetricType.sorenessCalves;
      case SorenessRegion.innerThigh:
        return MetricType.sorenessInnerThigh;
    }
  }
}

class MetricEntry {
  final int? id;
  final String date;
  final MetricType metricType;
  final double value;

  /// Precise ISO datetime of entry — distinguishes multiple same-day entries
  /// (e.g. logging soreness more than once in a day). Nullable since older
  /// entries/other metric types may not always set it.
  final String? loggedAt;
  final String? notes;

  /// Which half of the day this entry is for — soreness only, see
  /// `SorenessTimeSlot`. Null for steps/sleep, and for any soreness entry
  /// logged before this existed.
  final SorenessTimeSlot? timeSlot;

  const MetricEntry({
    this.id,
    required this.date,
    required this.metricType,
    required this.value,
    this.loggedAt,
    this.notes,
    this.timeSlot,
  });

  factory MetricEntry.fromMap(Map<String, dynamic> m) => MetricEntry(
    id: m['id'] as int?,
    date: m['date'] as String,
    metricType: MetricTypeKey.fromKey(m['metric_type'] as String),
    value: (m['value'] as num).toDouble(),
    loggedAt: m['logged_at'] as String?,
    notes: m['notes'] as String?,
    timeSlot: SorenessTimeSlotKey.fromKey(m['time_slot'] as String?),
  );

  Map<String, dynamic> toMap() => {
    'date': date,
    'metric_type': metricType.key,
    'value': value,
    'logged_at': loggedAt,
    'notes': notes,
    'time_slot': timeSlot?.key,
  };
}
