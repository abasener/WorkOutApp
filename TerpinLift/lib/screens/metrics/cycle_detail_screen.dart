import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../../services/app_services.dart';
import '../../services/cycle_analysis.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_card.dart';
import '../../widgets/simple_bar_chart.dart';

/// Cycle tracking detail — reached only by tapping the nondescript Cycle
/// card on Metrics, never surfaced on Home. See designFiles/00_UX_DESIGN.md.
///
/// A metric-overlay dropdown (sleep/steps/workout days/intensity/PRs plotted
/// against the calendar) is planned but deliberately not built yet — noted
/// in designFiles/09_SCREEN_cycle_detail.md as a documented next step rather
/// than a half-built control here.
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
  }

  String _fmtDate(DateTime d) => d.toIso8601String().substring(0, 10);

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
                onPressed: () => setState(() => _focusedMonth =
                    DateTime(_focusedMonth.year, _focusedMonth.month - 1)),
              ),
              Text(DateFormat('MMMM yyyy').format(_focusedMonth), style: AppText.subHeader),
              IconButton(
                icon: const Icon(Icons.chevron_right, color: AppColors.textSecondary),
                onPressed: () => setState(() => _focusedMonth =
                    DateTime(_focusedMonth.year, _focusedMonth.month + 1)),
              ),
            ],
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
            final flow = _flowByDate[_fmtDate(day)];
            final isToday = _fmtDate(day) == _fmtDate(DateTime.now());
            return InkWell(
              onTap: () => _pickFlow(day),
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
            );
          },
        ),
      ],
    );
  }
}
