import 'package:flutter/material.dart';

import '../../data/models/custom_metric.dart';
import '../../theme/app_theme.dart';

class MetricTrendOption {
  final String ref;
  final String label;
  final IconData icon;
  const MetricTrendOption(this.ref, this.label, this.icon);

  static List<MetricTrendOption> builtIns() => const [
    MetricTrendOption('steps', 'Steps', Icons.directions_walk),
    MetricTrendOption('sleep', 'Sleep', Icons.bed),
    MetricTrendOption('weight', 'Weight', Icons.balance),
    MetricTrendOption(
      'workoutDuration',
      'Workout Duration',
      Icons.timer_outlined,
    ),
  ];

  static List<MetricTrendOption> all(List<CustomMetric> customMetrics) => [
    ...builtIns(),
    for (final m in customMetrics)
      if (m.id != null)
        MetricTrendOption('custom:${m.id}', m.name, Icons.insights),
  ];
}

/// Picks which single metric a Metric Trend card tracks, plus the shared
/// "how far back" months setting (same global setting Strength Trend cards
/// use — one "months of history" knob for every Home trend card), and
/// (designFiles/05_SCREEN_metrics.md "Goals") whether this specific card
/// draws that metric's dashed goal line, if it has one. Reached per-card and
/// only from Home's edit mode.
class MetricTrendEditSheet extends StatefulWidget {
  final List<MetricTrendOption> options;
  final String? selectedRef;
  final int months;
  final bool showGoal;

  /// Only refs with an actual goal value set — steps always has one;
  /// weight/sleep only if set in Settings; a custom metric only if
  /// `kind == number` and its own goal is set. Anything not in here has
  /// nothing for the toggle to show, so the toggle itself doesn't appear.
  final Map<String, double> goalsByRef;

  const MetricTrendEditSheet({
    super.key,
    required this.options,
    required this.selectedRef,
    required this.months,
    required this.showGoal,
    required this.goalsByRef,
  });

  @override
  State<MetricTrendEditSheet> createState() => _MetricTrendEditSheetState();
}

class _MetricTrendEditSheetState extends State<MetricTrendEditSheet> {
  String? _selected;
  late bool _showGoal;
  late final _monthsController = TextEditingController(
    text: widget.months.toString(),
  );

  @override
  void initState() {
    super.initState();
    _selected = widget.selectedRef;
    _showGoal = widget.showGoal;
  }

  @override
  void dispose() {
    _monthsController.dispose();
    super.dispose();
  }

  void _save() {
    final selected = _selected;
    if (selected == null) return;
    final months = int.tryParse(_monthsController.text) ?? widget.months;
    final hasGoal = widget.goalsByRef.containsKey(selected);
    Navigator.pop(context, (
      selected,
      months.clamp(1, 999),
      hasGoal && _showGoal,
    ));
  }

  /// Only shown once a metric with an actual goal value is selected — a
  /// toggle with nothing to show would just be confusing. Icon swaps
  /// on/off, same two-state convention the visibility icons elsewhere in
  /// this app already use.
  Widget _goalToggleRow() {
    final hasGoal =
        _selected != null && widget.goalsByRef.containsKey(_selected);
    if (!hasGoal) return const SizedBox.shrink();
    return Row(
      children: [
        Icon(
          _showGoal ? Icons.flag : Icons.outlined_flag,
          size: 18,
          color: _showGoal ? AppColors.good : AppColors.textSecondary,
        ),
        const SizedBox(width: AppSpacing.small),
        Expanded(
          child: Text('Show goal line on this chart', style: AppText.bodyText),
        ),
        Switch(
          value: _showGoal,
          activeThumbColor: AppColors.accent,
          onChanged: (v) => setState(() => _showGoal = v),
        ),
      ],
    );
  }

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
            Text('Metric Trend', style: AppText.subHeader),
            const SizedBox(height: AppSpacing.standard),
            Row(
              children: [
                Expanded(
                  child: Text('Months of history', style: AppText.bodyText),
                ),
                SizedBox(
                  width: 70,
                  child: TextField(
                    controller: _monthsController,
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    style: AppText.bodyText,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.small),
            Text(
              'Applies to every trend card on Home, not just this one.',
              style: AppText.smallText,
            ),
            const SizedBox(height: AppSpacing.standard),
            Text('Which metric', style: AppText.label),
            Flexible(
              child: widget.options.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: AppSpacing.standard,
                      ),
                      child: Text(
                        'Every metric already has a card.',
                        style: AppText.smallText,
                      ),
                    )
                  : ListView(
                      shrinkWrap: true,
                      children: widget.options.map((o) {
                        final selected = o.ref == _selected;
                        return ListTile(
                          onTap: () => setState(() => _selected = o.ref),
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(o.icon, color: AppColors.textSecondary),
                          trailing: Icon(
                            selected
                                ? Icons.radio_button_checked
                                : Icons.radio_button_unchecked,
                            color: selected
                                ? AppColors.accent
                                : AppColors.textSecondary,
                          ),
                          title: Text(o.label, style: AppText.bodyText),
                        );
                      }).toList(),
                    ),
            ),
            const SizedBox(height: AppSpacing.standard),
            _goalToggleRow(),
            const SizedBox(height: AppSpacing.standard),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.button),
                  ),
                ),
                onPressed: _selected == null ? null : _save,
                child: const Text('Save'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
