import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../../data/models/metric_entry.dart';
import '../../data/repositories/lift_repository.dart';
import '../../services/app_services.dart';
import '../../services/cycle_analysis.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_card.dart';
import '../../widgets/simple_bar_chart.dart';

/// What can be overlaid on the calendar alongside the period-flow dots.
/// Colors deliberately reuse the same 5 categorical hues as the Training
/// Composition chart (blue/aqua/green/yellow/violet) — distinct from the
/// flow dots' red, and already validated to read well together.
enum CycleOverlay { none, sleep, steps, workout, intensity, prs }

extension on CycleOverlay {
  String get label {
    switch (this) {
      case CycleOverlay.none:
        return 'None';
      case CycleOverlay.sleep:
        return 'Sleep';
      case CycleOverlay.steps:
        return 'Steps';
      case CycleOverlay.workout:
        return 'Workout days';
      case CycleOverlay.intensity:
        return 'Intensity (avg RPE)';
      case CycleOverlay.prs:
        return 'PRs';
    }
  }

  Color get color {
    switch (this) {
      case CycleOverlay.none:
        return Colors.transparent;
      case CycleOverlay.sleep:
        return const Color(0xFF3987E5);
      case CycleOverlay.steps:
        return const Color(0xFF199E70);
      case CycleOverlay.workout:
        return const Color(0xFF008300);
      case CycleOverlay.intensity:
        return const Color(0xFFC98500);
      case CycleOverlay.prs:
        return const Color(0xFF9085E9);
    }
  }
}

/// Cycle tracking detail — reached only by tapping the nondescript Cycle
/// card on Metrics, never surfaced on Home. See designFiles/00_UX_DESIGN.md.
class CycleDetailScreen extends StatefulWidget {
  const CycleDetailScreen({super.key});

  @override
  State<CycleDetailScreen> createState() => _CycleDetailScreenState();
}

class _CycleDetailScreenState extends State<CycleDetailScreen> {
  bool _loading = true;
  Map<String, int> _flowByDate = {};
  CycleStats _stats = const CycleStats(periodLengths: [], cycleLengths: []);
  DateTime _focusedMonth = DateTime(DateTime.now().year, DateTime.now().month);

