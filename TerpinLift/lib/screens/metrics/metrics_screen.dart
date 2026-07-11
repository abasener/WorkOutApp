import 'package:flutter/material.dart';
import 'package:flutter_body_heatmap/flutter_body_heatmap.dart';

import '../../data/models/bodyweight_entry.dart';
import '../../data/models/exercise.dart';
import '../../data/models/metric_entry.dart';
import '../../services/app_services.dart';
import '../../services/muscle_map.dart';
import '../../services/units.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_card.dart';
import '../../widgets/labeled_trend_chart.dart';
import '../quick_log/soreness_body_map_form.dart';
import 'cycle_detail_screen.dart';

const _dashboardHistoryDays = 183; // ~6 months, per designFiles/05_SCREEN_metrics.md

class MetricsScreen extends StatefulWidget {
  const MetricsScreen({super.key});

  @override
  State<MetricsScreen> createState() => _MetricsScreenState();
}

class _MetricsScreenState extends State<MetricsScreen> {
  bool _loading = true;
  final Map<MetricType, List<MetricEntry>> _entries = {};
  List<BodyweightEntry> _bodyweight = [];
  int _cycleFlowDaysCount = 0;
  final Map<ExerciseCategory, int> _latestSoreness = {};

  @override
  void initState() {
    super.initState();
    AppServices.reloadSignal.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    AppServices.reloadSignal.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    final entries = <MetricType, List<MetricEntry>>{};
    for (final type in MetricType.values) {
      entries[type] = await AppServices.metrics.getByType(type);
    }
    final bodyweight = await AppServices.bodyweight.getAll();
    final flowEntries = await AppServices.cycle.getFlowEntries();

    final soreness = <ExerciseCategory, int>{};
    for (final category in MuscleMap.broadGroups.keys) {
      final latest = await AppServices.metrics
          .getLatest(MetricTypeKey.forSorenessCategory(category));
      if (latest != null) soreness[category] = latest.value.round();
    }

    if (!mounted) return;
    setState(() {
      _entries
        ..clear()
        ..addAll(entries);
      _bodyweight = bodyweight;
      _cycleFlowDaysCount = flowEntries.where((e) => (e.flowValue ?? 0) > 0).length;
      _latestSoreness
        ..clear()
        ..addAll(soreness);
      _loading = false;
    });
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
    final points = byWeek.entries
        .map((e) => ChartPoint(e.key, e.value.reduce((a, b) => a + b) / e.value.length))
        .toList()
      ..sort((a, b) => a.date.compareTo(b.date));
    return points;
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: AppColors.accent));
    }
    final cutoff = DateTime.now().subtract(const Duration(days: _dashboardHistoryDays));

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Metrics')),
      body: ListView(
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
                                    in MuscleMap.broadGroups[entry.key] ?? const <Muscle>[])
                                  muscle: MuscleData(intensity: entry.value / 5.0),
                            },
                            colors: const [AppColors.surfaceRaised, AppColors.muscleHigh],
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
                                    in MuscleMap.broadGroups[entry.key] ?? const <Muscle>[])
                                  muscle: MuscleData(intensity: entry.value / 5.0),
                            },
                            colors: const [AppColors.surfaceRaised, AppColors.muscleHigh],
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
            yFormatter: (v) => Units.format(v),
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
                const Icon(Icons.calendar_today_outlined,
                    color: AppColors.textSecondary, size: 20),
                const SizedBox(width: AppSpacing.standard),
                Expanded(child: Text('Cycle', style: AppText.bodyText)),
                Text('$_cycleFlowDaysCount days logged', style: AppText.smallText),
                const SizedBox(width: AppSpacing.small),
                const Icon(Icons.chevron_right, color: AppColors.textSecondary),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xLarge),
        ],
      ),
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
}
