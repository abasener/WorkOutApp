import 'package:flutter/material.dart';

import 'metric_trend_edit_sheet.dart';
import '../../theme/app_theme.dart';

/// Picks which goal-having metric a This Week ring card tracks. Simpler
/// than `MetricTrendEditSheet` — no "months of history" (rings always show
/// exactly 7 days) and no goal on/off toggle (a ring's whole point *is*
/// percent-to-goal, there's nothing to turn off). Only offers metrics that
/// currently have an actual goal value set — a ring with nothing to measure
/// against wouldn't mean anything, see `_HomeScreenState._goalsByRef`.
class WeekRingsEditSheet extends StatefulWidget {
  final List<MetricTrendOption> options;
  final String? selectedRef;

  const WeekRingsEditSheet({
    super.key,
    required this.options,
    required this.selectedRef,
  });

  @override
  State<WeekRingsEditSheet> createState() => _WeekRingsEditSheetState();
}

class _WeekRingsEditSheetState extends State<WeekRingsEditSheet> {
  String? _selected;

  @override
  void initState() {
    super.initState();
    _selected = widget.selectedRef;
  }

  void _save() {
    final selected = _selected;
    if (selected == null) return;
    Navigator.pop(context, selected);
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
            Text('This Week', style: AppText.subHeader),
            const SizedBox(height: AppSpacing.small),
            Text(
              'Only metrics with a goal set can drive a ring row — set one in '
              'Settings (weight/sleep) or on the metric itself (custom).',
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
                        'No goal-linked metrics yet.',
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
