import 'package:flutter/material.dart';

import '../../data/models/custom_metric.dart';
import '../../services/home_layout_settings.dart';
import '../../theme/app_theme.dart';
import '../../widgets/time_frame_dropdown.dart';

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

/// Picks which single metric a Metric Trend card tracks, its own title and
/// time-frame overrides, and (designFiles/05_SCREEN_metrics.md "Goals")
/// whether this specific card draws that metric's dashed goal line, if it
/// has one. Reached per-card and only from Home's edit mode.
class MetricTrendEditSheet extends StatefulWidget {
  final List<MetricTrendOption> options;
  final String? selectedRef;

  /// Refs already tracked by another Metric Trend card — no longer excluded
  /// from `options` (2026-07-26, duplicates are allowed, same as This Week),
  /// just dimmed so it's still obvious which ones already have a card.
  final Set<String> alreadyUsedRefs;
  final String defaultTitle;
  final String? currentTitle;
  final int? monthsOverride;
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
    required this.alreadyUsedRefs,
    required this.defaultTitle,
    required this.currentTitle,
    required this.monthsOverride,
    required this.showGoal,
    required this.goalsByRef,
  });

  @override
  State<MetricTrendEditSheet> createState() => _MetricTrendEditSheetState();
}

class _MetricTrendEditSheetState extends State<MetricTrendEditSheet> {
  String? _selected;
  late bool _showGoal;
  late int _months = widget.monthsOverride ?? 0;
  late final _titleController = TextEditingController(
    text: widget.currentTitle ?? '',
  );

  @override
  void initState() {
    super.initState();
    _selected = widget.selectedRef;
    _showGoal = widget.showGoal;
  }

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  void _save() {
    final selected = _selected;
    if (selected == null) return;
    final hasGoal = widget.goalsByRef.containsKey(selected);
    // Title popped verbatim (may be ''); the caller resolves what that means
    // against `HomeLayoutItem.title`'s tri-state (see `_HomeScreenState._resolveTitle`).
    Navigator.pop(context, (
      selected,
      _titleController.text.trim(),
      _months == 0 ? null : _months,
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
            Text('Title', style: AppText.label),
            const SizedBox(height: AppSpacing.small),
            TextField(
              controller: _titleController,
              style: AppText.bodyText,
              maxLength: homeWidgetTitleMaxLength,
              decoration: InputDecoration(
                hintText: widget.defaultTitle,
                counterText: '',
              ),
            ),
            const SizedBox(height: AppSpacing.standard),
            Text('Time frame', style: AppText.label),
            const SizedBox(height: AppSpacing.small),
            TimeFrameDropdown(
              value: _months,
              onChanged: (v) => setState(() => _months = v),
            ),
            const SizedBox(height: AppSpacing.standard),
            Text('Which metric', style: AppText.label),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: widget.options.map((o) {
                  final selected = o.ref == _selected;
                  // Dimmed, not excluded, when another card already tracks
                  // this metric — still fully selectable (duplicates
                  // allowed).
                  final alreadyUsed =
                      widget.alreadyUsedRefs.contains(o.ref) && !selected;
                  return Opacity(
                    opacity: alreadyUsed ? 0.5 : 1.0,
                    child: ListTile(
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
                    ),
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
