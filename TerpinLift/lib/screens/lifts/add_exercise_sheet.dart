import 'package:flutter/material.dart';
import 'package:flutter_body_heatmap/flutter_body_heatmap.dart';

import '../../data/models/custom_goal.dart';
import '../../data/models/exercise.dart';
import '../../services/app_services.dart';
import '../../services/muscle_map.dart';
import '../../services/units.dart';
import '../../theme/app_theme.dart';
import 'muscle_selector_sheet.dart';

/// Add-or-edit sheet: pass [existing] to edit that exercise's name/tags/
/// muscles/YouTube link in place (updates rather than inserting) — added
/// after a seeded exercise's tags were found stale from before multi-category
/// support existed, with no way to fix it short of wiping all data.
///
/// **Add mode is a 3-step wizard** (name+tags, muscles, goal+notes) — added
/// once the entry point grew past a single-page form's worth of fields.
/// Everything is skippable except the name and picking at least one muscle
/// (the muscle pick is what used to only exist for the ~90 seeded lifts as
/// curated reference data — a custom exercise had no muscle data at all
/// otherwise). **Edit mode stays a single page** — a quick-tweak flow
/// shouldn't force a multi-step wizard for changing one field — but gains a
/// "Select Muscles" button so an existing exercise can get/update its own
/// fine-grained muscles the same way, and categories are no longer required
/// to save (same "skippable" relaxation as the add wizard).
///
/// **No movement-pattern picker** — that tag exists purely for the Workout
/// Planner's backend pattern-pool matching (`10_WORKOUT_PLANNER.md`), not as
/// a general-purpose exercise label, and the user doesn't want it settable
/// from the app at all (backend/seed-data edit only, an Excel-upload path
/// later). A custom exercise added here simply carries no pattern and won't
/// show up in the planner's pattern slots — editing an existing exercise
/// never touches its `patterns` either, whatever it already has stays as-is.
class AddExerciseSheet extends StatefulWidget {
  final Exercise? existing;
  const AddExerciseSheet({super.key, this.existing});

  @override
  State<AddExerciseSheet> createState() => _AddExerciseSheetState();
}

class _AddExerciseSheetState extends State<AddExerciseSheet> {
  late final _nameController =
      TextEditingController(text: widget.existing?.name ?? '');
  late final _youtubeController =
      TextEditingController(text: widget.existing?.youtubeUrl ?? '');
  late final _goalController = TextEditingController();
  late final _notesController = TextEditingController();
  late final Set<ExerciseCategory> _categories = {
    ...?widget.existing?.categories,
  };
  late final Set<ExerciseType> _equipmentTags = {
    ...?widget.existing?.equipmentTags,
  };
  // For an existing exercise, seed the picker with its *current* effective
  // muscles (`MuscleMap.musclesFor` — the user's own `targetMuscles` if set,
  // otherwise the curated fallback), not just the raw stored field. Otherwise
  // an older seeded lift that already shows a curated muscle diagram would
  // open to an empty-looking picker, which reads as "did I lose my data?"
  late Set<Muscle> _targetMuscles = widget.existing == null
      ? {}
      : MuscleMap.musclesFor(widget.existing!).toSet();
  bool _saving = false;

  /// Which wizard step is showing — only relevant in add mode (edit mode
  /// always renders every field on one page, ignoring this).
  int _step = 0;
  static const _stepCount = 3;

  bool get _isEditing => widget.existing != null;
  bool get _isBodyweightLift => _equipmentTags.contains(ExerciseType.bodyweight);

  @override
  void dispose() {
    _nameController.dispose();
    _youtubeController.dispose();
    _goalController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _pickMuscles() async {
    final result = await showModalBottomSheet<Set<Muscle>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => MuscleSelectorSheet(initialSelection: _targetMuscles),
    );
    if (result == null) return;
    setState(() => _targetMuscles = result);
    // Editing an already-saved exercise: this is its own standalone action,
    // not staged for a later Save button (there isn't one dedicated to just
    // muscles), so persist immediately.
    if (_isEditing) {
      final updated = widget.existing!.copyWith(targetMuscles: _targetMuscles.toList());
      await AppServices.exercises.update(updated);
      AppServices.signalReload();
    }
  }

  void _goNext() {
    if (_step == 0 && _nameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Name is required.')));
      return;
    }
    if (_step == 1 && _targetMuscles.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Pick at least one muscle this movement targets.')));
      return;
    }
    setState(() => _step += 1);
  }

