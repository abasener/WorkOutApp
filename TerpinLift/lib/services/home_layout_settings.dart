import 'package:flutter/material.dart';

/// Shared cap for every Home widget's title field (`HomeWidgetTitleSheet`,
/// and the title field inside `StrengthTrendEditSheet`/`MetricTrendEditSheet`/
/// `WeekRingsEditSheet`). A single-line `subHeader` header (16sp, w600) has
/// to fit the screen width minus `AppSpacing.edge` on both sides; sized off
/// a conservative worst-case wide-glyph width (~0.85em, i.e. "W"/"M"-heavy
/// text) at the smallest realistic phone width (~360dp), so it holds even
/// for all-caps titles, not just an average-case character mix. No counter
/// is shown alongside it (`counterText: ''`) — the cap is meant to be felt,
/// not read as a number.
const homeWidgetTitleMaxLength = 24;

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

  /// Whether this type is repeatable (`strengthTrends`/`metricTrend`/
  /// `weekRings` — one card per lift/metric, can be fully removed and
  /// re-added) vs. single-instance (everything else — hide-only, always
  /// present in the order, never fully removable). Decides whether a card
  /// gets a trash icon alongside its eye icon in edit mode.
  bool get isRepeatable =>
      this == HomeWidgetId.strengthTrends ||
      this == HomeWidgetId.metricTrend ||
      this == HomeWidgetId.weekRings;

  /// Whether this type's settings sheet has a time-frame override at all
  /// (`strengthTrends`/`metricTrend` plot a history-windowed chart;
  /// `weekRings` is always exactly 7 days, no window concept; every
  /// single-instance type has no chart to window in the first place).
  bool get hasTimeFrame =>
      this == HomeWidgetId.strengthTrends || this == HomeWidgetId.metricTrend;
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

  /// Whether this card is hidden — stays in place (still reorderable),
  /// renders dimmed in edit mode, doesn't render at all outside it. For a
  /// single-instance type this replaces "absent from the order" as the only
  /// way to hide something (2026-07-26) — those types are never fully
  /// removable anymore, only hidden. Repeatable types can be both hidden
  /// *and* fully removed (a trash icon, separate from the eye).
  final bool hidden;

  /// User-editable override for this card's header — tri-state, distinct
  /// from a plain nullable string:
  /// - `null` — not customized, use the type's default label (or, for
  ///   strengthTrends/metricTrend/weekRings, the resolved lift/metric name).
  /// - `''` — explicitly cleared: show **no** header at all, not even the
  ///   default. Deliberately does not fall back to the default — a user who
  ///   clears the field and saves means "no title here," not "reset it."
  /// - any other string — the literal override text.
  final String? title;

  /// This card's own history window, in months — `null` means "Default,"
  /// which tracks `HomeTrendSettings.months` live. Only meaningful where
  /// `HomeWidgetId.hasTimeFrame` is true.
  final int? monthsOverride;

  const HomeLayoutItem(
    this.type, {
    this.exerciseId,
    this.metricRef,
    this.showGoal = false,
    this.hidden = false,
    this.title,
    this.monthsOverride,
  });

  /// Identity independent of the mutable flags below — use for a
  /// `ReorderableListView`'s `ValueKey` instead of `token`, which changes
  /// whenever hidden/title/monthsOverride/showGoal is toggled and would
  /// otherwise make the list treat an in-place settings change as a
  /// completely different item mid-interaction.
  String get stableKey {
    if (exerciseId != null) return '${type.key}:$exerciseId';
    if (metricRef != null) return '${type.key}:$metricRef';
    return type.key;
  }

  /// Persisted form — base `<type>`, `<type>:<exerciseId>`, or
  /// `<type>:<metricRef>` (a custom metric's own ref already contains a
  /// colon, e.g. `custom:5` — only ever appended to, never blind-split),
  /// plus any of `;hidden=1` / `;months=<n>` / `;goal=1` /
  /// `;title=<percent-encoded>` for whichever flags differ from their
  /// default. `title` is percent-encoded since it's free user text that
  /// could otherwise contain `,`/`:`/`;` and corrupt either this token's own
  /// delimiters or the outer comma-joined settings string — written whenever
  /// `title` is non-null, **including** the explicitly-blank `''` case,
  /// which must round-trip distinctly from "not customized" (absent).
  String get token {
    final base = exerciseId != null
        ? '${type.key}:$exerciseId'
        : metricRef != null
        ? '${type.key}:$metricRef'
        : type.key;
    final flags = [
      if (hidden) 'hidden=1',
      if (monthsOverride != null) 'months=$monthsOverride',
      if (showGoal) 'goal=1',
      if (title != null) 'title=${Uri.encodeComponent(title!)}',
    ];
    return flags.isEmpty ? base : '$base;${flags.join(';')}';
  }

  static HomeLayoutItem? fromToken(String raw) {
    final parts = raw.split(';');
    final base = parts.first;

    var hidden = false;
    int? monthsOverride;
    var showGoalFlag = false;
    String? title;
    for (final flag in parts.skip(1)) {
      if (flag == 'hidden=1') hidden = true;
      if (flag == 'goal=1') showGoalFlag = true;
      if (flag.startsWith('months=')) {
        monthsOverride = int.tryParse(flag.substring('months='.length));
      }
      if (flag.startsWith('title=')) {
        title = Uri.decodeComponent(flag.substring('title='.length));
      }
    }

    final i = base.indexOf(':');
    final typeKey = i == -1 ? base : base.substring(0, i);
    var rest = i == -1 ? null : base.substring(i + 1);
    final type = HomeWidgetIdKey.fromKey(typeKey);
    if (type == null) return null;

    if (type == HomeWidgetId.strengthTrends) {
      return HomeLayoutItem(
        type,
        exerciseId: rest == null ? null : int.tryParse(rest),
        hidden: hidden,
        title: title,
        monthsOverride: monthsOverride,
      );
    }
    if (type == HomeWidgetId.metricTrend || type == HomeWidgetId.weekRings) {
      // Backward compat: an earlier round wrote the goal flag as a
      // `:goal` suffix directly on the metricRef rather than the `;goal=1`
      // flag above — still read as showGoal so nothing already saved
      // on-device silently loses its goal-line setting. New saves always
      // use the `;goal=1` form via `token` above.
      var legacyGoal = false;
      if (rest != null && rest.endsWith(':goal')) {
        legacyGoal = true;
        rest = rest.substring(0, rest.length - ':goal'.length);
      }
      return HomeLayoutItem(
        type,
        metricRef: rest,
        showGoal: showGoalFlag || legacyGoal,
        hidden: hidden,
        title: title,
        monthsOverride: monthsOverride,
      );
    }
    return HomeLayoutItem(type, hidden: hidden, title: title);
  }

  /// `title`/`monthsOverride` need tri-state updates (leave alone / set to a
  /// value / clear back to default), which a plain `newValue ?? oldValue`
  /// copyWith can't express — wrapped in a function so "clear it" can be
  /// `() => null` and "leave alone" can stay the default `null` argument,
  /// distinguishing the two.
  HomeLayoutItem copyWith({
    bool? hidden,
    String? Function()? title,
    int? Function()? monthsOverride,
    bool? showGoal,
  }) => HomeLayoutItem(
    type,
    exerciseId: exerciseId,
    metricRef: metricRef,
    hidden: hidden ?? this.hidden,
    title: title != null ? title() : this.title,
    monthsOverride: monthsOverride != null
        ? monthsOverride()
        : this.monthsOverride,
    showGoal: showGoal ?? this.showGoal,
  );

  @override
  bool operator ==(Object other) =>
      other is HomeLayoutItem &&
      other.type == type &&
      other.exerciseId == exerciseId &&
      other.metricRef == metricRef &&
      other.showGoal == showGoal &&
      other.hidden == hidden &&
      other.title == title &&
      other.monthsOverride == monthsOverride;

  @override
  int get hashCode => Object.hash(
    type,
    exerciseId,
    metricRef,
    showGoal,
    hidden,
    title,
    monthsOverride,
  );
}

/// Home screen's section order/visibility — an ordered list of every
/// `HomeLayoutItem` currently placed; visibility is `HomeLayoutItem.hidden`,
/// not presence in this list (2026-07-26) — a single-instance type is always
/// present here, hidden or not. `order == null` means "not customized yet,"
/// in which case Home falls back to every section in its original default
/// order, with one `strengthTrends` entry per zero-state active lift.
abstract class HomeLayoutSettings {
  static List<HomeLayoutItem>? order;
}
