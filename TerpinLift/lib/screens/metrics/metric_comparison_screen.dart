import 'package:flutter/material.dart';

import '../../services/app_services.dart';
import '../../services/comparison_data_service.dart';
import '../../services/comparison_metric_options.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_card.dart';
import '../../widgets/comparison_month_calendar.dart';
import '../../widgets/dual_axis_trend_chart.dart';
import '../../widgets/metric_scatter_plot.dart';
import '../../widgets/time_frame_dropdown.dart';

/// Pick any two tracked metrics and see how they relate — a dual-axis line
/// chart over time, a scatter plot, and a size-encoded month calendar, all
/// fed by the same two selections and one shared time frame. See
/// `05_SCREEN_metrics.md` "Metric Comparison" for the full design writeup,
/// including why the line chart is a deliberate dual-axis exception to this
/// app's usual "never dual-axis" rule.
class MetricComparisonScreen extends StatefulWidget {
  const MetricComparisonScreen({super.key});

  @override
  State<MetricComparisonScreen> createState() => _MetricComparisonScreenState();
}

class _MetricComparisonScreenState extends State<MetricComparisonScreen> {
  bool _loading = true;
  List<ComparisonMetricOption> _options = [];

  ComparisonMetricOption? _optionA;
  ComparisonMetricOption? _optionB;
  int _months = 6;

  List<ComparisonEntry> _rawA = [];
  List<ComparisonEntry> _rawB = [];
  bool _loadingData = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final customMetrics = await AppServices.customMetrics.getAllDefinitions();
    if (!mounted) return;
    final options = ComparisonMetricOption.all(customMetrics);
    setState(() {
      _options = options;
      _optionA = options.isNotEmpty ? options[0] : null;
      _optionB = options.length > 1 ? options[1] : null;
      _loading = false;
    });
    await _loadData();
  }

  DateTime get _cutoff {
    if (_months < 0) return DateTime(1970);
    final now = DateTime.now();
    return DateTime(now.year, now.month - _months, now.day);
  }

  Future<void> _loadData() async {
    final a = _optionA;
    final b = _optionB;
    if (a == null || b == null) {
      setState(() {
        _rawA = [];
        _rawB = [];
      });
      return;
    }
    setState(() => _loadingData = true);
    final cutoff = _cutoff;
    final rawA = await ComparisonDataService.fetch(a.ref, cutoff);
    final rawB = await ComparisonDataService.fetch(b.ref, cutoff);
    if (!mounted) return;
    setState(() {
      _rawA = rawA;
      _rawB = rawB;
      _loadingData = false;
    });
  }

  Future<void> _pickOption({required bool forSlotA}) async {
    final excluded = forSlotA ? _optionB : _optionA;
    final picked = await showModalBottomSheet<ComparisonMetricOption>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ComparisonOptionPicker(
        options: _options,
        excluded: excluded,
        current: forSlotA ? _optionA : _optionB,
      ),
    );
    if (picked == null) return;
    setState(() {
      if (forSlotA) {
        _optionA = picked;
      } else {
        _optionB = picked;
      }
    });
    await _loadData();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: AppColors.background,
        body: Center(child: CircularProgressIndicator(color: AppColors.accent)),
      );
    }

    final a = _optionA;
    final b = _optionB;
    final aggA = ComparisonDataService.aggregateForCharts(
      _rawA,
      a?.isCategorical ?? false,
    );
    final aggB = ComparisonDataService.aggregateForCharts(
      _rawB,
      b?.isCategorical ?? false,
    );
    // Weight stays raw daily for the scatter plot and calendar (aggA/aggB
    // above) — only the line chart's trend gets weekly-smoothed, so it
    // reads like every other bodyweight chart while the other two plots
    // keep the exact-day correlation the comparison feature is for.
    final lineA = a?.ref == 'weight'
        ? ComparisonDataService.weeklyAverage(aggA)
        : aggA;
    final lineB = b?.ref == 'weight'
        ? ComparisonDataService.weeklyAverage(aggB)
        : aggB;
    final scatterPairs = ComparisonDataService.scatterPairs(_rawA, _rawB);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Compare Metrics')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.edge),
        children: [
          Row(
            children: [
              Expanded(
                child: _MetricPickerButton(
                  label: a?.label ?? 'Pick a metric',
                  color: comparisonSlotAColor,
                  onTap: () => _pickOption(forSlotA: true),
                ),
              ),
              const SizedBox(width: AppSpacing.standard),
              Expanded(
                child: _MetricPickerButton(
                  label: b?.label ?? 'Pick a metric',
                  color: comparisonSlotBColor,
                  onTap: () => _pickOption(forSlotA: false),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.standard),
          Text('Time frame', style: AppText.label),
          const SizedBox(height: AppSpacing.small),
          TimeFrameDropdown(
            value: _months,
            includeDefault: false,
            onChanged: (v) {
              setState(() => _months = v);
              _loadData();
            },
          ),
          const SizedBox(height: AppSpacing.large),
          if (a == null || b == null)
            Padding(
              padding: const EdgeInsets.symmetric(
                vertical: AppSpacing.standard,
              ),
              child: Text(
                'Pick two metrics to compare.',
                style: AppText.smallText,
              ),
            )
          else if (_loadingData)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: AppSpacing.xLarge),
              child: Center(
                child: CircularProgressIndicator(color: AppColors.accent),
              ),
            )
          else ...[
            Text('Over time', style: AppText.subHeader),
            const SizedBox(height: AppSpacing.standard),
            AppCard(
              child: DualAxisTrendChart(
                seriesA: DualAxisSeries(
                  points: lineA,
                  color: comparisonSlotAColor,
                  isCategorical: a.isCategorical,
                  categoryLabels: a.categoryLabels,
                ),
                seriesB: DualAxisSeries(
                  points: lineB,
                  color: comparisonSlotBColor,
                  isCategorical: b.isCategorical,
                  categoryLabels: b.categoryLabels,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.large),
            Text('Day by day', style: AppText.subHeader),
            const SizedBox(height: AppSpacing.standard),
            AppCard(
              child: MetricScatterPlot(
                pairs: scatterPairs,
                isCategoricalX: a.isCategorical,
                isCategoricalY: b.isCategorical,
                categoryLabelsX: a.categoryLabels,
                categoryLabelsY: b.categoryLabels,
                xLabelColor: comparisonSlotAColor,
                yLabelColor: comparisonSlotBColor,
              ),
            ),
            const SizedBox(height: AppSpacing.large),
            Text('By day, on a calendar', style: AppText.subHeader),
            const SizedBox(height: AppSpacing.standard),
            AppCard(
              child: ComparisonMonthCalendar(
                seriesA: CalendarSeries(
                  valuesByDate: {
                    for (final e in aggA)
                      e.date.toIso8601String().substring(0, 10): e.value,
                  },
                  color: comparisonSlotAColor,
                  isCategorical: a.isCategorical,
                ),
                seriesB: CalendarSeries(
                  valuesByDate: {
                    for (final e in aggB)
                      e.date.toIso8601String().substring(0, 10): e.value,
                  },
                  color: comparisonSlotBColor,
                  isCategorical: b.isCategorical,
                ),
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.xLarge),
        ],
      ),
    );
  }
}

/// Small pill button naming the current pick for one slot, tinted with that
/// slot's color — doubles as the one shared "legend" for this whole screen
/// (`05_SCREEN_metrics.md`), so no other plot needs its own key.
class _MetricPickerButton extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _MetricPickerButton({
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        side: BorderSide(color: color),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.standard,
          vertical: 12,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: AppSpacing.small),
          Expanded(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: AppText.bodyText,
            ),
          ),
        ],
      ),
    );
  }
}

