import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_body_heatmap/flutter_body_heatmap.dart';

import '../../data/models/bodyweight_entry.dart';
import '../../data/models/custom_metric.dart';
import '../../data/models/custom_metric_entry.dart';
import '../../data/models/exercise.dart';
import '../../data/models/hiit_session.dart';
import '../../data/models/metric_entry.dart';
import '../../data/models/workout_plan.dart';
import '../../data/repositories/lift_repository.dart';
import '../../services/app_services.dart';
import '../../services/home_layout_settings.dart';
import '../../services/home_trend_settings.dart';
import '../../services/metric_chart_points.dart';
import '../../services/readiness_engine.dart';
import '../../services/training_composition_service.dart';
import '../../services/trend_engine.dart';
import '../../services/units.dart';
import '../../services/user_profile.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_card.dart';
import '../../widgets/info_tooltip.dart';
import '../../widgets/labeled_trend_chart.dart';
import '../../widgets/muscle_status_row.dart';
import '../../widgets/primed_lifts_row.dart';
import '../../widgets/readiness_bands.dart';
import '../../widgets/readiness_legend.dart';
import '../../widgets/tap_icon.dart';
import '../../widgets/todo_list_card.dart';
import '../../widgets/training_composition_chart.dart';
import '../../widgets/week_rings.dart';
import '../exercise_detail_nav.dart';
import '../hiit/hiit_active_screen.dart';
import '../hiit/hiit_setup_screen.dart';
import '../planner/active_day_screen.dart';
import '../planner/day_select_screen.dart';
import 'home_widget_title_sheet.dart';
import 'metric_trend_edit_sheet.dart';
import 'strength_trend_edit_sheet.dart';
import 'week_rings_edit_sheet.dart';

// Zero-state fallback (no pins yet, no customized selection) caps at this
// many recently-active lifts — see designFiles/02_SCREEN_home.md.
const _defaultTrendLiftCount = 4;

class HomeScreen extends StatefulWidget {
  /// Whether this is the currently-visible bottom-nav tab. `RootShell` keeps
  /// every tab alive in an `IndexedStack`, so without this Home would stay
  /// in edit mode forever once entered — this lets `didUpdateWidget` notice
  /// the tab going inactive and auto-exit, rather than requiring the user to
  /// remember to tap Done every time (designFiles/02_SCREEN_home.md).
  final bool active;

  const HomeScreen({super.key, required this.active});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _loading = true;
  bool _editing = false;
  Set<String> _workoutDates = {};
  Map<String, double> _stepsByDate = {};
  List<Exercise> _exercises = [];
  final Map<int, List<SessionWithSets>> _sessionsByExercise = {};
  List<CategoryComposition> _compositions = [];
  Map<Muscle, double> _readiness = {};
  List<CategoryStatus> _categoryStatuses = [];
  List<Exercise> _primedLifts = [];
  PlannedSession? _activeSession;
  WorkoutTemplateDay? _activeDay;
  HiitSession? _activeHiit;
  Timer? _ticker;

  // Metric Trend cards — same underlying data the Metrics screen's Overview
  // tab uses, loaded here too since Home is a separate screen/state.
  final Map<MetricType, List<MetricEntry>> _metricEntries = {};
  List<BodyweightEntry> _bodyweight = [];
  Map<String, double> _workoutDurationByDate = {};
  List<CustomMetric> _customMetrics = [];
  final Map<int, List<CustomMetricEntry>> _customMetricEntries = {};

