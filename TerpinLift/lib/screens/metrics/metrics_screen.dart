import 'package:flutter/material.dart';
import 'package:flutter_body_heatmap/flutter_body_heatmap.dart';

import '../../data/models/bodyweight_entry.dart';
import '../../data/models/custom_metric.dart';
import '../../data/models/custom_metric_entry.dart';
import '../../data/models/metric_entry.dart';
import '../../data/models/progress_photo.dart';
import '../../services/app_services.dart';
import '../../services/home_trend_settings.dart';
import '../../services/metric_chart_points.dart';
import '../../services/metric_layout_settings.dart';
import '../../services/muscle_map.dart';
import '../../services/trend_engine.dart';
import '../../services/units.dart';
import '../../services/user_profile.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_card.dart';
import '../../widgets/labeled_trend_chart.dart';
import '../../widgets/progress_photo_timeline.dart';
import '../../widgets/tap_icon.dart';
import '../quick_log/log_simple_metric_form.dart';
import '../quick_log/soreness_body_map_form.dart';
import 'custom_metric_builder_sheet.dart';
import 'custom_metric_entry_sheet.dart';
import 'custom_metric_history_sheet.dart';
import 'cycle_detail_screen.dart';
import 'metric_card_settings_sheet.dart';
import 'metric_history_sheet.dart';
import 'progress_photos_screen.dart';

class MetricsScreen extends StatefulWidget {
  const MetricsScreen({super.key});

  @override
  State<MetricsScreen> createState() => _MetricsScreenState();
}

