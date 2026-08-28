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

  /// Whether this card type is windowed by a time frame at all (steps/
  /// sleep/weight/workoutDuration/customMetric all plot a `LabeledTrendChart`
  /// against some history window; soreness/cycle/progressPhotos don't) —
  /// decides whether the settings gear even has a time-frame row to show.
  bool get hasTimeFrame =>
      this != MetricWidgetId.soreness &&
      this != MetricWidgetId.cycle &&
      this != MetricWidgetId.progressPhotos;

  /// Whether this card type has a prediction-extension concept at all
  /// (designFiles/00_UX_DESIGN.md: real data stops early and the remaining
  /// chart width is reserved for the trend continuation) — only steps and
  /// weight currently do. Decides whether the settings gear even has a
  /// "Show predictions" row to show.
  bool get hasPrediction =>
      this == MetricWidgetId.steps || this == MetricWidgetId.weight;
}

/// One placed card. Every type appears at most once **except**
/// `customMetric`, which is repeatable — one instance per user-defined
/// metric, `customMetricId` says which.
class MetricLayoutItem {
  final MetricWidgetId type;
  final int? customMetricId;

  /// Whether this card is hidden — no longer removes it from the order the
  /// way an absent entry used to; it stays in place (still reorderable) and
  /// renders dimmed in edit mode, full-strength when shown. Replaces the
  /// old "hide = remove from order, show = pick from a separate popup"
  /// scheme entirely (2026-07-25) — the only way to add a genuinely new
  /// card now is a new custom metric (or, on Home, a new trend/ring card).
  final bool hidden;

  /// This card's own "how far back" window, in months — `null` means
  /// "Default," which tracks `HomeTrendSettings.months` live rather than
  /// copying its value once, so a card left on Default keeps following the
  /// shared setting even if it changes later. Only meaningful for a type
  /// where `hasTimeFrame` is true.
  final int? monthsOverride;

  /// Whether this card's optional goal (designFiles/05_SCREEN_metrics.md
  /// "Goals") draws as a dashed line on its chart — same per-card idea as
  /// `HomeLayoutItem.showGoal`. Meaningless if the underlying metric has no
  /// goal value set.
  final bool showGoal;

  /// Weight-only: shows raw daily log entries instead of the default
  /// weekly average — a deliberate, disclosed opt-in exception to
  /// designFiles/00_UX_DESIGN.md's usual "never a raw daily reading"
  /// bodyweight rule (2026-07-27, user's own explicit request). Meaningless
  /// for every other type.
  final bool dailyView;

  /// Whether this card's chart reserves its usual trailing chunk for the
  /// prediction extension (see [MetricWidgetIdKey.hasPrediction]). Defaults
  /// on to preserve the existing steps/weight behavior; turning it off
  /// makes real data fill the chart's full width instead, the same as a
  /// card with no prediction concept (e.g. sleep) already renders.
  /// Meaningless for a type where `hasPrediction` is false.
  final bool showPrediction;

  const MetricLayoutItem(
    this.type, {
    this.customMetricId,
    this.hidden = false,
    this.monthsOverride,
    this.showGoal = false,
    this.dailyView = false,
    this.showPrediction = true,
  });

  /// Identity independent of the mutable flags below — use this (not
  /// `token`) for a `ReorderableListView`'s `ValueKey`. `token` now changes
  /// whenever hidden/monthsOverride/showGoal is toggled, which would
  /// otherwise make the list treat an in-place settings change as a
  /// completely different item mid-interaction.
  String get stableKey =>
      customMetricId != null ? '${type.key}:$customMetricId' : type.key;

  /// Persisted form — base `<type>` or `<type>:<customMetricId>`, plus any
  /// of `;hidden=1` / `;months=<n>` / `;goal=1` / `;predict=0` appended (any
  /// combination, any order not required since each is parsed
  /// independently) only when that flag differs from its default, so an
  /// untouched card's token stays exactly what it always was.
  String get token {
    final base = customMetricId != null
        ? '${type.key}:$customMetricId'
        : type.key;
    final flags = [
      if (hidden) 'hidden=1',
      if (monthsOverride != null) 'months=$monthsOverride',
      if (showGoal) 'goal=1',
      if (dailyView) 'daily=1',
      if (!showPrediction) 'predict=0',
    ];
    return flags.isEmpty ? base : '$base;${flags.join(';')}';
  }

  static MetricLayoutItem? fromToken(String raw) {
    final parts = raw.split(';');
    final base = parts.first;
    final i = base.indexOf(':');
    final typeKey = i == -1 ? base : base.substring(0, i);
    final rest = i == -1 ? null : base.substring(i + 1);
    final type = MetricWidgetIdKey.fromKey(typeKey);
    if (type == null) return null;

    var hidden = false;
    int? monthsOverride;
    var showGoal = false;
    var dailyView = false;
    var showPrediction = true;
    for (final flag in parts.skip(1)) {
      if (flag == 'hidden=1') hidden = true;
      if (flag == 'goal=1') showGoal = true;
      if (flag == 'daily=1') dailyView = true;
      if (flag == 'predict=0') showPrediction = false;
      if (flag.startsWith('months=')) {
        monthsOverride = int.tryParse(flag.substring('months='.length));
      }
    }

    return MetricLayoutItem(
      type,
      customMetricId: type == MetricWidgetId.customMetric && rest != null
          ? int.tryParse(rest)
          : null,
      hidden: hidden,
      monthsOverride: monthsOverride,
      showGoal: showGoal,
      dailyView: dailyView,
      showPrediction: showPrediction,
    );
  }

  /// `monthsOverride` needs a tri-state update (leave alone / set to a
  /// value / clear back to Default), which a plain `newValue ?? oldValue`
  /// copyWith can't express — wrap the new value in a function so "clear
  /// it" can be `() => null` and "leave alone" can stay the default `null`
  /// argument, distinguishing the two.
  MetricLayoutItem copyWith({
    bool? hidden,
    int? Function()? monthsOverride,
    bool? showGoal,
    bool? dailyView,
    bool? showPrediction,
  }) => MetricLayoutItem(
    type,
    customMetricId: customMetricId,
    hidden: hidden ?? this.hidden,
    monthsOverride: monthsOverride != null
        ? monthsOverride()
        : this.monthsOverride,
    showGoal: showGoal ?? this.showGoal,
    dailyView: dailyView ?? this.dailyView,
    showPrediction: showPrediction ?? this.showPrediction,
  );

  @override
  bool operator ==(Object other) =>
      other is MetricLayoutItem &&
      other.type == type &&
      other.customMetricId == customMetricId &&
      other.hidden == hidden &&
      other.monthsOverride == monthsOverride &&
      other.showGoal == showGoal &&
      other.dailyView == dailyView &&
      other.showPrediction == showPrediction;

  @override
  int get hashCode => Object.hash(
    type,
    customMetricId,
    hidden,
    monthsOverride,
    showGoal,
    dailyView,
    showPrediction,
  );
}

/// Overview tab's card order/visibility — `null` means "not customized yet,"
/// falling back to every built-in card in its original order plus one entry
/// per existing custom metric. Hiding a card here never deletes its
/// underlying data (logged entries, or a custom metric definition) — it's
/// just flagged hidden, same convention `HomeLayoutSettings` uses for
/// deletion-safety, now via `MetricLayoutItem.hidden` rather than absence.
abstract class MetricLayoutSettings {
  static List<MetricLayoutItem>? order;
}