  @override
  void initState() {
    super.initState();
    AppServices.reloadSignal.addListener(_load);
    _load();
    // Only matters while a session is active (the card's elapsed-time
    // display) — harmless no-op rebuild otherwise.
    _ticker = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted && _activeSession != null) setState(() {});
    });
  }

  @override
  void didUpdateWidget(HomeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.active && !widget.active) {
      setState(() => _editing = false);
    }
  }

  @override
  void dispose() {
    AppServices.reloadSignal.removeListener(_load);
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final dates = await AppServices.lifts.getAllWorkoutDates();
    final cardioDates = await AppServices.cardio.getAllWorkoutDates();
    final exercises = await AppServices.exercises.getAll();
    final steps = await AppServices.metrics.getByType(
      MetricType.steps,
      limit: 14,
    );
    final compositions = await TrainingCompositionService.compute();
    final readiness = await ReadinessEngine.computeMuscleReadiness();
    final categoryStatuses = await ReadinessEngine.computeCategoryStatus();

    final sessionsByExercise = <int, List<SessionWithSets>>{};
    for (final e in exercises) {
      if (e.id == null) continue;
      sessionsByExercise[e.id!] = await AppServices.lifts
          .getSessionsForExercise(e.id!);
    }

    final primedLifts = ReadinessEngine.suggestPrimedLifts(
      exercises,
      readiness,
    );

    final activeSession = await AppServices.workoutPlans.getActiveSession();
    final activeDay = activeSession == null
        ? null
        : await AppServices.workoutPlans.getDay(activeSession.templateDayId);
    final activeHiit = await AppServices.hiit.getActiveSession();

    // Metric Trend cards' data — same queries the Metrics screen's Overview
    // tab runs, see MetricChartPoints for the shared point computation.
    final metricEntries = <MetricType, List<MetricEntry>>{};
    for (final type in [MetricType.steps, MetricType.sleepHours]) {
      metricEntries[type] = await AppServices.metrics.getByType(type);
    }
    final bodyweight = await AppServices.bodyweight.getAll();
    final liftSessions = await AppServices.lifts.getAllSessions();
    final plannedSessions = await AppServices.workoutPlans.getAllSessions();
    final workoutDurationByDate = TrendEngine.workoutDurationMinutesByDate(
      liftSessions,
      plannedSessions: plannedSessions,
    );
    final customMetrics = await AppServices.customMetrics.getAllDefinitions();
    final customMetricEntries = <int, List<CustomMetricEntry>>{};
    for (final metric in customMetrics) {
      customMetricEntries[metric.id!] = await AppServices.customMetrics
          .getEntries(metric.id!);
    }

    if (!mounted) return;
    setState(() {
      _workoutDates = {...dates, ...cardioDates};
      _stepsByDate = {for (final m in steps) m.date: m.value};
      _exercises = exercises;
      _sessionsByExercise
        ..clear()
        ..addAll(sessionsByExercise);
      _compositions = compositions;
      _readiness = readiness;
      _categoryStatuses = categoryStatuses;
      _primedLifts = primedLifts;
      _activeSession = activeSession;
      _activeDay = activeDay;
      _activeHiit = activeHiit;
      _metricEntries
        ..clear()
        ..addAll(metricEntries);
      _bodyweight = bodyweight;
      _workoutDurationByDate = workoutDurationByDate;
      _customMetrics = customMetrics;
      _customMetricEntries
        ..clear()
        ..addAll(customMetricEntries);
      _loading = false;
    });
  }

  String get _elapsedLabel {
    final session = _activeSession;
    if (session == null) return '';
    final elapsed = DateTime.now().difference(
      DateTime.parse(session.startedAt),
    );
    final h = elapsed.inHours;
    final m = elapsed.inMinutes % 60;
    return h > 0 ? '${h}h ${m}m' : '${m}m';
  }

  Widget _buildPlannerCard(BuildContext context) {
    final session = _activeSession;
    final day = _activeDay;
    if (session == null || day == null) {
      return AppCard(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const DaySelectScreen()),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.event_note_outlined,
              color: AppColors.textSecondary,
            ),
            const SizedBox(width: AppSpacing.standard),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Plan a session', style: AppText.bodyText),
                  const SizedBox(height: AppSpacing.micro),
                  Text('See what\'s ready to train', style: AppText.smallText),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: AppColors.textSecondary),
          ],
        ),
      );
    }

    return AppCard(
      backgroundColor: AppColors.accentDim,
      borderColor: AppColors.accent,
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ActiveDayScreen(session: session, day: day),
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.event_note, color: AppColors.accent),
          const SizedBox(width: AppSpacing.standard),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(day.dayLabel, style: AppText.bodyText),
                const SizedBox(height: AppSpacing.micro),
                Text(
                  '$_elapsedLabel · tap to resume',
                  style: AppText.smallText,
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right, color: AppColors.accent),
        ],
      ),
    );
  }

  Widget _buildHiitCard(BuildContext context) {
    final session = _activeHiit;
    if (session == null) {
      return AppCard(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const HiitSetupScreen()),
        ),
        child: Row(
          children: [
            const Icon(Icons.bolt_outlined, color: AppColors.textSecondary),
            const SizedBox(width: AppSpacing.standard),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('HIIT', style: AppText.bodyText),
                  const SizedBox(height: AppSpacing.micro),
                  Text('Set up a circuit', style: AppText.smallText),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: AppColors.textSecondary),
          ],
        ),
      );
    }

    return AppCard(
      backgroundColor: AppColors.accentDim,
      borderColor: AppColors.accent,
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => HiitActiveScreen(sessionId: session.id!),
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.bolt, color: AppColors.accent),
          const SizedBox(width: AppSpacing.standard),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('HIIT in progress', style: AppText.bodyText),
                const SizedBox(height: AppSpacing.micro),
                Text(
                  session.paused ? 'Paused · tap to resume' : 'Tap to resume',
                  style: AppText.smallText,
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right, color: AppColors.accent),
        ],
      ),
    );
  }

  // ---- Layout: default order, current order, and edit-mode mutations ----

  // Zero state: no customized selection yet -> pinned lifts (the "usual
  // suspects"), falling back further to recently-active ones if nothing is
  // pinned either (e.g. a very fresh install). Only used to seed the
  // default (never-customized) layout with individual Strength Trend cards.
  List<Exercise> get _defaultTrendLifts {
    final pinned = _exercises.where((e) => e.pinned).toList();
    return (pinned.isNotEmpty ? pinned : _exercises)
        .where((e) => (_sessionsByExercise[e.id] ?? []).isNotEmpty)
        .take(_defaultTrendLiftCount)
        .toList();
  }

  List<HomeLayoutItem> get _defaultOrder {
    final result = <HomeLayoutItem>[];
    for (final id in HomeWidgetId.values) {
      if (id == HomeWidgetId.strengthTrends) {
        for (final e in _defaultTrendLifts) {
          if (e.id != null) {
            result.add(
              HomeLayoutItem(HomeWidgetId.strengthTrends, exerciseId: e.id),
            );
          }
        }
      } else if (id == HomeWidgetId.metricTrend) {
        // Opt-in only, per designFiles/02_SCREEN_home.md — there's no
        // natural "which metric" default the way Strength Trends has a
        // zero-state active-lift list, so this is skipped entirely rather
        // than defaulting to a metricRef-less card with nothing to show.
        // Add one from the "+" menu if you want it.
      } else {
        result.add(HomeLayoutItem(id));
      }
    }
    return result;
  }

  List<HomeLayoutItem> get _currentOrder =>
      HomeLayoutSettings.order ?? _defaultOrder;

  Future<void> _persistOrder(List<HomeLayoutItem> order) async {
    await AppServices.setHomeWidgetOrder(order);
    if (mounted) setState(() {});
  }

  Future<void> _reorder(int oldIndex, int newIndex) async {
    final order = [..._currentOrder];
    if (newIndex > oldIndex) newIndex -= 1;
    final item = order.removeAt(oldIndex);
    order.insert(newIndex, item);
    await _persistOrder(order);
  }

  Future<void> _removeItem(HomeLayoutItem item) async {
    final order = [..._currentOrder]..remove(item);
    await _persistOrder(order);
  }

  /// Toggles a card's hidden flag in place — the only way to hide/show a
  /// single-instance widget, and one of two ways (with the trash icon) to
  /// affect a repeatable one. Mirrors Metrics' equivalent toggle.
  Future<void> _toggleHidden(HomeLayoutItem item) async {
    final order = [..._currentOrder];
    final i = order.indexOf(item);
    if (i == -1) return;
    order[i] = item.copyWith(hidden: !item.hidden);
    await _persistOrder(order);
  }

  Future<(int, String, int?)?> _pickLift({
    required Set<int> alreadyUsedIds,
    int? currentId,
    required String defaultTitle,
    String? currentTitle,
    int? monthsOverride,
  }) {
    return showModalBottomSheet<(int, String, int?)>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => StrengthTrendEditSheet(
        exercises: _exercises,
        selectedId: currentId,
        alreadyUsedIds: alreadyUsedIds,
        defaultTitle: defaultTitle,
        currentTitle: currentTitle,
        monthsOverride: monthsOverride,
      ),
    );
  }

  String _strengthDefaultTitle(HomeLayoutItem item) {
    final byId = {
      for (final e in _exercises)
        if (e.id != null) e.id!: e,
    };
    return byId[item.exerciseId]?.name ?? 'Strength Trend';
  }

  Future<void> _editStrengthTrend(HomeLayoutItem item) async {
    final order = _currentOrder;
    final usedIds = order
        .where((i) => i.type == HomeWidgetId.strengthTrends && i != item)
        .map((i) => i.exerciseId)
        .whereType<int>()
        .toSet();
    final defaultTitle = _strengthDefaultTitle(item);
    final result = await _pickLift(
      alreadyUsedIds: usedIds,
      currentId: item.exerciseId,
      defaultTitle: defaultTitle,
      currentTitle: item.title,
      monthsOverride: item.monthsOverride,
    );
    if (result == null) return;
    final (exerciseId, title, monthsOverride) = result;
    final newOrder = [
      for (final i in order)
        i == item
            ? HomeLayoutItem(
                HomeWidgetId.strengthTrends,
                exerciseId: exerciseId,
                title: _resolveTitle(title, defaultTitle),
                monthsOverride: monthsOverride,
              )
            : i,
    ];
    await _persistOrder(newOrder);
  }

  /// Every ref that actually has a goal value set right now — steps always
  /// has one; weight/sleep only if set in Settings; a custom metric only if
  /// `kind == number` and its own goal is set. Feeds both the Metric Trend
  /// edit sheet's goal toggle and the This Week ring picker.
  Map<String, double> _goalsByRef() {
    final map = <String, double>{'steps': UserProfile.stepsGoal.toDouble()};
    if (UserProfile.weightGoalLb != null) {
      map['weight'] = UserProfile.weightGoalLb!;
    }
    if (UserProfile.sleepGoalHours != null) {
      map['sleep'] = UserProfile.sleepGoalHours!;
    }
    for (final m in _customMetrics) {
      if (m.kind == CustomMetricKind.number && m.goal != null && m.id != null) {
        map['custom:${m.id}'] = m.goal!;
      }
    }
    return map;
  }

  Future<(String, String, int?, bool)?> _pickMetric({
    required Set<String> alreadyUsedRefs,
    String? currentRef,
    required String defaultTitle,
    String? currentTitle,
    int? monthsOverride,
    bool currentShowGoal = false,
  }) {
    return showModalBottomSheet<(String, String, int?, bool)>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => MetricTrendEditSheet(
        options: MetricTrendOption.all(_customMetrics),
        selectedRef: currentRef,
        alreadyUsedRefs: alreadyUsedRefs,
        defaultTitle: defaultTitle,
        currentTitle: currentTitle,
        monthsOverride: monthsOverride,
        showGoal: currentShowGoal,
        goalsByRef: _goalsByRef(),
      ),
    );
  }

  String _metricDefaultTitle(HomeLayoutItem item) {
    return _metricTrendInfo(item.metricRef, DateTime.now())?.title ??
        'Metric Trend';
  }

  Future<void> _editMetricTrend(HomeLayoutItem item) async {
    final order = _currentOrder;
    final usedRefs = order
        .where((i) => i.type == HomeWidgetId.metricTrend && i != item)
        .map((i) => i.metricRef)
        .whereType<String>()
        .toSet();
    final defaultTitle = _metricDefaultTitle(item);
    final result = await _pickMetric(
      alreadyUsedRefs: usedRefs,
      currentRef: item.metricRef,
      defaultTitle: defaultTitle,
      currentTitle: item.title,
      monthsOverride: item.monthsOverride,
      currentShowGoal: item.showGoal,
    );
    if (result == null) return;
    final (ref, title, monthsOverride, showGoal) = result;
    final newOrder = [
      for (final i in order)
        i == item
            ? HomeLayoutItem(
                HomeWidgetId.metricTrend,
                metricRef: ref,
                title: _resolveTitle(title, defaultTitle),
                monthsOverride: monthsOverride,
                showGoal: showGoal,
              )
            : i,
    ];
    await _persistOrder(newOrder);
  }

  String _weekRingsDefaultTitle(HomeLayoutItem item) {
    final rings = _weekRingsInfo(item.metricRef);
    return rings == null ? 'This Week' : 'This Week · ${rings.title}';
  }

  /// Opens the settings sheet for a single-instance widget's gear icon —
  /// title only, since none of these types have any other per-card setting.
  Future<void> _editSingleInstanceTitle(HomeLayoutItem item) async {
    final order = [..._currentOrder];
    final i = order.indexOf(item);
    if (i == -1) return;
    final defaultTitle = _defaultTitleFor(item);
    // The sheet pops the raw typed text (may be '') and null only when
    // dismissed without saving — see home_widget_title_sheet.dart.
    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => HomeWidgetTitleSheet(
        defaultTitle: defaultTitle,
        currentTitle: item.title,
      ),
    );
    if (result == null) return;
    order[i] = item.copyWith(title: () => _resolveTitle(result, defaultTitle));
    await _persistOrder(order);
  }

  /// Maps a sheet's raw, verbatim-typed title text back onto
  /// `HomeLayoutItem.title`'s tri-state: left exactly as the shown default
  /// resolves to "not customized" (`null`, tracks the default live, even if
  /// it changes later); anything else — including an explicitly cleared `''`
  /// — is taken literally, so clearing the field never silently falls back
  /// to showing the default title again.
  String? _resolveTitle(String raw, String defaultTitle) =>
      raw == defaultTitle ? null : raw;

  Future<void> _editItem(HomeLayoutItem item) {
    switch (item.type) {
      case HomeWidgetId.strengthTrends:
        return _editStrengthTrend(item);
      case HomeWidgetId.metricTrend:
        return _editMetricTrend(item);
      case HomeWidgetId.weekRings:
        return _editWeekRings(item);
      default:
        return _editSingleInstanceTitle(item);
    }
  }

  String _defaultTitleFor(HomeLayoutItem item) {
    switch (item.type) {
      case HomeWidgetId.muscleStatus:
        return 'Muscle Status';
      case HomeWidgetId.planner:
        return 'Plan a Session';
      case HomeWidgetId.todoList:
        return 'Checklist';
      case HomeWidgetId.weekRings:
        return _weekRingsDefaultTitle(item);
      case HomeWidgetId.primedForGrowth:
        return 'Primed for Growth';
      case HomeWidgetId.trainingSplit:
        return 'Training Split';
      case HomeWidgetId.strengthTrends:
        return _strengthDefaultTitle(item);
      case HomeWidgetId.metricTrend:
        return _metricDefaultTitle(item);
      case HomeWidgetId.hiit:
        return 'HIIT';
    }
  }

  /// `null` means show no header at all — either the type has none by
  /// design, or the user explicitly cleared this card's title (see
  /// `HomeLayoutItem.title`'s tri-state doc comment).
  String? _effectiveTitle(HomeLayoutItem item) {
    final title = item.title;
    if (title == null) return _defaultTitleFor(item);
    return title.isEmpty ? null : title;
  }

  Future<void> _addWidgetMenu() async {
    final order = _currentOrder;
    final picked = await showModalBottomSheet<HomeWidgetId>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.edge,
          AppSpacing.standard,
          AppSpacing.edge,
          AppSpacing.large,
        ),
        decoration: const BoxDecoration(
          color: AppColors.surfaceRaised,
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppRadius.card),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Add a widget', style: AppText.subHeader),
            const SizedBox(height: AppSpacing.standard),
            if (_goalsByRef().isNotEmpty)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  HomeWidgetId.weekRings.icon,
                  color: AppColors.textSecondary,
                ),
                title: Text(
                  HomeWidgetId.weekRings.label,
                  style: AppText.bodyText,
                ),
                subtitle: Text(
                  'Add another goal-linked metric\'s ring row',
                  style: AppText.smallText,
                ),
                onTap: () => Navigator.pop(context, HomeWidgetId.weekRings),
              ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                HomeWidgetId.strengthTrends.icon,
                color: AppColors.textSecondary,
              ),
              title: Text(
                HomeWidgetId.strengthTrends.label,
                style: AppText.bodyText,
              ),
              subtitle: Text(
                'Add another lift\'s trend card',
                style: AppText.smallText,
              ),
              onTap: () => Navigator.pop(context, HomeWidgetId.strengthTrends),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                HomeWidgetId.metricTrend.icon,
                color: AppColors.textSecondary,
              ),
              title: Text(
                HomeWidgetId.metricTrend.label,
                style: AppText.bodyText,
              ),
              subtitle: Text(
                'Add another metric\'s trend card',
                style: AppText.smallText,
              ),
              onTap: () => Navigator.pop(context, HomeWidgetId.metricTrend),
            ),
          ],
        ),
      ),
    );
    if (picked == null) return;
    if (picked == HomeWidgetId.strengthTrends) {
      final usedIds = order
          .where((i) => i.type == HomeWidgetId.strengthTrends)
          .map((i) => i.exerciseId)
          .whereType<int>()
          .toSet();
      const defaultTitle = 'Strength Trend';
      final result = await _pickLift(
        alreadyUsedIds: usedIds,
        currentId: null,
        defaultTitle: defaultTitle,
        currentTitle: null,
        monthsOverride: null,
      );
      if (result == null) return;
      final (exerciseId, title, monthsOverride) = result;
      await _persistOrder([
        HomeLayoutItem(
          HomeWidgetId.strengthTrends,
          exerciseId: exerciseId,
          title: _resolveTitle(title, defaultTitle),
          monthsOverride: monthsOverride,
        ),
        ...order,
      ]);
    } else if (picked == HomeWidgetId.metricTrend) {
      final usedRefs = order
          .where((i) => i.type == HomeWidgetId.metricTrend)
          .map((i) => i.metricRef)
          .whereType<String>()
          .toSet();
      const defaultTitle = 'Metric Trend';
      final result = await _pickMetric(
        alreadyUsedRefs: usedRefs,
        currentRef: null,
        defaultTitle: defaultTitle,
        currentTitle: null,
        monthsOverride: null,
      );
      if (result == null) return;
      final (ref, title, monthsOverride, showGoal) = result;
      await _persistOrder([
        HomeLayoutItem(
          HomeWidgetId.metricTrend,
          metricRef: ref,
          title: _resolveTitle(title, defaultTitle),
          monthsOverride: monthsOverride,
          showGoal: showGoal,
        ),
        ...order,
      ]);
    } else if (picked == HomeWidgetId.weekRings) {
      final usedRefs = order
          .where((i) => i.type == HomeWidgetId.weekRings)
          .map((i) => i.metricRef ?? 'steps')
          .toSet();
      const defaultTitle = 'This Week';
      final result = await _pickWeekRingsMetric(
        alreadyUsedRefs: usedRefs,
        currentRef: null,
        defaultTitle: defaultTitle,
        currentTitle: null,
      );
      if (result == null) return;
      final (ref, title) = result;
      await _persistOrder([
        HomeLayoutItem(
          HomeWidgetId.weekRings,
          metricRef: ref == 'steps' ? null : ref,
          title: _resolveTitle(title, defaultTitle),
        ),
        ...order,
      ]);
    } else {
      await _persistOrder([HomeLayoutItem(picked), ...order]);
    }
  }

  /// Only offers metrics that currently have a goal set (`_goalsByRef`) —
  /// a ring row with nothing to measure against wouldn't mean anything.
  /// `'steps'` is used as the picker's stand-in for a `null` metricRef (the
  /// original, pre-repeatable meaning) so it shows/selects like any other
  /// option rather than needing special-casing in the sheet itself.
  /// **Deliberately not restricted to one card per metric** (2026-07-26,
  /// unlike Strength Trend/Metric Trend, which still just dim already-used
  /// lifts/metrics rather than exclude them either) — the user explicitly
  /// wants e.g. two separate Steps rings placed in different spots on the
  /// page to be allowed. `alreadyUsedRefs` only dims, same as the other two.
  Future<(String, String)?> _pickWeekRingsMetric({
    required Set<String> alreadyUsedRefs,
    String? currentRef,
    required String defaultTitle,
    String? currentTitle,
  }) {
    final goals = _goalsByRef();
    final options = MetricTrendOption.all(
      _customMetrics,
    ).where((o) => goals.containsKey(o.ref)).toList();
    return showModalBottomSheet<(String, String)>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => WeekRingsEditSheet(
        options: options,
        selectedRef: currentRef,
        alreadyUsedRefs: alreadyUsedRefs,
        defaultTitle: defaultTitle,
        currentTitle: currentTitle,
      ),
    );
  }

  Future<void> _editWeekRings(HomeLayoutItem item) async {
    final order = _currentOrder;
    final currentRef = item.metricRef ?? 'steps';
    final usedRefs = order
        .where((i) => i.type == HomeWidgetId.weekRings && i != item)
        .map((i) => i.metricRef ?? 'steps')
        .toSet();
    final defaultTitle = _weekRingsDefaultTitle(item);
    final result = await _pickWeekRingsMetric(
      alreadyUsedRefs: usedRefs,
      currentRef: currentRef,
      defaultTitle: defaultTitle,
      currentTitle: item.title,
    );
    if (result == null) return;
    final (ref, title) = result;
    final newOrder = [
      for (final i in order)
        i == item
            ? HomeLayoutItem(
                HomeWidgetId.weekRings,
                metricRef: ref == 'steps' ? null : ref,
                title: _resolveTitle(title, defaultTitle),
              )
            : i,
    ];
    await _persistOrder(newOrder);
  }

  /// Resolves a This Week ring card's `metricRef` (`null` meaning steps, the
  /// original pre-repeatable meaning) to its per-date values + goal — `null`
  /// if that metric no longer has a goal set (cleared in Settings/on the
  /// metric after this card was pointed at it). Reuses whichever per-date
  /// map `_metricTrendInfo`'s sibling data already builds for each source
  /// rather than duplicating the lookups.
  ({String title, Map<String, double> valuesByDate, double goal})?
  _weekRingsInfo(String? ref) {
    final effectiveRef = ref ?? 'steps';
    final goal = _goalsByRef()[effectiveRef];
    if (goal == null) return null;
    switch (effectiveRef) {
      case 'steps':
        return (title: 'Steps', valuesByDate: _stepsByDate, goal: goal);
      case 'sleep':
        return (
          title: 'Sleep',
          valuesByDate: {
            for (final m
                in _metricEntries[MetricType.sleepHours] ??
                    const <MetricEntry>[])
              m.date: m.value,
          },
          goal: goal,
        );
      case 'weight':
        return (
          title: 'Weight',
          valuesByDate: {for (final b in _bodyweight) b.date: b.weight},
          goal: goal,
        );
    }
    if (effectiveRef.startsWith('custom:')) {
      final id = int.tryParse(effectiveRef.substring('custom:'.length));
      CustomMetric? metric;
      for (final m in _customMetrics) {
        if (m.id == id) {
          metric = m;
          break;
        }
      }
      if (metric == null) return null;
      final entries = _customMetricEntries[id] ?? const <CustomMetricEntry>[];
      return (
        title: metric.name,
        valuesByDate: {for (final e in entries) e.date: e.value},
        goal: goal,
      );
    }
    return null;
  }

  /// Resolves a Metric Trend card's `metricRef` token to a title + the same
  /// chart points/formatter the Metrics screen would compute for it
  /// (`MetricChartPoints`) — `null` if the ref is unset or points at a
  /// custom metric that's since been deleted.
  ({
    String title,
    List<ChartPoint> points,
    String Function(double)? yFormatter,
  })?
  _metricTrendInfo(String? ref, DateTime cutoff) {
    switch (ref) {
      case 'steps':
        return (
          title: 'Steps',
          points: MetricChartPoints.forEntries(
            _metricEntries[MetricType.steps] ?? [],
            cutoff,
          ),
          yFormatter: null,
        );
      case 'sleep':
        return (
          title: 'Sleep',
          points: MetricChartPoints.forEntries(
            _metricEntries[MetricType.sleepHours] ?? [],
            cutoff,
          ),
          yFormatter: null,
        );
      case 'weight':
        return (
          title: 'Weight',
          points: MetricChartPoints.weeklyBodyweight(_bodyweight, cutoff),
          yFormatter: Units.formatMaskable,
        );
      case 'workoutDuration':
        return (
          title: 'Workout Duration',
          points: MetricChartPoints.workoutDuration(
            _workoutDurationByDate,
            cutoff,
          ),
          yFormatter: (v) => '${v.round()}m',
        );
    }
    if (ref != null && ref.startsWith('custom:')) {
      final id = int.tryParse(ref.substring('custom:'.length));
      CustomMetric? metric;
      for (final m in _customMetrics) {
        if (m.id == id) {
          metric = m;
          break;
        }
      }
      if (metric == null) return null;
      return (
        title: metric.name,
        points: MetricChartPoints.customMetric(
          _customMetricEntries[metric.id] ?? [],
          cutoff,
        ),
        yFormatter: MetricChartPoints.customYFormatter(metric),
      );
    }
    return null;
  }

  /// This card's own history window — its `monthsOverride` if it has one,
  /// otherwise the shared `HomeTrendSettings.months` default (edited only
  /// from Settings now). `-1` (the "All time" sentinel) maps to a cutoff far
  /// enough back to include everything. Mirrors Metrics' `_cutoffFor`.
  DateTime _cutoffFor(HomeLayoutItem item) {
    final months = item.monthsOverride ?? HomeTrendSettings.months;
    if (months < 0) return DateTime(1970);
    final now = DateTime.now();
    return DateTime(now.year, now.month - months, now.day);
  }

  /// The header shown above every card — a plain title for most types, plus
  /// Primed for Growth's info tooltip alongside its own. `null` means no
  /// header at all (the user explicitly cleared this card's title) — the
  /// tooltip goes with it too in that case rather than floating alone.
  Widget? _sectionHeader(HomeLayoutItem item) {
    final title = _effectiveTitle(item);
    if (title == null) return null;
    if (item.type == HomeWidgetId.primedForGrowth) {
      return Row(
        children: [
          Text(title, style: AppText.subHeader),
          const InfoTooltip(
            glossaryKey: 'readiness',
            title: 'Primed for Growth',
            footer: ReadinessLegend(),
          ),
        ],
      );
    }
    return Text(title, style: AppText.subHeader);
  }

  Widget _buildSectionBody(BuildContext context, HomeLayoutItem item) {
    switch (item.type) {
      case HomeWidgetId.muscleStatus:
        return AppCard(child: MuscleStatusRow(statuses: _categoryStatuses));
      case HomeWidgetId.planner:
        return _buildPlannerCard(context);
      case HomeWidgetId.todoList:
        return const TodoListCard();
      case HomeWidgetId.weekRings:
        final rings = _weekRingsInfo(item.metricRef);
        return AppCard(
          child: rings == null
              ? Text(
                  // Only reachable if a metric's goal got cleared after
                  // this card was already set to track it.
                  'This metric no longer has a goal set.',
                  style: AppText.smallText,
                )
              : WeekRings(
                  valuesByDate: rings.valuesByDate,
                  goal: rings.goal,
                  workoutDates: _workoutDates,
                ),
        );
      case HomeWidgetId.primedForGrowth:
        final body = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppCard(
              child: SizedBox(
                height: 160,
                child: Row(
                  children: [
                    Expanded(
                      child: AspectRatio(
                        aspectRatio: 724 / 1448,
                        child: BodyHeatmap(
                          side: BodySide.front,
                          data: {
                            for (final entry in _readiness.entries)
                              entry.key: MuscleData(
                                color: ReadinessBands.colorFor(entry.value),
                              ),
                          },
                          bodyColor: AppColors.surfaceRaised,
                          borderColor: AppColors.textSecondary,
                          showBorder: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.standard),
                    Expanded(
                      child: AspectRatio(
                        aspectRatio: 724 / 1448,
                        child: BodyHeatmap(
                          side: BodySide.back,
                          data: {
                            for (final entry in _readiness.entries)
                              entry.key: MuscleData(
                                color: ReadinessBands.colorFor(entry.value),
                              ),
                          },
                          bodyColor: AppColors.surfaceRaised,
                          borderColor: AppColors.textSecondary,
                          showBorder: true,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.standard),
            PrimedLiftsRow(
              lifts: _primedLifts,
              onTap: (e) => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => exerciseDetailScreen(e)),
              ),
            ),
          ],
        );
        // Normally the info tooltip rides alongside the header text
        // (`_sectionHeader`) — cleared-title is treated as the edge case,
        // not the other way round, so it only drops down here, pinned to
        // the widget's own top-left corner, when there's no header for it
        // to sit next to. Any other widget that later gains its own header
        // tooltip should follow the same pattern.
        if (_effectiveTitle(item) != null) return body;
        return Stack(
          children: [
            body,
            Positioned(
              left: 0,
              top: 0,
              child: InfoTooltip(
                glossaryKey: 'readiness',
                title: 'Primed for Growth',
                footer: ReadinessLegend(),
              ),
            ),
          ],
        );
      case HomeWidgetId.trainingSplit:
        return AppCard(
          child: TrainingCompositionChart(compositions: _compositions),
        );
      case HomeWidgetId.strengthTrends:
        final byId = {
          for (final e in _exercises)
            if (e.id != null) e.id!: e,
        };
        final exercise = byId[item.exerciseId];
        final sessions = exercise == null
            ? <SessionWithSets>[]
            : _sessionsByExercise[exercise.id] ?? [];
        final cutoff = _cutoffFor(item);
        final points = sessions.reversed
            .where((s) => DateTime.parse(s.session.date).isAfter(cutoff))
            .map((s) => ChartPoint(DateTime.parse(s.session.date), s.bestE1rm))
            .where((p) => p.value > 0)
            .toList();
        if (exercise == null) {
          return AppCard(
            child: Text(
              _editing
                  ? 'Tap the gear above to choose a lift.'
                  : 'No lift chosen for this card yet.',
              style: AppText.smallText,
            ),
          );
        }
        return AppCard(
          child: points.isEmpty
              ? Text(
                  'Log ${exercise.name} to start seeing a trend here.',
                  style: AppText.smallText,
                )
              : CenteredTrendChart(
                  points: points,
                  showPrediction: true,
                  trendStyle: TrendStyle.polynomial,
                ),
        );
      case HomeWidgetId.metricTrend:
        final info = _metricTrendInfo(item.metricRef, _cutoffFor(item));
        return AppCard(
          child: info == null
              ? Text(
                  _editing
                      ? 'Tap the gear above to choose a metric.'
                      : 'No metric chosen for this card yet.',
                  style: AppText.smallText,
                )
              : LabeledTrendChart(
                  points: info.points,
                  yLabelFormatter: info.yFormatter,
                  height: 130,
                  goal: item.showGoal ? _goalsByRef()[item.metricRef] : null,
                ),
        );
      case HomeWidgetId.hiit:
        return _buildHiitCard(context);
    }
  }

  Widget _buildSection(BuildContext context, HomeLayoutItem item) {
    final header = _sectionHeader(item);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // No header at all (title explicitly cleared) skips its spacing too
        // — otherwise clearing a title would just swap visible text for an
        // equally-tall patch of empty space, not actually reclaim it.
        if (header != null) ...[
          header,
          const SizedBox(height: AppSpacing.standard),
        ],
        _buildSectionBody(context, item),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.accent),
      );
    }

    final order = _currentOrder;
    final visibleItems = order.where((i) => !i.hidden).toList();

    return RefreshIndicator(
      color: AppColors.accent,
      onRefresh: _load,
      child: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            backgroundColor: AppColors.background,
            title: const Text('TerrapinLift'),
            actions: [
              if (_editing)
                IconButton(
                  icon: const Icon(Icons.add),
                  tooltip: 'Add a widget',
                  onPressed: _addWidgetMenu,
                ),
              IconButton(
                icon: Icon(_editing ? Icons.check : Icons.edit_outlined),
                tooltip: _editing ? 'Done editing' : 'Edit layout',
                onPressed: () => setState(() => _editing = !_editing),
              ),
            ],
          ),
          if (!_editing)
            visibleItems.isEmpty
                ? const SliverToBoxAdapter(child: _EmptyHomeState())
                : SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.edge),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (final item in visibleItems) ...[
                            _buildSection(context, item),
                            const SizedBox(height: AppSpacing.large),
                          ],
                        ],
                      ),
                    ),
                  )
          else
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.edge),
              sliver: SliverReorderableList(
                itemCount: order.length,
                onReorder: _reorder,
                // SliverReorderableList's default drag proxy doesn't wrap
                // the dragged item in a Material ancestor (unlike the
                // higher-level ReorderableListView) — any InkWell inside the
                // dragged section (e.g. the Planner card's AppCard.onTap)
                // throws "No Material widget found" mid-drag without this.
                proxyDecorator: (child, index, animation) =>
                    Material(color: Colors.transparent, child: child),
                itemBuilder: (context, i) {
                  final item = order[i];
                  return Padding(
                    key: ValueKey(item.stableKey),
                    padding: const EdgeInsets.only(bottom: AppSpacing.large),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: IgnorePointer(
                            child: Opacity(
                              // Hidden cards still fully render (same
                              // size/content), just dimmed — makes exactly
                              // what's being toggled visible instead of
                              // collapsing to a bare row.
                              opacity: item.hidden ? 0.4 : 1.0,
                              // Caches each card's painted content as its own
                              // layer so dragging (which repositions/animates
                              // every other item) doesn't force expensive
                              // widgets — the body heatmap, chart painters —
                              // to repaint every frame; only the layer itself
                              // is transformed. This is what made drag/reorder
                              // feel choppy on heavier cards.
                              child: RepaintBoundary(
                                child: _buildSection(context, item),
                              ),
                            ),
                          ),
                        ),
                        // Drag / show-hide / settings / (repeatable-only)
                        // remove stacked in a column, not a row, so the
                        // controls only ever cost one icon's worth of width
                        // next to the card rather than squeezing it out.
                        Column(
                          children: [
                            ReorderableDragStartListener(
                              index: i,
                              child: const Padding(
                                padding: EdgeInsets.only(top: AppSpacing.small),
                                child: Icon(
                                  Icons.drag_handle,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ),
                            TapIcon(
                              icon: item.hidden
                                  ? Icons.visibility_off_outlined
                                  : Icons.visibility_outlined,
                              onTap: () => _toggleHidden(item),
                            ),
                            TapIcon(
                              icon: Icons.settings_outlined,
                              onTap: () => _editItem(item),
                            ),
                            if (item.type.isRepeatable)
                              TapIcon(
                                icon: Icons.delete_outline,
                                onTap: () => _removeItem(item),
                              ),
                          ],
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.xLarge)),
        ],
      ),
    );
  }
}

/// Shown instead of an empty scroll area when every widget is hidden — a
/// user who got here already hid each one individually, so this stays a
/// short nudge rather than a paragraph explaining edit mode from scratch.
class _EmptyHomeState extends StatelessWidget {
  const _EmptyHomeState();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xLarge * 2),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.widgets_outlined,
            size: 40,
            color: AppColors.textSecondary,
          ),
          const SizedBox(height: AppSpacing.standard),
          Text('Nothing to show', style: AppText.subHeader),
          const SizedBox(height: AppSpacing.micro),
          Text(
            'Tap the edit icon above to bring widgets back.',
            style: AppText.smallText,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