class _MetricsScreenState extends State<MetricsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController = TabController(
    length: 2,
    vsync: this,
  );

  bool _loading = true;
  bool _editingMetrics = false;
  final Map<MetricType, List<MetricEntry>> _entries = {};
  List<MetricEntry> _allMetrics = [];
  List<BodyweightEntry> _bodyweight = [];
  int _cycleFlowDaysCount = 0;
  final Map<SorenessRegion, double> _latestSoreness = {};
  Map<String, double> _workoutDurationByDate = {};
  List<ProgressPhoto> _progressPhotos = [];
  List<CustomMetric> _customMetrics = [];
  final Map<int, List<CustomMetricEntry>> _customMetricEntries = {};

  @override
  void initState() {
    super.initState();
    AppServices.reloadSignal.addListener(_load);
    // Edit mode is Overview-only — rebuild so its AppBar actions (and any
    // active edit mode) drop away when the Days tab is showing instead.
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) setState(() {});
    });
    _load();
  }

  @override
  void dispose() {
    AppServices.reloadSignal.removeListener(_load);
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final entries = <MetricType, List<MetricEntry>>{};
    for (final type in MetricType.values) {
      entries[type] = await AppServices.metrics.getByType(type);
    }
    final allMetrics = await AppServices.metrics.getAll();
    final bodyweight = await AppServices.bodyweight.getAll();
    final flowEntries = await AppServices.cycle.getFlowEntries();
    final liftSessions = await AppServices.lifts.getAllSessions();
    final plannedSessions = await AppServices.workoutPlans.getAllSessions();
    final workoutDurationByDate = TrendEngine.workoutDurationMinutesByDate(
      liftSessions,
      plannedSessions: plannedSessions,
    );

    // The current (decayed) picture, whether or not anything was logged
    // today — same `effectiveSorenessLevel` the readiness engine uses, so
    // this card shows the same "what's actually sore right now" the heatmap
    // reasons about, not just whatever was last typed in. The Days tab below
    // stays raw/as-logged on purpose — that view's job is "what did I
    // actually report," not "what's the current estimate."
    final soreness = <SorenessRegion, double>{};
    for (final region in MuscleMap.sorenessRegionGroups.keys) {
      soreness[region] = await AppServices.metrics.effectiveSorenessLevel(
        region,
      );
    }

    final progressPhotos = await AppServices.progressPhotos.getAll();
    final customMetrics = await AppServices.customMetrics.getAllDefinitions();
    final customMetricEntries = <int, List<CustomMetricEntry>>{};
    for (final metric in customMetrics) {
      customMetricEntries[metric.id!] = await AppServices.customMetrics
          .getEntries(metric.id!);
    }

    if (!mounted) return;
    setState(() {
      _entries
        ..clear()
        ..addAll(entries);
      _allMetrics = allMetrics;
      _bodyweight = bodyweight;
      _cycleFlowDaysCount = flowEntries
          .where((e) => (e.flowValue ?? 0) > 0)
          .length;
      _latestSoreness
        ..clear()
        ..addAll(soreness);
      _workoutDurationByDate = workoutDurationByDate;
      _progressPhotos = progressPhotos;
      _customMetrics = customMetrics;
      _customMetricEntries
        ..clear()
        ..addAll(customMetricEntries);
      _loading = false;
    });
  }

  /// The "+" icon on a built-in metric card — same form the quick-log FAB
  /// uses, just skipping the FAB's type picker since the card already says
  /// which metric this is.
  Future<void> _logSimpleMetric(SimpleMetricKind kind) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => LogSimpleMetricForm(kind: kind),
    );
  }

  /// The notebook icon on every metric card — a popup listing just that
  /// metric's own entries (newest first), not a jump to the mixed Days tab.
  /// Less discoverable than a tab, but the user's own call: this is "the
  /// easy place to see all the exact numbers/tags" for one metric at a
  /// time, which the Days tab's everything-by-date layout doesn't give you.
  Future<void> _showMetricHistory(
    String title,
    List<MetricHistoryRow> rows,
  ) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => MetricHistorySheet(title: title, rows: rows),
    );
  }

  List<MetricHistoryRow> _stepsHistoryRows() =>
      (_entries[MetricType.steps] ?? [])
          .map(
            (e) => MetricHistoryRow(
              date: e.date,
              valueText: e.value.round().toString(),
              onEdit: () => _editSimpleMetric(SimpleMetricKind.steps, e),
            ),
          )
          .toList();

  List<MetricHistoryRow> _sleepHistoryRows() =>
      (_entries[MetricType.sleepHours] ?? [])
          .map(
            (e) => MetricHistoryRow(
              date: e.date,
              valueText: '${e.value.toStringAsFixed(1)} hrs',
              onEdit: () => _editSimpleMetric(SimpleMetricKind.sleep, e),
            ),
          )
          .toList();

  List<MetricHistoryRow> _weightHistoryRows() => _bodyweight
      .map(
        (e) => MetricHistoryRow(
          date: e.date,
          valueText: Units.formatMaskable(e.weight),
          onEdit: () => _editBodyweight(e),
        ),
      )
      .toList();

  /// Derived, not logged — no `onEdit` on any row, since there's no single
  /// entry behind a given date's number to correct (it's the planned-
  /// session span, or a sum of lift Track Time windows).
  List<MetricHistoryRow> _workoutDurationHistoryRows() => _workoutDurationByDate
      .entries
      .map(
        (e) => MetricHistoryRow(date: e.key, valueText: '${e.value.round()}m'),
      )
      .toList();

  String _sorenessTagLabel(MetricEntry e) =>
      '${e.metricType.sorenessRegion!.label} (${e.value.round()})';

  /// Groups every logged soreness entry by `(date, slot)` — **not** just by
  /// date — so an AM log and a PM log on the same date become two separate
  /// groups. This is what makes "edit the PM one" and "edit the AM one"
  /// actually distinct actions instead of both landing on whichever slot the
  /// edit form happened to default to. Legacy entries logged before the
  /// AM/PM feature existed (`timeSlot == null`) get their own group per
  /// date too, kept apart from any real AM/PM groups on that same date.
  List<_SorenessGroup> _sorenessGroupedBySlot() {
    final byKey = <String, _SorenessGroup>{};
    for (final e in _allMetrics) {
      if (e.metricType.sorenessRegion == null) continue;
      final key = '${e.date}|${e.timeSlot?.key ?? ''}';
      byKey
          .putIfAbsent(key, () => _SorenessGroup(e.date, e.timeSlot))
          .entries
          .add(e);
    }
    return byKey.values.toList();
  }

  /// Same per-`(date, slot)` grouping the Days tab uses for soreness, just
  /// rendered as this metric's own popup instead of mixed in with everything
  /// else logged that day.
  List<MetricHistoryRow> _sorenessHistoryRows() {
    return _sorenessGroupedBySlot()
        .map(
          (g) => MetricHistoryRow(
            date: g.date,
            valueText: g.slot?.key,
            tags: [for (final e in g.entries) _sorenessTagLabel(e)],
            onEdit: () => _editSorenessDay(g.date, g.slot),
          ),
        )
        .toList();
  }

  Future<void> _editSimpleMetric(
    SimpleMetricKind kind,
    MetricEntry entry,
  ) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => LogSimpleMetricForm(
        kind: kind,
        editingId: entry.id,
        initialValue: entry.value,
        initialDate: DateTime.parse(entry.date),
        initialLoggedAt: entry.loggedAt,
      ),
    );
  }

  Future<void> _editBodyweight(BodyweightEntry entry) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => LogSimpleMetricForm(
        kind: SimpleMetricKind.bodyweight,
        editingId: entry.id,
        initialValue: entry.weight,
        initialDate: DateTime.parse(entry.date),
      ),
    );
  }

  /// Opens the full body-map sheet pre-set to this day, so every region
  /// touched that day can be edited part-by-part in one place, rather than
  /// a separate dialog per region. [slot] pins the form to the exact AM/PM
  /// entry this row represents — without it, the form would fall back to
  /// its own default (AM) regardless of which slot was actually tapped,
  /// which is exactly the bug this fixes: editing "the PM one" needs to
  /// actually open the PM one, not silently land on a different, possibly
  /// empty slot. `null` for a legacy pre-AM/PM entry — nothing to pin to.
  Future<void> _editSorenessDay(String date, SorenessTimeSlot? slot) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => SorenessBodyMapForm(
        initialDate: DateTime.parse(date),
        initialSlot: slot,
      ),
    );
  }

  Future<void> _openSorenessForm() async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const SorenessBodyMapForm(),
    );
  }

  Future<void> _openProgressPhotos() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ProgressPhotoAlbumScreen()),
    );
    await _load();
  }

  Future<void> _addProgressPhoto() async {
    await showAddProgressPhotoSheet(context);
    await _load();
  }

  Future<void> _openCustomMetricBuilder() async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const CustomMetricBuilderSheet(),
    );
  }

  Future<void> _logCustomMetric(CustomMetric metric) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => CustomMetricEntrySheet(metric: metric),
    );
  }

  Future<void> _viewCustomMetricHistory(CustomMetric metric) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => CustomMetricHistorySheet(metric: metric),
    );
  }

  /// Days-tab pencil for a custom metric row — same entry sheet as logging
  /// a new value, just pre-filled and replacing the specific entry tapped.
  Future<void> _editCustomMetricEntry(
    CustomMetric metric,
    CustomMetricEntry entry,
  ) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) =>
          CustomMetricEntrySheet(metric: metric, editingEntry: entry),
    );
  }

  /// Editing an existing custom metric's definition doesn't exist as a
  /// general feature (kind/scaleMax/classLabels aren't safe to change once
  /// real entries exist) — this is a narrow, single-field exception for the
  /// one thing that is safe to change anytime: the optional goal. Blank
  /// clears it, same "empty is legitimate" convention as the Settings
  /// weight/sleep goal fields.
  Future<void> _editCustomMetricGoal(CustomMetric metric) async {
    final controller = TextEditingController(
      text: metric.goal == null ? '' : metric.formatValue(metric.goal!),
    );
    final entered = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceRaised,
        title: Text('Goal for ${metric.name}', style: AppText.subHeader),
        content: TextField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          autofocus: true,
          style: AppText.bodyText,
          decoration: const InputDecoration(hintText: 'Leave blank for none'),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: AppText.bodyText),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text(
              'Save',
              style: TextStyle(color: AppColors.accent),
            ),
          ),
        ],
      ),
    );
    if (entered == null) return;
    final trimmed = entered.trim();
    await AppServices.customMetrics.updateDefinition(
      CustomMetric(
        id: metric.id,
        name: metric.name,
        kind: metric.kind,
        scaleMax: metric.scaleMax,
        scaleIcon: metric.scaleIcon,
        classLabels: metric.classLabels,
        created: metric.created,
        allowMultiplePerDay: metric.allowMultiplePerDay,
        goal: trimmed.isEmpty ? null : double.tryParse(trimmed),
      ),
    );
    AppServices.signalReload();
  }

  Future<void> _deleteCustomMetric(CustomMetric metric) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceRaised,
        title: Text('Delete "${metric.name}"?', style: AppText.subHeader),
        content: Text(
          'This deletes every value logged for this metric too. This cannot be undone.',
          style: AppText.bodyText,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: AppText.bodyText),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Delete',
              style: TextStyle(color: AppColors.accent),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await AppServices.customMetrics.deleteDefinition(metric.id!);
    AppServices.signalReload();
    await _load();
  }

  List<ChartPoint> _customMetricPoints(CustomMetric metric, DateTime cutoff) =>
      MetricChartPoints.customMetric(
        _customMetricEntries[metric.id] ?? [],
        cutoff,
      );

  String Function(double)? _customMetricYFormatter(CustomMetric metric) =>
      MetricChartPoints.customYFormatter(metric);

  List<ChartPoint> _points(MetricType type, DateTime cutoff) =>
      MetricChartPoints.forEntries(_entries[type] ?? [], cutoff);

  /// Derived from `lift_sessions.started_at`/`completed_at`, not a
  /// manually-logged metric, so it's not in `_entries` alongside steps/sleep.
  List<ChartPoint> _workoutDurationPoints(DateTime cutoff) =>
      MetricChartPoints.workoutDuration(_workoutDurationByDate, cutoff);

  List<ChartPoint> _weeklyBodyweightPoints(DateTime cutoff) =>
      MetricChartPoints.weeklyBodyweight(_bodyweight, cutoff);

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.accent),
      );
    }
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Metrics'),
        actions: [
          if (_tabController.index == 0)
            IconButton(
              icon: Icon(_editingMetrics ? Icons.check : Icons.edit_outlined),
              tooltip: _editingMetrics ? 'Done editing' : 'Edit cards',
              onPressed: () =>
                  setState(() => _editingMetrics = !_editingMetrics),
            ),
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'New metric',
            onPressed: _openCustomMetricBuilder,
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppColors.accent,
          labelColor: AppColors.textPrimary,
          unselectedLabelColor: AppColors.textSecondary,
          tabs: const [
            Tab(text: 'Overview'),
            Tab(text: 'Days'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [_buildOverviewTab(), _buildDaysTab()],
      ),
    );
  }

  // ---- Overview tab card order/visibility ("edit mode," mirrors Home) ----

  List<MetricLayoutItem> get _defaultMetricOrder => [
    const MetricLayoutItem(MetricWidgetId.steps),
    const MetricLayoutItem(MetricWidgetId.sleep),
    const MetricLayoutItem(MetricWidgetId.workoutDuration),
    const MetricLayoutItem(MetricWidgetId.soreness),
    const MetricLayoutItem(MetricWidgetId.weight),
    if (UserProfile.gender == Gender.female)
      const MetricLayoutItem(MetricWidgetId.cycle),
    const MetricLayoutItem(MetricWidgetId.progressPhotos),
    for (final m in _customMetrics)
      if (m.id != null)
        MetricLayoutItem(MetricWidgetId.customMetric, customMetricId: m.id),
  ];

  /// Reconciles the persisted order against current reality: drops a
  /// `cycle` entry if the profile is no longer female (even if it was
  /// customized while female), drops a `customMetric` entry whose metric
  /// was actually deleted (not just hidden), and appends any custom metric
  /// created since the order was last saved so a brand-new metric doesn't
  /// silently vanish from the screen.
  List<MetricLayoutItem> get _currentMetricOrder {
    final base = MetricLayoutSettings.order ?? _defaultMetricOrder;
    final customIds = _customMetrics.map((m) => m.id).whereType<int>().toSet();
    final reconciled = base.where((i) {
      if (i.type == MetricWidgetId.cycle) {
        return UserProfile.gender == Gender.female;
      }
      if (i.type == MetricWidgetId.customMetric) {
        return customIds.contains(i.customMetricId);
      }
      return true;
    }).toList();
    final presentCustomIds = reconciled
        .where((i) => i.type == MetricWidgetId.customMetric)
        .map((i) => i.customMetricId)
        .toSet();
    for (final m in _customMetrics) {
      if (m.id != null && !presentCustomIds.contains(m.id)) {
        reconciled.add(
          MetricLayoutItem(MetricWidgetId.customMetric, customMetricId: m.id),
        );
      }
    }
    return reconciled;
  }

  Future<void> _persistMetricOrder(List<MetricLayoutItem> order) async {
    await AppServices.setMetricWidgetOrder(order);
    if (mounted) setState(() {});
  }

  Future<void> _reorderMetricCards(int oldIndex, int newIndex) async {
    final order = [..._currentMetricOrder];
    if (newIndex > oldIndex) newIndex -= 1;
    final item = order.removeAt(oldIndex);
    order.insert(newIndex, item);
    await _persistMetricOrder(order);
  }

  /// Toggles a card's hidden flag in place — replaces the old "hide removes
  /// it from the order, a separate popup re-adds it" scheme. A hidden card
  /// stays exactly where it was (still reorderable), just flagged; the only
  /// way to add a genuinely new card now is a new custom metric.
  Future<void> _toggleMetricCardHidden(MetricLayoutItem item) async {
    final order = [..._currentMetricOrder];
    final i = order.indexOf(item);
    if (i == -1) return;
    order[i] = item.copyWith(hidden: !item.hidden);
    await _persistMetricOrder(order);
  }

  /// This card's own history window — its `monthsOverride` if it has one,
  /// otherwise `HomeTrendSettings.months` (the "Default" the settings sheet
  /// shows, read live rather than copied at save time). `-1` (the "All
  /// time" sentinel, `metric_card_settings_sheet.dart`) maps to a cutoff far
  /// enough back to include everything without a special-cased "no cutoff"
  /// path through `MetricChartPoints`. Real month subtraction, same
  /// convention Home's trend cards already use — replaces the flat
  /// ~6-month day-count this screen used before every card could have its
  /// own window.
  DateTime _cutoffFor(MetricLayoutItem item) {
    final months = item.monthsOverride ?? HomeTrendSettings.months;
    if (months < 0) return DateTime(1970);
    final now = DateTime.now();
    return DateTime(now.year, now.month - months, now.day);
  }

  /// The goal value backing this card's type, if any is actually set —
  /// `null` for a type with no goal concept (workoutDuration) or one that
  /// simply hasn't had a goal configured yet. Steps always has one; see
  /// designFiles/05_SCREEN_metrics.md "Goals".
  double? _goalFor(MetricLayoutItem item) {
    switch (item.type) {
      case MetricWidgetId.steps:
        return UserProfile.stepsGoal.toDouble();
      case MetricWidgetId.sleep:
        return UserProfile.sleepGoalHours;
      case MetricWidgetId.weight:
        return UserProfile.weightGoalLb;
      case MetricWidgetId.customMetric:
        for (final m in _customMetrics) {
          if (m.id == item.customMetricId) {
            return m.kind == CustomMetricKind.number ? m.goal : null;
          }
        }
        return null;
      case MetricWidgetId.workoutDuration:
      case MetricWidgetId.soreness:
      case MetricWidgetId.cycle:
      case MetricWidgetId.progressPhotos:
        return null;
    }
  }

  Widget _buildMetricCard(MetricLayoutItem item) {
    final cutoff = _cutoffFor(item);
    final goal = item.showGoal ? _goalFor(item) : null;
    switch (item.type) {
      case MetricWidgetId.steps:
        return _metricCard(
          'Steps',
          _points(MetricType.steps, cutoff),
          showPrediction: true,
          trendWindowDays: 21,
          onAdd: () => _logSimpleMetric(SimpleMetricKind.steps),
          onHistory: () => _showMetricHistory('Steps', _stepsHistoryRows()),
          goal: goal,
        );
      case MetricWidgetId.sleep:
        return _metricCard(
          'Sleep (hrs)',
          _points(MetricType.sleepHours, cutoff),
          trendWindowDays: 30,
          onAdd: () => _logSimpleMetric(SimpleMetricKind.sleep),
          onHistory: () => _showMetricHistory('Sleep', _sleepHistoryRows()),
          goal: goal,
        );
      case MetricWidgetId.workoutDuration:
        // No "+" here. Workout Duration is derived (planned sessions /
        // lift Track Time), never manually logged, so there's nothing to
        // add. Notebook still applies, it just shows the computed number
        // per date, with no edit hook on any row.
        return _metricCard(
          'Workout Duration (min)',
          _workoutDurationPoints(cutoff),
          trendWindowDays: 30,
          yFormatter: (v) => '${v.round()}m',
          onHistory: () => _showMetricHistory(
            'Workout Duration',
            _workoutDurationHistoryRows(),
          ),
        );
      case MetricWidgetId.soreness:
        return _buildSorenessCard();
      case MetricWidgetId.weight:
        return _metricCard(
          'Weight (weekly avg)',
          _weeklyBodyweightPoints(cutoff),
          showPrediction: true,
          trendWindowDays: 42,
          yFormatter: (v) => Units.formatMaskable(v),
          onAdd: () => _logSimpleMetric(SimpleMetricKind.bodyweight),
          onHistory: () => _showMetricHistory('Weight', _weightHistoryRows()),
          goal: goal,
        );
      case MetricWidgetId.cycle:
        return _buildCycleCard();
      case MetricWidgetId.progressPhotos:
        return _buildProgressPhotosCard();
      case MetricWidgetId.customMetric:
        final metric = _customMetrics.firstWhere(
          (m) => m.id == item.customMetricId,
          orElse: () => _customMetrics.first,
        );
        return _buildCustomMetricCard(metric, cutoff, goal: goal);
    }
  }

  // Cycle card: deliberately nondescript, no preview chart, per
  // designFiles/00_UX_DESIGN.md privacy rules.
  Widget _buildCycleCard() {
    return AppCard(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const CycleDetailScreen()),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.calendar_today_outlined,
            color: AppColors.textSecondary,
            size: 20,
          ),
          const SizedBox(width: AppSpacing.standard),
          Expanded(child: Text('Cycle', style: AppText.bodyText)),
          Text('$_cycleFlowDaysCount days logged', style: AppText.smallText),
          const SizedBox(width: AppSpacing.small),
          const Icon(Icons.chevron_right, color: AppColors.textSecondary),
        ],
      ),
    );
  }

  Widget _buildSorenessCard() {
    return AppCard(
      onTap: _openSorenessForm,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Soreness', style: AppText.bodyText),
              const Spacer(),
              TapIcon(
                icon: Icons.menu_book_outlined,
                size: 20,
                onTap: () =>
                    _showMetricHistory('Soreness', _sorenessHistoryRows()),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.small),
          SizedBox(
            height: 140,
            width: double.infinity,
            child: Row(
              children: [
                Expanded(
                  child: AspectRatio(
                    aspectRatio: 724 / 1448,
                    child: BodyHeatmap(
                      side: BodySide.front,
                      data: {
                        for (final entry in _latestSoreness.entries)
                          for (final muscle
                              in MuscleMap.sorenessRegionGroups[entry.key] ??
                                  const <Muscle>[])
                            muscle: MuscleData(intensity: entry.value / 5.0),
                      },
                      colors: const [
                        AppColors.surfaceRaised,
                        AppColors.muscleHigh,
                      ],
                      bodyColor: AppColors.surfaceRaised,
                      borderColor: AppColors.textSecondary,
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
                        for (final entry in _latestSoreness.entries)
                          for (final muscle
                              in MuscleMap.sorenessRegionGroups[entry.key] ??
                                  const <Muscle>[])
                            muscle: MuscleData(intensity: entry.value / 5.0),
                      },
                      colors: const [
                        AppColors.surfaceRaised,
                        AppColors.muscleHigh,
                      ],
                      bodyColor: AppColors.surfaceRaised,
                      borderColor: AppColors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProgressPhotosCard() {
    return AppCard(
      onTap: _openProgressPhotos,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Progress Photos', style: AppText.bodyText),
              const Spacer(),
              TapIcon(
                icon: Icons.camera_alt_outlined,
                size: 20,
                onTap: _addProgressPhoto,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.small),
          ProgressPhotoTimeline(photos: _progressPhotos),
        ],
      ),
    );
  }

  Widget _buildCustomMetricCard(
    CustomMetric metric,
    DateTime cutoff, {
    double? goal,
  }) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(metric.name, style: AppText.bodyText),
              const Spacer(),
              TapIcon(
                icon: Icons.menu_book_outlined,
                size: 20,
                onTap: () => _viewCustomMetricHistory(metric),
              ),
              if (metric.kind == CustomMetricKind.number)
                TapIcon(
                  icon: metric.goal == null ? Icons.outlined_flag : Icons.flag,
                  size: 20,
                  onTap: () => _editCustomMetricGoal(metric),
                ),
              TapIcon(
                icon: Icons.add_circle_outline,
                size: 20,
                onTap: () => _logCustomMetric(metric),
              ),
              TapIcon(
                icon: Icons.delete_outline,
                size: 20,
                onTap: () => _deleteCustomMetric(metric),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.small),
          LabeledTrendChart(
            points: _customMetricPoints(metric, cutoff),
            yLabelFormatter: _customMetricYFormatter(metric),
            height: 130,
            goal: goal,
          ),
        ],
      ),
    );
  }

  Widget _buildOverviewTab() {
    final order = _currentMetricOrder;

    if (!_editingMetrics) {
      return ListView(
        padding: const EdgeInsets.all(AppSpacing.edge),
        children: [
          for (final item in order.where((i) => !i.hidden)) ...[
            _buildMetricCard(item),
            const SizedBox(height: AppSpacing.cardGap),
          ],
        ],
      );
    }

    return ReorderableListView(
      padding: const EdgeInsets.all(AppSpacing.edge),
      onReorder: _reorderMetricCards,
      children: [
        for (final item in order)
          Padding(
            key: ValueKey(item.stableKey),
            padding: const EdgeInsets.only(bottom: AppSpacing.cardGap),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: IgnorePointer(
                    child: Opacity(
                      // Hidden cards still fully render (same size/content),
                      // just dimmed — makes exactly what's being toggled
                      // visible instead of collapsing to a bare row, and
                      // keeps every card's edit-mode treatment consistent.
                      opacity: item.hidden ? 0.4 : 1.0,
                      child: _buildMetricCard(item),
                    ),
                  ),
                ),
                // Drag / show-hide / settings stacked in a column, not a
                // row, so the controls only ever cost one icon's worth of
                // width next to the card rather than squeezing it out —
                // see designFiles/00_UX_DESIGN.md "Tap targets" for the
                // shared TapIcon sizing this keeps.
                Column(
                  children: [
                    ReorderableDragStartListener(
                      index: order.indexOf(item),
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
                      onTap: () => _toggleMetricCardHidden(item),
                    ),
                    if (item.type.hasTimeFrame)
                      TapIcon(
                        icon: Icons.settings_outlined,
                        onTap: () => _openMetricCardSettings(item),
                      ),
                  ],
                ),
              ],
            ),
          ),
      ],
    );
  }

  /// Card title for the settings sheet's heading — reuses each type's
  /// label, except a custom metric wants its own name, not the generic
  /// "Custom metric."
  String _titleForSettings(MetricLayoutItem item) {
    if (item.type == MetricWidgetId.customMetric) {
      for (final m in _customMetrics) {
        if (m.id == item.customMetricId) return m.name;
      }
    }
    return item.type.label;
  }

  Future<void> _openMetricCardSettings(MetricLayoutItem item) async {
    final order = [..._currentMetricOrder];
    final i = order.indexOf(item);
    if (i == -1) return;
    final result = await showModalBottomSheet<(int?, bool)>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => MetricCardSettingsSheet(
        title: _titleForSettings(item),
        hasTimeFrame: item.type.hasTimeFrame,
        monthsOverride: item.monthsOverride,
        hasGoal: _goalFor(item) != null,
        showGoal: item.showGoal,
      ),
    );
    if (result == null) return;
    final (monthsOverride, showGoal) = result;
    order[i] = item.copyWith(
      monthsOverride: () => monthsOverride,
      showGoal: showGoal,
    );
    await _persistMetricOrder(order);
  }

  /// [onAdd]/[onHistory] add the same notebook/"+" icon pair the custom
  /// metric cards have — `null` skips a given icon (e.g. Workout Duration
  /// has no add form at all, it's derived, not logged). No trash icon here
  /// ever: unlike a custom metric, these built-in metric *types* can't be
  /// deleted, only individual entries can (via [_showMetricHistory]'s
  /// per-row edit hook).
  Widget _metricCard(
    String title,
    List<ChartPoint> points, {
    bool showPrediction = false,
    double trendWindowDays = 21,
    String Function(double)? yFormatter,
    VoidCallback? onAdd,
    VoidCallback? onHistory,
    double? goal,
  }) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(title, style: AppText.bodyText),
              if (onHistory != null || onAdd != null) const Spacer(),
              if (onHistory != null)
                TapIcon(
                  icon: Icons.menu_book_outlined,
                  size: 20,
                  onTap: onHistory,
                ),
              if (onAdd != null)
                TapIcon(icon: Icons.add_circle_outline, size: 20, onTap: onAdd),
            ],
          ),
          const SizedBox(height: AppSpacing.small),
          LabeledTrendChart(
            points: points,
            showPrediction: showPrediction,
            trendWindowDays: trendWindowDays,
            yLabelFormatter: yFormatter,
            height: 130,
            goal: goal,
          ),
        ],
      ),
    );
  }

  /// Days tab: every logged entry (bodyweight, steps, sleep, soreness — not
  /// cycle) grouped by date, most recent first, each with an edit pencil.
  /// Added after the user hit a wrong-value-typo they couldn't fix without
  /// this — mirrors the Lifts "Workouts" tab's day-grouped layout.
  Widget _buildDaysTab() {
    final rows = <_DayRow>[];
    for (final e in _bodyweight) {
      rows.add(
        _DayRow(
          date: e.date,
          sortKey: e.date,
          icon: Icons.balance,
          label: 'Weight',
          valueText: Units.formatMaskable(e.weight),
          onEdit: () => _editBodyweight(e),
        ),
      );
    }

    // A separate row per (date, slot) — an AM log and a PM log on the same
    // date are two different rows, each editable independently, rather than
    // one row mixing both together. This is the Days tab's whole point:
    // what was actually reported, as reported — no decay, no carrying a
    // value forward from another day (that's what the Overview soreness
    // card is for instead).
    for (final g in _sorenessGroupedBySlot()) {
      final latestLoggedAt = g.entries
          .map((e) => e.loggedAt ?? e.date)
          .reduce((a, b) => a.compareTo(b) > 0 ? a : b);
      rows.add(
        _DayRow(
          date: g.date,
          sortKey: latestLoggedAt,
          icon: Icons.local_fire_department,
          label: g.slot == null ? 'Soreness' : 'Soreness (${g.slot!.key})',
          tags: [for (final e in g.entries) _sorenessTagLabel(e)],
          onEdit: () => _editSorenessDay(g.date, g.slot),
        ),
      );
    }

    for (final e in _allMetrics) {
      if (e.metricType.sorenessRegion != null) {
        continue;
      } else if (e.metricType == MetricType.steps) {
        rows.add(
          _DayRow(
            date: e.date,
            sortKey: e.loggedAt ?? e.date,
            icon: Icons.directions_walk,
            label: 'Steps',
            valueText: e.value.round().toString(),
            onEdit: () => _editSimpleMetric(SimpleMetricKind.steps, e),
          ),
        );
      } else if (e.metricType == MetricType.sleepHours) {
        rows.add(
          _DayRow(
            date: e.date,
            sortKey: e.loggedAt ?? e.date,
            icon: Icons.bed,
            label: 'Sleep',
            valueText: '${e.value.toStringAsFixed(1)} hrs',
            onEdit: () => _editSimpleMetric(SimpleMetricKind.sleep, e),
          ),
        );
      }
    }

    // Custom metric entries, one row per entry (not collapsed per day like
    // soreness — there's no shared multi-region sheet to reopen here, each
    // entry is its own independent thing to edit).
    for (final metric in _customMetrics) {
      for (final e
          in _customMetricEntries[metric.id] ?? const <CustomMetricEntry>[]) {
        rows.add(
          _DayRow(
            date: e.date,
            sortKey: e.loggedAt,
            icon: Icons.insights,
            label: metric.name,
            valueText: metric.formatValue(e.value),
            onEdit: () => _editCustomMetricEntry(metric, e),
          ),
        );
      }
    }

    if (rows.isEmpty) {
      return Center(
        child: Text('No entries logged yet.', style: AppText.smallText),
      );
    }

    final byDate = <String, List<_DayRow>>{};
    for (final r in rows) {
      byDate.putIfAbsent(r.date, () => []).add(r);
    }
    final dates = byDate.keys.toList()..sort((a, b) => b.compareTo(a));

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.edge),
      children: [
        for (final date in dates) ...[
          Text(date, style: AppText.subHeader),
          const SizedBox(height: AppSpacing.standard),
          for (final row
              in byDate[date]!..sort((a, b) => a.sortKey.compareTo(b.sortKey)))
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.cardGap),
              child: AppCard(
                child: Row(
                  children: [
                    Icon(row.icon, size: 20, color: AppColors.textSecondary),
                    const SizedBox(width: AppSpacing.standard),
                    Expanded(
                      child: Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: AppSpacing.small,
                        runSpacing: AppSpacing.micro,
                        children: [
                          Text(row.label, style: AppText.bodyText),
                          ...?row.tags?.map((t) => _SorenessTag(label: t)),
                        ],
                      ),
                    ),
                    if (row.valueText != null)
                      Text(row.valueText!, style: AppText.smallText),
                    const SizedBox(width: AppSpacing.standard),
                    TapIcon(icon: Icons.edit_outlined, onTap: row.onEdit),
                  ],
                ),
              ),
            ),
          const SizedBox(height: AppSpacing.standard),
        ],
        const SizedBox(height: AppSpacing.xLarge),
      ],
    );
  }
}

/// One `(date, slot)` bucket of soreness entries — see
/// `_MetricsScreenState._sorenessGroupedBySlot`.
class _SorenessGroup {
  final String date;
  final SorenessTimeSlot? slot;
  final List<MetricEntry> entries = [];
  _SorenessGroup(this.date, this.slot);
}

class _DayRow {
  final String date;
  final String sortKey;
  final IconData icon;
  final String label;
  final String? valueText;
  final List<String>? tags;
  final VoidCallback onEdit;

  _DayRow({
    required this.date,
    required this.sortKey,
    required this.icon,
    required this.label,
    this.valueText,
    this.tags,
    required this.onEdit,
  });
}

class _SorenessTag extends StatelessWidget {
  final String label;
  const _SorenessTag({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.surfaceRaised,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: AppColors.border),
      ),
      child: Text(label, style: AppText.smallText.copyWith(fontSize: 11)),
    );
  }
}
