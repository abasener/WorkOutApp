import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../../widgets/time_frame_dropdown.dart';

/// Per-card settings for a Metrics Overview card — reached via its gear icon
/// in edit mode, only shown at all for a card type that actually has
/// settings (designFiles/05_SCREEN_metrics.md "Goals"): a time-frame
/// override (any card with a `LabeledTrendChart`) and, if the underlying
/// metric has a goal value set, whether this card's chart draws it.
///
/// [hasDailyToggle] is Weight-only: a deliberate, disclosed opt-in exception
/// to designFiles/00_UX_DESIGN.md's "never a raw daily reading" default for
/// bodyweight (2026-07-27, user's own explicit request) — defaults off
/// (weekly average, unchanged prior behavior) and only reachable through
/// this same edit-mode gear, not a casual toggle.
class MetricCardSettingsSheet extends StatefulWidget {
  final String title;
  final bool hasTimeFrame;
  final int? monthsOverride; // null = Default
  final bool hasGoal;
  final bool showGoal;
  final bool hasDailyToggle;
  final bool dailyView;

  const MetricCardSettingsSheet({
    super.key,
    required this.title,
    required this.hasTimeFrame,
    required this.monthsOverride,
    required this.hasGoal,
    required this.showGoal,
    this.hasDailyToggle = false,
    this.dailyView = false,
  });

  @override
  State<MetricCardSettingsSheet> createState() =>
      _MetricCardSettingsSheetState();
}

class _MetricCardSettingsSheetState extends State<MetricCardSettingsSheet> {
  late int _months = widget.monthsOverride ?? 0;
  late bool _showGoal = widget.showGoal;
  late bool _dailyView = widget.dailyView;

  void _save() {
    Navigator.pop(context, (
      _months == 0 ? null : _months,
      _showGoal,
      _dailyView,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
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
            Text('${widget.title} settings', style: AppText.subHeader),
            const SizedBox(height: AppSpacing.standard),
            if (widget.hasTimeFrame) ...[
              Text('Time frame', style: AppText.label),
              const SizedBox(height: AppSpacing.small),
              TimeFrameDropdown(
                value: _months,
                onChanged: (v) => setState(() => _months = v),
              ),
              const SizedBox(height: AppSpacing.standard),
            ],
            if (widget.hasGoal)
              Row(
                children: [
                  Icon(
                    _showGoal ? Icons.flag : Icons.outlined_flag,
                    size: 18,
                    color: _showGoal ? AppColors.good : AppColors.textSecondary,
                  ),
                  const SizedBox(width: AppSpacing.small),
                  Expanded(
                    child: Text(
                      'Show goal line on this chart',
                      style: AppText.bodyText,
                    ),
                  ),
                  Switch(
                    value: _showGoal,
                    activeThumbColor: AppColors.accent,
                    onChanged: (v) => setState(() => _showGoal = v),
                  ),
                ],
              ),
            if (widget.hasDailyToggle) ...[
              const SizedBox(height: AppSpacing.standard),
              Row(
                children: [
                  Icon(
                    _dailyView ? Icons.calendar_view_day : Icons.date_range,
                    size: 18,
                    color: AppColors.textSecondary,
                  ),
                  const SizedBox(width: AppSpacing.small),
                  Expanded(
                    child: Text(
                      _dailyView
                          ? 'Showing every daily log'
                          : 'Showing weekly averages',
                      style: AppText.bodyText,
                    ),
                  ),
                  Switch(
                    value: _dailyView,
                    activeThumbColor: AppColors.accent,
                    onChanged: (v) => setState(() => _dailyView = v),
                  ),
                ],
              ),
            ],
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
                onPressed: _save,
                child: const Text('Save'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
