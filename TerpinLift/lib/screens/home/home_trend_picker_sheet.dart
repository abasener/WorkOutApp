import 'package:flutter/material.dart';

import '../../data/models/exercise.dart';
import '../../services/app_services.dart';
import '../../theme/app_theme.dart';

/// Lets the user pick exactly which lifts' trend charts show in Home's
/// "Strength Trends" section, and how many months of history each one
/// plots. Reached via the edit pencil next to that section's header.
class HomeTrendPickerSheet extends StatefulWidget {
  final List<Exercise> exercises;
  final Set<int> selectedIds;
  final int months;

  const HomeTrendPickerSheet({
    super.key,
    required this.exercises,
    required this.selectedIds,
    required this.months,
  });

  @override
  State<HomeTrendPickerSheet> createState() => _HomeTrendPickerSheetState();
}

class _HomeTrendPickerSheetState extends State<HomeTrendPickerSheet> {
  late final Set<int> _selected = {...widget.selectedIds};
  late final _monthsController = TextEditingController(text: widget.months.toString());
  bool _saving = false;

  @override
  void dispose() {
    _monthsController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final months = int.tryParse(_monthsController.text) ?? widget.months;
    await AppServices.setHomeTrendExerciseIds(_selected.toList());
    await AppServices.setHomeTrendMonths(months.clamp(1, 999));
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    // Pinned lifts (the ones actually trained regularly) surface first —
    // same ordering logic as the quick-log dropdown, just not filtered down
    // to only pinned since any lift can still be charted here.
    final sorted = [...widget.exercises]
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
            Text('Strength Trends', style: AppText.subHeader),
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
              'If a lift has less history than this, it just shows everything it has.',
              style: AppText.smallText,
            ),
            const SizedBox(height: AppSpacing.standard),
            Text('Lifts to chart', style: AppText.label),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: sorted.map((e) {
                  final selected = e.id != null && _selected.contains(e.id);
                  return CheckboxListTile(
                    value: selected,
                    onChanged: (v) {
                      if (e.id == null) return;
                      setState(() => v == true ? _selected.add(e.id!) : _selected.remove(e.id!));
                    },
                    activeColor: AppColors.accent,
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
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
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('Save'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
