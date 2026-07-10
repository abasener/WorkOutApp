import 'exercise.dart';

enum MetricType {
  steps,
  sleepHours,
  sorenessCore,
  sorenessBack,
  sorenessArms,
  sorenessLegs,
  sorenessChest,
}

extension MetricTypeKey on MetricType {
  String get key {
    switch (this) {
      case MetricType.steps:
        return 'steps';
      case MetricType.sleepHours:
        return 'sleep_hours';
      case MetricType.sorenessCore:
        return 'soreness_core';
      case MetricType.sorenessBack:
        return 'soreness_back';
      case MetricType.sorenessArms:
        return 'soreness_arms';
      case MetricType.sorenessLegs:
        return 'soreness_legs';
      case MetricType.sorenessChest:
        return 'soreness_chest';
    }
  }

  String get label {
    switch (this) {
      case MetricType.steps:
        return 'Steps';
      case MetricType.sleepHours:
        return 'Sleep';
      case MetricType.sorenessCore:
        return 'Core Soreness';
      case MetricType.sorenessBack:
        return 'Back Soreness';
      case MetricType.sorenessArms:
        return 'Arms Soreness';
      case MetricType.sorenessLegs:
        return 'Legs Soreness';
      case MetricType.sorenessChest:
        return 'Chest Soreness';
    }
  }

  bool get isSoreness => sorenessCategory != null;

  /// The body-part category this soreness metric tracks, or null for
  /// non-soreness metrics (steps, sleep).
  ExerciseCategory? get sorenessCategory {
    switch (this) {
      case MetricType.sorenessCore:
        return ExerciseCategory.core;
      case MetricType.sorenessBack:
        return ExerciseCategory.back;
      case MetricType.sorenessArms:
        return ExerciseCategory.arms;
      case MetricType.sorenessLegs:
        return ExerciseCategory.legs;
      case MetricType.sorenessChest:
        return ExerciseCategory.chest;
      case MetricType.steps:
      case MetricType.sleepHours:
        return null;
    }
  }

  static MetricType fromKey(String key) =>
      MetricType.values.firstWhere((t) => t.key == key);

  static MetricType forSorenessCategory(ExerciseCategory category) {
    switch (category) {
      case ExerciseCategory.core:
        return MetricType.sorenessCore;
      case ExerciseCategory.back:
        return MetricType.sorenessBack;
      case ExerciseCategory.arms:
        return MetricType.sorenessArms;
      case ExerciseCategory.legs:
        return MetricType.sorenessLegs;
      case ExerciseCategory.chest:
        return MetricType.sorenessChest;
      case ExerciseCategory.push:
      case ExerciseCategory.pull:
        throw ArgumentError('push/pull are not soreness-tracked body parts');
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

  const MetricEntry({
    this.id,
    required this.date,
    required this.metricType,
    required this.value,
    this.loggedAt,
    this.notes,
  });

  factory MetricEntry.fromMap(Map<String, dynamic> m) => MetricEntry(
        id: m['id'] as int?,
        date: m['date'] as String,
        metricType: MetricTypeKey.fromKey(m['metric_type'] as String),
        value: (m['value'] as num).toDouble(),
        loggedAt: m['logged_at'] as String?,
        notes: m['notes'] as String?,
      );

  Map<String, dynamic> toMap() => {
        'date': date,
        'metric_type': metricType.key,
        'value': value,
        'logged_at': loggedAt,
        'notes': notes,
      };
}
