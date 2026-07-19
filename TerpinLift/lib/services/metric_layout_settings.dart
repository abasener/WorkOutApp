import 'package:flutter/material.dart';

/// One reorderable/hideable card on the Metrics screen's Overview tab —
/// same "edit mode" idea as `HomeLayoutSettings`, applied here after the
/// user asked for parity between the two screens.
enum MetricWidgetId {
  steps,
  sleep,
  workoutDuration,
  soreness,
  weight,
  cycle,
  progressPhotos,
  customMetric,
}

extension MetricWidgetIdKey on MetricWidgetId {
  String get key => name;

  static MetricWidgetId? fromKey(String key) {
    for (final v in MetricWidgetId.values) {
      if (v.name == key) return v;
    }
    return null;
  }

  String get label {
    switch (this) {
      case MetricWidgetId.steps:
        return 'Steps';
      case MetricWidgetId.sleep:
        return 'Sleep';
      case MetricWidgetId.workoutDuration:
        return 'Workout Duration';
      case MetricWidgetId.soreness:
        return 'Soreness';
      case MetricWidgetId.weight:
        return 'Weight';
      case MetricWidgetId.cycle:
        return 'Cycle';
      case MetricWidgetId.progressPhotos:
        return 'Progress Photos';
      case MetricWidgetId.customMetric:
        return 'Custom metric';
    }
  }

  IconData get icon {
    switch (this) {
      case MetricWidgetId.steps:
        return Icons.directions_walk;
      case MetricWidgetId.sleep:
        return Icons.bedtime_outlined;
      case MetricWidgetId.workoutDuration:
        return Icons.timer_outlined;
      case MetricWidgetId.soreness:
        return Icons.monitor_heart_outlined;
      case MetricWidgetId.weight:
        return Icons.monitor_weight_outlined;
      case MetricWidgetId.cycle:
        return Icons.calendar_today_outlined;
      case MetricWidgetId.progressPhotos:
        return Icons.camera_alt_outlined;
      case MetricWidgetId.customMetric:
        return Icons.show_chart;
    }
  }
}

/// One placed card. Every type appears at most once **except**
/// `customMetric`, which is repeatable — one instance per user-defined
/// metric, `customMetricId` says which.
class MetricLayoutItem {
  final MetricWidgetId type;
  final int? customMetricId;

  const MetricLayoutItem(this.type, {this.customMetricId});

  String get token =>
      customMetricId != null ? '${type.key}:$customMetricId' : type.key;

  static MetricLayoutItem? fromToken(String raw) {
    final i = raw.indexOf(':');
    final typeKey = i == -1 ? raw : raw.substring(0, i);
    final rest = i == -1 ? null : raw.substring(i + 1);
    final type = MetricWidgetIdKey.fromKey(typeKey);
    if (type == null) return null;
    if (type == MetricWidgetId.customMetric) {
      return MetricLayoutItem(
        type,
        customMetricId: rest == null ? null : int.tryParse(rest),
      );
    }
    return MetricLayoutItem(type);
  }

  @override
  bool operator ==(Object other) =>
      other is MetricLayoutItem &&
      other.type == type &&
      other.customMetricId == customMetricId;

  @override
  int get hashCode => Object.hash(type, customMetricId);
}

/// Overview tab's card order/visibility — `null` means "not customized yet,"
/// falling back to every built-in card in its original order plus one entry
/// per existing custom metric. Hiding a card here never deletes its
/// underlying data (logged entries, or a custom metric definition) — it's
/// just left out of this order, same convention `HomeLayoutSettings` uses.
abstract class MetricLayoutSettings {
  static List<MetricLayoutItem>? order;
}