  void _goBack() => setState(() => _step -= 1);

  Future<void> _submit() async {
    if (_nameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Name is required.')));
      return;
    }
    if (_targetMuscles.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Pick at least one muscle this movement targets.')));
      return;
    }
    setState(() => _saving = true);
    final youtubeUrl = _youtubeController.text.trim().isEmpty
        ? null
        : _youtubeController.text.trim();
    final notes = _notesController.text.trim().isEmpty ? null : _notesController.text.trim();

    if (_isEditing) {
      await AppServices.exercises.update(widget.existing!.copyWith(
        name: _nameController.text.trim(),
        categories: _categories.toList(),
        equipmentTags: _equipmentTags.toList(),
        // No `patterns:` — movement patterns are a backend/seed-data concept
        // for the Workout Planner's pattern-pool matching, not something the
        // app lets a user assign; omitting keeps whatever's already there.
        youtubeUrl: youtubeUrl,
        targetMuscles: _targetMuscles.toList(),
      ));
    } else {
      final today = DateTime.now().toIso8601String().substring(0, 10);
      // No `patterns:` here either — a custom exercise added from the app
      // simply doesn't participate in the Workout Planner's pattern slots;
      // assigning a pattern is a backend edit, not a user-facing one.
      final id = await AppServices.exercises.insert(Exercise(
        name: _nameController.text.trim(),
        categories: _categories.toList(),
        equipmentTags: _equipmentTags.toList(),
        isSeeded: false,
        youtubeUrl: youtubeUrl,
        created: today,
        notes: notes,
        targetMuscles: _targetMuscles.toList(),
      ));
      final goalEntered = double.tryParse(_goalController.text);
      if (goalEntered != null) {
        await AppServices.customGoals.insert(CustomGoal(
          exerciseId: id,
          targetReps: _isBodyweightLift ? goalEntered.round() : null,
          targetWeight: _isBodyweightLift ? null : Units.toLb(goalEntered),
          created: DateTime.now().toIso8601String(),
        ));
      }
    }
    AppServices.signalReload();
    if (mounted) Navigator.pop(context);
  }

  Future<void> _delete() async {
    final sessions =
        await AppServices.lifts.getSessionsForExercise(widget.existing!.id!);
    if (!mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceRaised,
        title: Text('Delete ${widget.existing!.name}?', style: AppText.subHeader),
        content: Text(
          sessions.isEmpty
              ? 'This exercise has no logged sessions. This cannot be undone.'
              : 'This also deletes all ${sessions.length} logged session'
                  '${sessions.length == 1 ? '' : 's'} for this exercise. This cannot be undone.',
          style: AppText.bodyText,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: AppText.bodyText),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: AppColors.accent)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await AppServices.exercises.delete(widget.existing!.id!);
    AppServices.signalReload();
    // Returns `true` so a caller showing this exercise's own detail screen
    // knows to pop itself too — the exercise it was showing no longer exists.
    if (mounted) Navigator.pop(context, true);
  }

  Widget _chipWrap<T>(List<T> values, Set<T> selected, String Function(T) labelOf) => Wrap(
        spacing: AppSpacing.small,
        runSpacing: AppSpacing.small,
        children: values.map((v) {
          final isSelected = selected.contains(v);
          return FilterChip(
            label: Text(labelOf(v)),
            selected: isSelected,
            onSelected: (sel) =>
                setState(() => sel ? selected.add(v) : selected.remove(v)),
            backgroundColor: AppColors.surface,
            selectedColor: AppColors.accentDim,
            labelStyle: TextStyle(
                color: isSelected ? AppColors.accent : AppColors.textSecondary),
            side: BorderSide(color: isSelected ? AppColors.accent : AppColors.border),
          );
        }).toList(),
      );

