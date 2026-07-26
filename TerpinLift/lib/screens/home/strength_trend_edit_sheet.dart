import 'package:flutter/material.dart';

import '../../data/models/exercise.dart';
import '../../services/home_layout_settings.dart';
import '../../theme/app_theme.dart';
import '../../widgets/time_frame_dropdown.dart';

/// Picks which single lift a Strength Trend card tracks, its own title
/// override, and its own time-frame override. One card, one lift — unlike
/// the old combined multi-select sheet, this is reached per-card and only
/// from Home's edit mode (see designFiles/02_SCREEN_home.md "Strength Trend
/// widgets"). Returns `(exerciseId, title, monthsOverride)` on Save.
class StrengthTrendEditSheet extends StatefulWidget {
  final List<Exercise> exercises;
  final int? selectedId;

  /// Lifts already tracked by another Strength Trend card — no longer
  /// excluded from the list (2026-07-26, duplicates are allowed, same as
  /// This Week), just dimmed so it's still obvious at a glance which ones
  /// already have a card elsewhere.
  final Set<int> alreadyUsedIds;
  final String defaultTitle;
  final String? currentTitle;
  final int? monthsOverride;

  const StrengthTrendEditSheet({
    super.key,
    required this.exercises,
    required this.selectedId,
    required this.alreadyUsedIds,
    required this.defaultTitle,
    required this.currentTitle,
    required this.monthsOverride,
  });

  @override
  State<StrengthTrendEditSheet> createState() => _StrengthTrendEditSheetState();
}

class _StrengthTrendEditSheetState extends State<StrengthTrendEditSheet> {
  int? _selected;
  late final _titleController = TextEditingController(
    text: widget.currentTitle ?? '',
  );
  late int _months = widget.monthsOverride ?? 0;

  @override
  void initState() {
    super.initState();
    _selected = widget.selectedId;
  }

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  void _save() {
    final selected = _selected;
    if (selected == null) return;
    // Title popped verbatim (may be ''); the caller resolves what that means
    // against `HomeLayoutItem.title`'s tri-state (see `_HomeScreenState._resolveTitle`).
    Navigator.pop(context, (
      selected,
      _titleController.text.trim(),
      _months == 0 ? null : _months,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final options = widget.exercises.where((e) => e.id != null).toList()
      ..sort((a, b) {
        if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
        return a.name.compareTo(b.name);
      });

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
            Text('Strength Trend', style: AppText.subHeader),
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
            Text('Which lift', style: AppText.label),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: options.map((e) {
                  final selected = e.id == _selected;
                  // Dimmed, not excluded, when another card already tracks
                  // this lift — still fully selectable (duplicates allowed).
                  final alreadyUsed =
                      widget.alreadyUsedIds.contains(e.id) && !selected;
                  return Opacity(
                    opacity: alreadyUsed ? 0.5 : 1.0,
                    child: ListTile(
                      onTap: () => setState(() => _selected = e.id),
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        selected
                            ? Icons.radio_button_checked
                            : Icons.radio_button_unchecked,
                        color: selected
                            ? AppColors.accent
                            : AppColors.textSecondary,
                      ),
                      title: Row(
                        children: [
                          Flexible(
                            child: Text(e.name, style: AppText.bodyText),
                          ),
                          if (e.pinned) ...[
                            const SizedBox(width: AppSpacing.micro),
                            const Icon(
                              Icons.push_pin,
                              size: 12,
                              color: AppColors.accent,
                            ),
                          ],
                        ],
                      ),
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