class _ComparisonOptionPicker extends StatelessWidget {
  final List<ComparisonMetricOption> options;
  final ComparisonMetricOption? excluded;
  final ComparisonMetricOption? current;

  const _ComparisonOptionPicker({
    required this.options,
    required this.excluded,
    required this.current,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        decoration: const BoxDecoration(
          color: AppColors.surfaceRaised,
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppRadius.card),
          ),
        ),
        padding: EdgeInsets.fromLTRB(
          AppSpacing.edge,
          AppSpacing.standard,
          AppSpacing.edge,
          AppSpacing.standard + MediaQuery.of(context).padding.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Which metric', style: AppText.subHeader),
            const SizedBox(height: AppSpacing.standard),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: options.map((o) {
                  final isExcluded = o.ref == excluded?.ref;
                  final isSelected = o.ref == current?.ref;
                  return Opacity(
                    opacity: isExcluded ? 0.4 : 1.0,
                    child: ListTile(
                      enabled: !isExcluded,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(o.icon, color: AppColors.textSecondary),
                      trailing: Icon(
                        isSelected
                            ? Icons.radio_button_checked
                            : Icons.radio_button_unchecked,
                        color: isSelected
                            ? AppColors.accent
                            : AppColors.textSecondary,
                      ),
                      title: Text(o.label, style: AppText.bodyText),
                      onTap: isExcluded
                          ? null
                          : () => Navigator.pop(context, o),
                    ),
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