  Widget _nameAndTagsStep() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _nameController,
            style: AppText.bodyText,
            decoration: const InputDecoration(labelText: 'Name'),
          ),
          const SizedBox(height: AppSpacing.large),
          Text('Categories (optional)', style: AppText.label),
          const SizedBox(height: AppSpacing.standard),
          _chipWrap(ExerciseCategory.values, _categories, (c) => c.label),
          const SizedBox(height: AppSpacing.standard),
          Text('Equipment/type (optional)', style: AppText.label),
          const SizedBox(height: AppSpacing.standard),
          _chipWrap(ExerciseType.values, _equipmentTags, (t) => t.label),
          const SizedBox(height: AppSpacing.standard),
          TextField(
            controller: _youtubeController,
            style: AppText.bodyText,
            decoration: const InputDecoration(labelText: 'YouTube form link (optional)'),
          ),
        ],
      );

  Widget _musclesStep() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Muscles targeted', style: AppText.label),
          const SizedBox(height: AppSpacing.small),
          Text(
            'Pick every muscle this movement works — used for the Lift detail '
            'muscle diagram.',
            style: AppText.smallText,
          ),
          const SizedBox(height: AppSpacing.standard),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: AppColors.border),
              foregroundColor: AppColors.textPrimary,
              minimumSize: const Size(double.infinity, 44),
            ),
            onPressed: _pickMuscles,
            icon: const Icon(Icons.accessibility_new),
            label: const Text('Select Muscles'),
          ),
          const SizedBox(height: AppSpacing.standard),
          Text(
            _targetMuscles.isEmpty
                ? 'No muscles selected yet.'
                : _targetMuscles.map((m) => m.name).join(', '),
            style: AppText.smallText,
          ),
        ],
      );

  Widget _goalAndNotesStep() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Goal (optional)', style: AppText.label),
          const SizedBox(height: AppSpacing.standard),
          TextField(
            controller: _goalController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: AppText.bodyText,
            decoration: InputDecoration(
              labelText: _isBodyweightLift ? 'Target reps' : 'Target weight (${Units.suffix})',
            ),
          ),
          const SizedBox(height: AppSpacing.large),
          Text('Notes (optional)', style: AppText.label),
          const SizedBox(height: AppSpacing.standard),
          TextField(
            controller: _notesController,
            style: AppText.bodyText,
            maxLines: 4,
            minLines: 2,
            decoration: const InputDecoration(hintText: 'Form cues, reminders, whatever helps.'),
          ),
        ],
      );

  Widget _stepDots() => Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(_stepCount, (i) {
          final active = i == _step;
          return Container(
            margin: const EdgeInsets.symmetric(horizontal: 3),
            width: active ? 20 : 6,
            height: 6,
            decoration: BoxDecoration(
              color: active ? AppColors.accent : AppColors.border,
              borderRadius: BorderRadius.circular(3),
            ),
          );
        }),
      );

  @override
  Widget build(BuildContext context) {
    final wizardStep = switch (_step) {
      0 => _nameAndTagsStep(),
      1 => _musclesStep(),
      _ => _goalAndNotesStep(),
    };

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
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
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_isEditing ? 'Edit Movement' : 'Add Custom Movement',
                  style: AppText.subHeader),
              const SizedBox(height: AppSpacing.large),
              if (_isEditing) ...[
                _nameAndTagsStep(),
                const SizedBox(height: AppSpacing.large),
                _musclesStep(),
              ] else ...[
                _stepDots(),
                const SizedBox(height: AppSpacing.large),
                wizardStep,
              ],
              const SizedBox(height: AppSpacing.large),
              if (_isEditing)
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.accent,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppRadius.button)),
                    ),
                    onPressed: _saving ? null : _submit,
                    child: _saving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Text('Save'),
                  ),
                )
              else
                Row(
                  children: [
                    if (_step > 0)
                      Expanded(
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: AppColors.border),
                            foregroundColor: AppColors.textPrimary,
                            minimumSize: const Size(double.infinity, 52),
                          ),
                          onPressed: _saving ? null : _goBack,
                          child: const Text('Back'),
                        ),
                      ),
                    if (_step > 0) const SizedBox(width: AppSpacing.standard),
                    Expanded(
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.accent,
                          foregroundColor: Colors.white,
                          minimumSize: const Size(double.infinity, 52),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(AppRadius.button)),
                        ),
                        onPressed: _saving
                            ? null
                            : (_step < _stepCount - 1 ? _goNext : _submit),
                        child: _saving
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white))
                            : Text(_step < _stepCount - 1 ? 'Next' : 'Save'),
                      ),
                    ),
                  ],
                ),
              if (_isEditing) ...[
                const SizedBox(height: AppSpacing.standard),
                SizedBox(
                  width: double.infinity,
                  height: 44,
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: AppColors.accent),
                      foregroundColor: AppColors.accent,
                    ),
                    onPressed: _saving ? null : _delete,
                    child: const Text('Delete Exercise'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
