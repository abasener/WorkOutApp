import 'package:flutter/material.dart';
import 'package:flutter_body_heatmap/flutter_body_heatmap.dart';

import '../../data/models/bodyweight_entry.dart';
import '../../data/models/metric_entry.dart';
import '../../services/app_services.dart';
import '../../services/muscle_map.dart';
import '../../services/trend_engine.dart';
import '../../services/units.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_card.dart';
import '../../widgets/labeled_trend_chart.dart';
import '../quick_log/log_simple_metric_form.dart';
import '../quick_log/soreness_body_map_form.dart';
import 'cycle_detail_screen.dart';

const _dashboardHistoryDays =
    183; // ~6 months, per designFiles/05_SCREEN_metrics.md

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
  final Map<MetricType, List<MetricEntry>> _entries = {};
  List<MetricEntry> _allMetrics = [];
  List<BodyweightEntry> _bodyweight = [];
  int _cycleFlowDaysCount = 0;
  final Map<SorenessRegion, int> _latestSoreness = {};
  Map<String, double> _workoutDurationByDate = {};

  @override
  void initState() {
    super.initState();
    AppServices.reloadSignal.addListener(_load);
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
    final workoutDurationByDate = TrendEngine.workoutDurationMinutesByDate(liftSessions);

    final soreness = <SorenessRegion, int>{};
    for (final region in MuscleMap.sorenessRegionGroups.keys) {
      final latest = await AppServices.metrics.getLatest(
        MetricTypeKey.forSorenessRegion(region),
      );
      if (latest != null) soreness[region] = latest.value.round();
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
      _loading = false;
    });
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
  /// a separate dialog per region.
  Future<void> _editSorenessDay(String date) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => SorenessBodyMapForm(initialDate: DateTime.parse(date)),
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

  List<ChartPoint> _points(MetricType type, DateTime cutoff) {
    final entries = _entries[type] ?? [];
    return entries
        .where((e) => DateTime.parse(e.date).isAfter(cutoff))
        .map((e) => ChartPoint(DateTime.parse(e.date), e.value))
        .toList();
  }

  /// One point per date with any timed lift session — derived from
  /// `lift_sessions.started_at`/`completed_at`, not a manually-logged
  /// metric, so it's not in `_entries` alongside steps/sleep.
  List<ChartPoint> _workoutDurationPoints(DateTime cutoff) {
    return _workoutDurationByDate.entries
        .where((e) => DateTime.parse(e.key).isAfter(cutoff))
        .map((e) => ChartPoint(DateTime.parse(e.key), e.value))
        .toList()
      ..sort((a, b) => a.date.compareTo(b.date));
  }

  /// One dot per week (average of that week's entries) so no single raw
  /// bodyweight reading is ever directly exposed — see designFiles/00_UX_DESIGN.md.
  List<ChartPoint> _weeklyBodyweightPoints(DateTime cutoff) {
    final byWeek = <DateTime, List<double>>{};
    for (final e in _bodyweight) {
      final date = DateTime.parse(e.date);
      if (!date.isAfter(cutoff)) continue;
      final weekStart = date.subtract(Duration(days: date.weekday - 1));
      final key = DateTime(weekStart.year, weekStart.month, weekStart.day);
      byWeek.putIfAbsent(key, () => []).add(e.weight);
    }
    final points =
        byWeek.entries
            .map(
              (e) => ChartPoint(
                e.key,
                e.value.reduce((a, b) => a + b) / e.value.length,
              ),
            )
            .toList()
          ..sort((a, b) => a.date.compareTo(b.date));
    return points;
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.accent),
      );
    }
    final cutoff = DateTime.now().subtract(
      const Duration(days: _dashboardHistoryDays),
    );

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Metrics'),
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
        children: [_buildOverviewTab(cutoff), _buildDaysTab()],
      ),
    );
  }

  Widget _buildOverviewTab(DateTime cutoff) {
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.edge),
      children: [
        _metricCard(
          'Steps',
          _points(MetricType.steps, cutoff),
          showPrediction: true,
          trendWindowDays: 21,
        ),
        const SizedBox(height: AppSpacing.cardGap),
        _metricCard(
          'Sleep (hrs)',
          _points(MetricType.sleepHours, cutoff),
          trendWindowDays: 30,
        ),
        const SizedBox(height: AppSpacing.cardGap),
        _metricCard(
          'Workout Duration (min)',
          _workoutDurationPoints(cutoff),
          trendWindowDays: 30,
          yFormatter: (v) => '${v.round()}m',
        ),
        const SizedBox(height: AppSpacing.cardGap),
        AppCard(
          onTap: _openSorenessForm,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Soreness', style: AppText.bodyText),
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
                                muscle: MuscleData(
                                  intensity: entry.value / 5.0,
                                ),
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
                                muscle: MuscleData(
                                  intensity: entry.value / 5.0,
                                ),
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
        ),
        const SizedBox(height: AppSpacing.cardGap),
        _metricCard(
          'Weight (weekly avg)',
          _weeklyBodyweightPoints(cutoff),
          showPrediction: true,
          trendWindowDays: 42,
          yFormatter: (v) => Units.formatMaskable(v),
        ),
        const SizedBox(height: AppSpacing.cardGap),
        // Cycle card: deliberately nondescript, no preview chart, per
        // designFiles/00_UX_DESIGN.md privacy rules.
        AppCard(
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
              Text(
                '$_cycleFlowDaysCount days logged',
                style: AppText.smallText,
              ),
              const SizedBox(width: AppSpacing.small),
              const Icon(Icons.chevron_right, color: AppColors.textSecondary),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.xLarge),
      ],
    );
  }

  Widget _metricCard(
    String title,
    List<ChartPoint> points, {
    bool showPrediction = false,
    double trendWindowDays = 21,
    String Function(double)? yFormatter,
  }) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: AppText.bodyText),
          const SizedBox(height: AppSpacing.small),
          LabeledTrendChart(
            points: points,
            showPrediction: showPrediction,
            trendWindowDays: trendWindowDays,
            yLabelFormatter: yFormatter,
            height: 130,
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
      rows.add(_DayRow(
        date: e.date,
        sortKey: e.date,
        icon: Icons.balance,
        label: 'Weight',
        valueText: Units.formatMaskable(e.weight),
        onEdit: () => _editBodyweight(e),
      ));
    }

    // All soreness entries for a day collapse into one row (tag per region
    // touched that day) — tapping it reopens the full body-map sheet so
    // every region can be edited at once, rather than one row per region.
    final sorenessByDate = <String, List<MetricEntry>>{};
    for (final e in _allMetrics) {
      if (e.metricType.sorenessRegion != null) {
        sorenessByDate.putIfAbsent(e.date, () => []).add(e);
      }
    }
    for (final entry in sorenessByDate.entries) {
      final date = entry.key;
      final regions = {for (final e in entry.value) e.metricType.sorenessRegion!.label};
      final latestLoggedAt = entry.value
          .map((e) => e.loggedAt ?? e.date)
          .reduce((a, b) => a.compareTo(b) > 0 ? a : b);
      rows.add(_DayRow(
        date: date,
        sortKey: latestLoggedAt,
        icon: Icons.local_fire_department,
        label: 'Soreness',
        tags: regions.toList(),
        onEdit: () => _editSorenessDay(date),
      ));
    }

    for (final e in _allMetrics) {
      if (e.metricType.sorenessRegion != null) {
        continue;
      } else if (e.metricType == MetricType.steps) {
        rows.add(_DayRow(
          date: e.date,
          sortKey: e.loggedAt ?? e.date,
          icon: Icons.directions_walk,
          label: 'Steps',
          valueText: e.value.round().toString(),
          onEdit: () => _editSimpleMetric(SimpleMetricKind.steps, e),
        ));
      } else if (e.metricType == MetricType.sleepHours) {
        rows.add(_DayRow(
          date: e.date,
          sortKey: e.loggedAt ?? e.date,
          icon: Icons.bed,
          label: 'Sleep',
          valueText: '${e.value.toStringAsFixed(1)} hrs',
          onEdit: () => _editSimpleMetric(SimpleMetricKind.sleep, e),
        ));
      }
    }

    if (rows.isEmpty) {
      return Center(child: Text('No entries logged yet.', style: AppText.smallText));
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
          for (final row in byDate[date]!..sort((a, b) => a.sortKey.compareTo(b.sortKey)))
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
                    GestureDetector(
                      onTap: row.onEdit,
                      child: const Icon(Icons.edit_outlined,
                          size: 18, color: AppColors.textSecondary),
                    ),
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
