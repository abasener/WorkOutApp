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
import 'metric_trend_edit_sheet.dart';
import 'strength_trend_edit_sheet.dart';

// Zero-state fallback (no pins yet, no customized selection) caps at this
// many recently-active lifts — see designFiles/02_SCREEN_home.md.
const _defaultTrendLiftCount = 4;

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

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

  Future<int?> _pickLift({
    required Set<int> excludeIds,
    int? currentId,
    required int months,
  }) async {
    final result = await showModalBottomSheet<(int, int)>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => StrengthTrendEditSheet(
        exercises: _exercises,
        selectedId: currentId,
        excludeIds: excludeIds,
        months: months,
      ),
    );
    if (result == null) return null;
    final (exerciseId, pickedMonths) = result;
    await AppServices.setHomeTrendMonths(pickedMonths);
    return exerciseId;
  }

  Future<void> _editStrengthTrend(HomeLayoutItem item) async {
    final order = _currentOrder;
    final usedIds = order
        .where((i) => i.type == HomeWidgetId.strengthTrends && i != item)
        .map((i) => i.exerciseId)
        .whereType<int>()
        .toSet();
    final exerciseId = await _pickLift(
      excludeIds: usedIds,
      currentId: item.exerciseId,
      months: HomeTrendSettings.months,
    );
    if (exerciseId == null) return;
    final newOrder = [
      for (final i in order)
        i == item
            ? HomeLayoutItem(
                HomeWidgetId.strengthTrends,
                exerciseId: exerciseId,
              )
            : i,
    ];
    await _persistOrder(newOrder);
  }

  Future<String?> _pickMetric({
    required Set<String> excludeRefs,
    String? currentRef,
    required int months,
  }) async {
    final options = MetricTrendOption.all(_customMetrics)
        .where((o) => o.ref == currentRef || !excludeRefs.contains(o.ref))
        .toList();
    final result = await showModalBottomSheet<(String, int)>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => MetricTrendEditSheet(
        options: options,
        selectedRef: currentRef,
        months: months,
      ),
    );
    if (result == null) return null;
    final (ref, pickedMonths) = result;
    await AppServices.setHomeTrendMonths(pickedMonths);
    return ref;
  }

  Future<void> _editMetricTrend(HomeLayoutItem item) async {
    final order = _currentOrder;
    final usedRefs = order
        .where((i) => i.type == HomeWidgetId.metricTrend && i != item)
        .map((i) => i.metricRef)
        .whereType<String>()
        .toSet();
    final ref = await _pickMetric(
      excludeRefs: usedRefs,
      currentRef: item.metricRef,
      months: HomeTrendSettings.months,
    );
    if (ref == null) return;
    final newOrder = [
      for (final i in order)
        i == item
            ? HomeLayoutItem(HomeWidgetId.metricTrend, metricRef: ref)
            : i,
    ];
    await _persistOrder(newOrder);
  }

  Future<void> _addWidgetMenu() async {
    final order = _currentOrder;
    final hiddenFixed = HomeWidgetId.values
        .where(
          (id) =>
              id != HomeWidgetId.strengthTrends &&
              id != HomeWidgetId.metricTrend &&
              !order.any((i) => i.type == id),
        )
        .toList();
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
            for (final id in hiddenFixed)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(id.icon, color: AppColors.textSecondary),
                title: Text(id.label, style: AppText.bodyText),
                onTap: () => Navigator.pop(context, id),
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
      final exerciseId = await _pickLift(
        excludeIds: usedIds,
        currentId: null,
        months: HomeTrendSettings.months,
      );
      if (exerciseId == null) return;
      await _persistOrder([
        HomeLayoutItem(HomeWidgetId.strengthTrends, exerciseId: exerciseId),
        ...order,
      ]);
    } else if (picked == HomeWidgetId.metricTrend) {
      final usedRefs = order
          .where((i) => i.type == HomeWidgetId.metricTrend)
          .map((i) => i.metricRef)
          .whereType<String>()
          .toSet();
      final ref = await _pickMetric(
        excludeRefs: usedRefs,
        currentRef: null,
        months: HomeTrendSettings.months,
      );
      if (ref == null) return;
      await _persistOrder([
        HomeLayoutItem(HomeWidgetId.metricTrend, metricRef: ref),
        ...order,
      ]);
    } else {
      await _persistOrder([HomeLayoutItem(picked), ...order]);
    }
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

  Widget _buildSection(
    BuildContext context,
    HomeLayoutItem item,
    DateTime cutoff,
  ) {
    switch (item.type) {
      case HomeWidgetId.muscleStatus:
        return AppCard(child: MuscleStatusRow(statuses: _categoryStatuses));
      case HomeWidgetId.planner:
        return _buildPlannerCard(context);
      case HomeWidgetId.todoList:
        return const TodoListCard();
      case HomeWidgetId.weekRings:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('This Week', style: AppText.subHeader),
            const SizedBox(height: AppSpacing.standard),
            AppCard(
              child: WeekRings(
                stepsByDate: _stepsByDate,
                workoutDates: _workoutDates,
              ),
            ),
          ],
        );
      case HomeWidgetId.primedForGrowth:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('Primed for Growth', style: AppText.subHeader),
                const InfoTooltip(
                  glossaryKey: 'readiness',
                  title: 'Primed for Growth',
                  footer: ReadinessLegend(),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.standard),
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
      case HomeWidgetId.trainingSplit:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Training Split', style: AppText.subHeader),
            const SizedBox(height: AppSpacing.standard),
            AppCard(
              child: TrainingCompositionChart(compositions: _compositions),
            ),
          ],
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
        final points = sessions.reversed
            .where((s) => DateTime.parse(s.session.date).isAfter(cutoff))
            .map((s) => ChartPoint(DateTime.parse(s.session.date), s.bestE1rm))
            .where((p) => p.value > 0)
            .toList();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(exercise?.name ?? 'Strength Trend', style: AppText.subHeader),
            const SizedBox(height: AppSpacing.standard),
            if (exercise == null)
              AppCard(
                child: Text(
                  _editing
                      ? 'Tap the pencil above to choose a lift.'
                      : 'No lift chosen for this card yet.',
                  style: AppText.smallText,
                ),
              )
            else
              AppCard(
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
              ),
          ],
        );
      case HomeWidgetId.metricTrend:
        final info = _metricTrendInfo(item.metricRef, cutoff);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(info?.title ?? 'Metric Trend', style: AppText.subHeader),
            const SizedBox(height: AppSpacing.standard),
            AppCard(
              child: info == null
                  ? Text(
                      _editing
                          ? 'Tap the pencil above to choose a metric.'
                          : 'No metric chosen for this card yet.',
                      style: AppText.smallText,
                    )
                  : LabeledTrendChart(
                      points: info.points,
                      yLabelFormatter: info.yFormatter,
                      height: 130,
                    ),
            ),
          ],
        );
      case HomeWidgetId.hiit:
        return _buildHiitCard(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.accent),
      );
    }

    final now = DateTime.now();
    final months = HomeTrendSettings.months;
    final cutoff = DateTime(now.year, now.month - months, now.day);
    final order = _currentOrder;

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
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.edge),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final item in order) ...[
                      _buildSection(context, item, cutoff),
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
                  return Dismissible(
                    key: ValueKey(item.token),
                    direction: DismissDirection.endToStart,
                    onDismissed: (_) => _removeItem(item),
                    background: Container(
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.only(
                        right: AppSpacing.standard,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.accent.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(AppRadius.card),
                      ),
                      child: const Icon(
                        Icons.delete_outline,
                        color: AppColors.accent,
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.large),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: IgnorePointer(
                              // Caches each card's painted content as its own
                              // layer so dragging (which repositions/animates
                              // every other item) doesn't force expensive
                              // widgets — the body heatmap, chart painters —
                              // to repaint every frame; only the layer itself
                              // is transformed. This is what made drag/reorder
                              // feel choppy on heavier cards.
                              child: RepaintBoundary(
                                child: _buildSection(context, item, cutoff),
                              ),
                            ),
                          ),
                          // Pencil lives here, outside the IgnorePointer above
                          // — nesting it inside _buildSection's edit-mode
                          // pencil meant edit mode's own IgnorePointer was
                          // swallowing its taps.
                          if (item.type == HomeWidgetId.strengthTrends)
                            TapIcon(
                              icon: Icons.edit_outlined,
                              size: 20,
                              onTap: () => _editStrengthTrend(item),
                            ),
                          if (item.type == HomeWidgetId.metricTrend)
                            TapIcon(
                              icon: Icons.edit_outlined,
                              size: 20,
                              onTap: () => _editMetricTrend(item),
                            ),
                          ReorderableDragStartListener(
                            index: i,
                            child: const Padding(
                              padding: EdgeInsets.only(
                                left: AppSpacing.small,
                                top: AppSpacing.small,
                              ),
                              child: Icon(
                                Icons.drag_handle,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ),
                        ],
                      ),
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
