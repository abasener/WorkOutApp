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
/// **except** `strengthTrends` and `metricTrend`, which are repeatable
/// "one card per thing" widgets — `exerciseId` (strengthTrends) or
/// `metricRef` (metricTrend) says which lift/metric a given instance
/// tracks, and both are `null` for every other (single-instance) type.
class HomeLayoutItem {
  final HomeWidgetId type;
  final int? exerciseId;
  final String? metricRef;

  const HomeLayoutItem(this.type, {this.exerciseId, this.metricRef});

  /// Persisted form — `<type>`, `<type>:<exerciseId>`, or `<type>:<metricRef>`.
  String get token {
    if (exerciseId != null) return '${type.key}:$exerciseId';
    if (metricRef != null) return '${type.key}:$metricRef';
    return type.key;
  }

  static HomeLayoutItem? fromToken(String raw) {
    final i = raw.indexOf(':');
    final typeKey = i == -1 ? raw : raw.substring(0, i);
    final rest = i == -1 ? null : raw.substring(i + 1);
    final type = HomeWidgetIdKey.fromKey(typeKey);
    if (type == null) return null;
    if (type == HomeWidgetId.strengthTrends) {
      return HomeLayoutItem(type, exerciseId: rest == null ? null : int.tryParse(rest));
    }
    if (type == HomeWidgetId.metricTrend) {
      return HomeLayoutItem(type, metricRef: rest);
    }
    return HomeLayoutItem(type);
  }

  @override
  bool operator ==(Object other) =>
      other is HomeLayoutItem &&
      other.type == type &&
      other.exerciseId == exerciseId &&
      other.metricRef == metricRef;

  @override
  int get hashCode => Object.hash(type, exerciseId, metricRef);
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