  CycleOverlay _overlay = CycleOverlay.none;
  Map<String, double> _overlayValues = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final flowEntries = await AppServices.cycle.getFlowEntries();
    if (!mounted) return;
    setState(() {
      _flowByDate = {
        for (final e in flowEntries)
          if (e.flowValue != null) e.date: e.flowValue!,
      };
      _stats = CycleAnalysis.compute(flowEntries);
      _loading = false;
    });
    await _loadOverlay();
  }

  String _fmtDate(DateTime d) => d.toIso8601String().substring(0, 10);

  bool _inFocusedMonth(DateTime d) =>
      d.year == _focusedMonth.year && d.month == _focusedMonth.month;

  Future<void> _loadOverlay() async {
    if (_overlay == CycleOverlay.none) {
      if (mounted) setState(() => _overlayValues = {});
      return;
    }

    final values = <String, double>{};

    switch (_overlay) {
      case CycleOverlay.none:
        break;
      case CycleOverlay.sleep:
      case CycleOverlay.steps:
        final type =
            _overlay == CycleOverlay.sleep ? MetricType.sleepHours : MetricType.steps;
        final entries = await AppServices.metrics.getByType(type);
        final inRange =
            entries.where((e) => _inFocusedMonth(DateTime.parse(e.date))).toList();
        if (inRange.isNotEmpty) {
          final minV = inRange.map((e) => e.value).reduce((a, b) => a < b ? a : b);
          final maxV = inRange.map((e) => e.value).reduce((a, b) => a > b ? a : b);
          final range = (maxV - minV).abs() < 1e-9 ? 1.0 : (maxV - minV);
          for (final e in inRange) {
            values[e.date] = ((e.value - minV) / range).clamp(0.0, 1.0);
          }
        }
      case CycleOverlay.workout:
        final workoutDates = await AppServices.lifts.getAllWorkoutDates();
        for (final d in workoutDates) {
          if (_inFocusedMonth(DateTime.parse(d))) values[d] = 1.0;
        }
      case CycleOverlay.intensity:
        final sessions = await AppServices.lifts.getAllSessions();
        final rpesByDate = <String, List<double>>{};
        for (final s in sessions) {
          if (!_inFocusedMonth(DateTime.parse(s.session.date))) continue;
          for (final set in s.sets) {
            if (set.rpe != null) {
              rpesByDate.putIfAbsent(s.session.date, () => []).add(set.rpe!);
            }
          }
        }
        for (final entry in rpesByDate.entries) {
          final avg = entry.value.reduce((a, b) => a + b) / entry.value.length;
          values[entry.key] = (avg / 10).clamp(0.0, 1.0);
        }
      case CycleOverlay.prs:
        final sessions = await AppServices.lifts.getAllSessions();
        final byExercise = <int, List<SessionWithSets>>{};
        for (final s in sessions) {
          byExercise.putIfAbsent(s.session.exerciseId, () => []).add(s);
        }
        for (final group in byExercise.values) {
          final sorted = [...group]..sort((a, b) => a.session.date.compareTo(b.session.date));
          var runningMax = 0.0;
          for (final s in sorted) {
            if (s.bestE1rm > runningMax) {
              if (_inFocusedMonth(DateTime.parse(s.session.date))) {
                values[s.session.date] = 1.0;
              }
              runningMax = s.bestE1rm;
            }
          }
        }
    }

    if (!mounted) return;
    setState(() => _overlayValues = values);
  }

  Future<void> _pickFlow(DateTime day) async {
    var selected = _flowByDate[_fmtDate(day)] ?? 0;
    final result = await showDialog<int>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: AppColors.surfaceRaised,
          title: Text(DateFormat('MMM d, yyyy').format(day), style: AppText.subHeader),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Flow (tap the last filled circle to clear)',
                  style: AppText.smallText),
              const SizedBox(height: AppSpacing.large),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(4, (i) {
                  final level = i + 1;
                  final filled = level <= selected;
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: GestureDetector(
                      onTap: () => setDialogState(
                          () => selected = selected == level ? 0 : level),
                      child: Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: filled ? AppColors.accent : Colors.transparent,
                          border: Border.all(color: AppColors.accent, width: 2),
                        ),
                      ),
                    ),
                  );
                }),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Cancel', style: AppText.bodyText),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, selected),
              child: const Text('Save', style: TextStyle(color: AppColors.accent)),
            ),
          ],
        ),
      ),
    );
    if (result == null) return;
    await AppServices.cycle.setFlow(_fmtDate(day), result);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: AppColors.background,
        body: Center(child: CircularProgressIndicator(color: AppColors.accent)),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Cycle')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.edge),
        children: [
          Row(
            children: [
              Expanded(
                child: AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Avg cycle length', style: AppText.label),
                      const SizedBox(height: AppSpacing.micro),
                      Text(
                        _stats.avgCycleLength == null
                            ? '—'
                            : '${_stats.avgCycleLength!.toStringAsFixed(0)} days',
                        style: AppText.subHeader,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.cardGap),
              Expanded(
                child: AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Avg period length', style: AppText.label),
                      const SizedBox(height: AppSpacing.micro),
                      Text(
                        _stats.avgPeriodLength == null
                            ? '—'
                            : '${_stats.avgPeriodLength!.toStringAsFixed(1)} days',
                        style: AppText.subHeader,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.large),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Period length', style: AppText.subHeader),
                    const SizedBox(height: AppSpacing.standard),
                    AppCard(
                      child: SimpleBarChart(
                        values: _stats.periodLengths.map((v) => v.toDouble()).toList(),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.cardGap),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Cycle length', style: AppText.subHeader),
                    const SizedBox(height: AppSpacing.standard),
                    AppCard(
                      child: SimpleBarChart(
                        values: _stats.cycleLengths.map((v) => v.toDouble()).toList(),
                        color: AppColors.warn,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.large),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left, color: AppColors.textSecondary),
                onPressed: () {
                  setState(() =>
                      _focusedMonth = DateTime(_focusedMonth.year, _focusedMonth.month - 1));
                  _loadOverlay();
                },
              ),
              Text(DateFormat('MMMM yyyy').format(_focusedMonth), style: AppText.subHeader),
              IconButton(
                icon: const Icon(Icons.chevron_right, color: AppColors.textSecondary),
                onPressed: () {
                  setState(() =>
                      _focusedMonth = DateTime(_focusedMonth.year, _focusedMonth.month + 1));
                  _loadOverlay();
                },
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.standard),
          DropdownButton<CycleOverlay>(
            value: _overlay,
            isExpanded: true,
            dropdownColor: AppColors.surfaceRaised,
            underline: Container(height: 1, color: AppColors.border),
            style: AppText.bodyText,
            items: CycleOverlay.values
                .map((o) => DropdownMenuItem(
                      value: o,
                      child: Row(
                        children: [
                          if (o != CycleOverlay.none) ...[
                            Container(
                              width: 10,
                              height: 10,
                              decoration:
                                  BoxDecoration(color: o.color, shape: BoxShape.circle),
                            ),
                            const SizedBox(width: AppSpacing.small),
                          ],
                          Text('Overlay: ${o.label}'),
                        ],
                      ),
                    ))
                .toList(),
            onChanged: (v) {
              if (v == null) return;
              setState(() => _overlay = v);
              _loadOverlay();
            },
          ),
          const SizedBox(height: AppSpacing.small),
          _buildCalendar(),
          const SizedBox(height: AppSpacing.xLarge),
        ],
      ),
    );
  }

  Widget _buildCalendar() {
    final firstOfMonth = DateTime(_focusedMonth.year, _focusedMonth.month);
    final daysInMonth = DateTime(_focusedMonth.year, _focusedMonth.month + 1, 0).day;
    final leadingBlanks = firstOfMonth.weekday % 7; // Sunday = 0

    const weekdayLabels = ['S', 'M', 'T', 'W', 'T', 'F', 'S'];

    return Column(
      children: [
        Row(
          children: weekdayLabels
              .map((l) => Expanded(
                    child: Center(child: Text(l, style: AppText.label)),
                  ))
              .toList(),
        ),
        const SizedBox(height: AppSpacing.small),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate:
              const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 7),
          itemCount: leadingBlanks + daysInMonth,
          itemBuilder: (context, index) {
            if (index < leadingBlanks) return const SizedBox.shrink();
            final day = DateTime(_focusedMonth.year, _focusedMonth.month, index - leadingBlanks + 1);
            final dateStr = _fmtDate(day);
            final flow = _flowByDate[dateStr];
            final isToday = dateStr == _fmtDate(DateTime.now());
            final overlayValue = _overlayValues[dateStr];

            return InkWell(
              onTap: () => _pickFlow(day),
              child: Container(
                margin: const EdgeInsets.all(1),
                decoration: BoxDecoration(
                  color: overlayValue != null
                      ? _overlay.color.withValues(alpha: 0.15 + overlayValue * 0.45)
                      : null,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      '${day.day}',
                      style: AppText.smallText.copyWith(
                        color: isToday ? AppColors.accent : AppColors.textPrimary,
                        fontWeight: isToday ? FontWeight.w700 : FontWeight.w400,
                      ),
                    ),
                    const SizedBox(height: 2),
                    if (flow != null && flow > 0)
                      Container(
                        width: 4.0 + flow * 2.0,
                        height: 4.0 + flow * 2.0,
                        decoration: const BoxDecoration(
                          color: AppColors.accent,
                          shape: BoxShape.circle,
                        ),
                      )
                    else
                      const SizedBox(height: 8),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}
