import 'package:flutter/material.dart';

import '../../data/models/exercise.dart';
import '../../theme/app_theme.dart';

/// Picks which single lift a Strength Trend card tracks, plus the shared
/// "how far back" months setting. One card, one lift — unlike the old
/// combined multi-select sheet, this is reached per-card and only from
/// Home's edit mode (see designFiles/02_SCREEN_home.md "Strength Trend
/// widgets"). Returns `(exerciseId, months)` on Save.
class StrengthTrendEditSheet extends StatefulWidget {
  final List<Exercise> exercises;
  final int? selectedId;
  final Set<int> excludeIds;
  final int months;

  const StrengthTrendEditSheet({
    super.key,
    required this.exercises,
    required this.selectedId,
    required this.excludeIds,
    required this.months,
  });

  @override
  State<StrengthTrendEditSheet> createState() => _StrengthTrendEditSheetState();
}

class _StrengthTrendEditSheetState extends State<StrengthTrendEditSheet> {
  int? _selected;
  late final _monthsController = TextEditingController(text: widget.months.toString());

  @override
  void initState() {
    super.initState();
    _selected = widget.selectedId;
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
    Navigator.pop(context, (selected, months.clamp(1, 999)));
  }

  @override
  Widget build(BuildContext context) {
    final options = widget.exercises
        .where((e) => e.id != null && (e.id == widget.selectedId || !widget.excludeIds.contains(e.id)))
        .toList()
      ..sort((a, b) {
        if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
        return a.name.compareTo(b.name);
      });

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
        decoration: const BoxDecoration(
          color: AppColors.surfaceRaised,
          borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.card)),
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
            Text('Strength Trend', style: AppText.subHeader),
            const SizedBox(height: AppSpacing.standard),
            Row(
              children: [
                Expanded(child: Text('Months of history', style: AppText.bodyText)),
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
              'Applies to every Strength Trend card, not just this one.',
              style: AppText.smallText,
            ),
            const SizedBox(height: AppSpacing.standard),
            Text('Which lift', style: AppText.label),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: options.map((e) {
                  final selected = e.id == _selected;
                  return ListTile(
                    onTap: () => setState(() => _selected = e.id),
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                      color: selected ? AppColors.accent : AppColors.textSecondary,
                    ),
                    title: Row(
                      children: [
                        Flexible(child: Text(e.name, style: AppText.bodyText)),
                        if (e.pinned) ...[
                          const SizedBox(width: AppSpacing.micro),
                          const Icon(Icons.push_pin, size: 12, color: AppColors.accent),
                        ],
                      ],
                    ),
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
                  shape:
                      RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.button)),
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
