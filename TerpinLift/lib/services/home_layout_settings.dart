import 'package:flutter/material.dart';

/// One reorderable/removable section of the Home screen — see
/// designFiles/02_SCREEN_home.md "Home layout editing".
enum HomeWidgetId {
  muscleStatus,
  planner,
  todoList,
  weekRings,
  primedForGrowth,
  trainingSplit,
  strengthTrends,
  metricTrend,
  hiit,
}

extension HomeWidgetIdKey on HomeWidgetId {
  String get key => name;

  static HomeWidgetId? fromKey(String key) {
    for (final v in HomeWidgetId.values) {
      if (v.name == key) return v;
    }
    return null;
  }

  String get label {
    switch (this) {
      case HomeWidgetId.muscleStatus:
        return 'Muscle Status';
      case HomeWidgetId.planner:
        return 'Plan a Session';
      case HomeWidgetId.todoList:
        return 'Checklist';
      case HomeWidgetId.weekRings:
        return 'This Week';
      case HomeWidgetId.primedForGrowth:
        return 'Primed for Growth';
      case HomeWidgetId.trainingSplit:
        return 'Training Split';
      case HomeWidgetId.strengthTrends:
        return 'Strength Trend';
      case HomeWidgetId.metricTrend:
        return 'Metric Trend';
      case HomeWidgetId.hiit:
        return 'HIIT';
    }
  }

  /// Shown next to [label] in the "+" add-widget menu, one row each
  /// (`[icon] [name]`) — purely cosmetic, picked to gesture at what each
  /// section actually is rather than leaving the list all-text.
  IconData get icon {
    switch (this) {
      case HomeWidgetId.muscleStatus:
        return Icons.monitor_heart_outlined;
      case HomeWidgetId.planner:
        return Icons.event_note_outlined;
      case HomeWidgetId.todoList:
        return Icons.checklist;
      case HomeWidgetId.weekRings:
        return Icons.calendar_view_week;
      case HomeWidgetId.primedForGrowth:
        return Icons.thermostat;
      case HomeWidgetId.trainingSplit:
        return Icons.pie_chart_outline;
      case HomeWidgetId.strengthTrends:
        return Icons.fitness_center;
      case HomeWidgetId.metricTrend:
        return Icons.show_chart;
      case HomeWidgetId.hiit:
        return Icons.bolt;
    }
  }
}

/// One placed instance of a Home section. Every type appears at most once
/// **except** `strengthTrends`, `metricTrend`, and `weekRings`, which are
/// repeatable "one card per thing" widgets — `exerciseId` (strengthTrends)
/// or `metricRef` (metricTrend/weekRings) says which lift/metric a given
/// instance tracks, and both are `null` for every other (single-instance)
/// type. A `weekRings` item with `metricRef == null` means steps — the
/// original, pre-repeatable meaning, preserved so an existing saved layout
/// with a bare `weekRings` token keeps meaning exactly what it always did.
class HomeLayoutItem {
  final HomeWidgetId type;
  final int? exerciseId;
  final String? metricRef;

  /// `metricTrend` only — whether that metric's optional goal (see
  /// designFiles/05_SCREEN_metrics.md "Goals") draws as a dashed line on
  /// this specific card. Per-card, not per-metric: the same metric could
  /// appear on more than one card with the line shown on one and not the
  /// other. Meaningless (always `false`) for every other type.
  final bool showGoal;

  const HomeLayoutItem(
    this.type, {
    this.exerciseId,
    this.metricRef,
    this.showGoal = false,
  });

  /// Persisted form — `<type>`, `<type>:<exerciseId>`, `<type>:<metricRef>`,
  /// or `<type>:<metricRef>:goal`. `metricRef` itself can contain a colon
  /// (a custom metric's ref is `custom:<id>`), so only a trailing `:goal`
  /// is ever stripped/appended — never a blind colon-split.
  String get token {
    if (exerciseId != null) return '${type.key}:$exerciseId';
    if (metricRef != null) {
      final base = '${type.key}:$metricRef';
      return showGoal ? '$base:goal' : base;
    }
    return type.key;
  }

  static HomeLayoutItem? fromToken(String raw) {
    final i = raw.indexOf(':');
    final typeKey = i == -1 ? raw : raw.substring(0, i);
    var rest = i == -1 ? null : raw.substring(i + 1);
    final type = HomeWidgetIdKey.fromKey(typeKey);
    if (type == null) return null;
    if (type == HomeWidgetId.strengthTrends) {
      return HomeLayoutItem(
        type,
        exerciseId: rest == null ? null : int.tryParse(rest),
      );
    }
    if (type == HomeWidgetId.metricTrend || type == HomeWidgetId.weekRings) {
      var showGoal = false;
      if (rest != null && rest.endsWith(':goal')) {
        showGoal = true;
        rest = rest.substring(0, rest.length - ':goal'.length);
      }
      return HomeLayoutItem(type, metricRef: rest, showGoal: showGoal);
    }
    return HomeLayoutItem(type);
  }

  @override
  bool operator ==(Object other) =>
      other is HomeLayoutItem &&
      other.type == type &&
      other.exerciseId == exerciseId &&
      other.metricRef == metricRef &&
      other.showGoal == showGoal;

  @override
  int get hashCode => Object.hash(type, exerciseId, metricRef, showGoal);
}

/// Home screen's section order/visibility — an ordered list of the
/// currently-shown `HomeLayoutItem`s; any single-instance type from the enum
/// not present is hidden (swiped away in edit mode, re-addable via the "+"
/// menu there). `order == null` means "not customized yet," in which case
/// Home falls back to every section in its original default order, with one
/// `strengthTrends` entry per zero-state active lift.
abstract class HomeLayoutSettings {
  static List<HomeLayoutItem>? order;
}
