import 'package:flutter/material.dart';

import '../../data/models/exercise.dart';
import '../../services/app_services.dart';
import '../../theme/app_theme.dart';

/// Add-or-edit sheet: pass [existing] to edit that exercise's name/categories/
/// YouTube link in place (updates rather than inserting) — added after a
/// seeded exercise's tags were found stale from before multi-category
/// support existed, with no way to fix it short of wiping all data.
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
  late final Set<ExerciseCategory> _categories = {
    ...?widget.existing?.categories,
  };
  bool _saving = false;

  bool get _isEditing => widget.existing != null;

  @override
  void dispose() {
    _nameController.dispose();
    _youtubeController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_nameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Name is required.')));
      return;
    }
    if (_categories.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Pick at least one category.')));
      return;
    }
    setState(() => _saving = true);
    final youtubeUrl = _youtubeController.text.trim().isEmpty
        ? null
        : _youtubeController.text.trim();

    if (_isEditing) {
      await AppServices.exercises.update(widget.existing!.copyWith(
        name: _nameController.text.trim(),
        categories: _categories.toList(),
        youtubeUrl: youtubeUrl,
      ));
    } else {
      final today = DateTime.now().toIso8601String().substring(0, 10);
      await AppServices.exercises.insert(Exercise(
        name: _nameController.text.trim(),
        categories: _categories.toList(),
        isSeeded: false,
        youtubeUrl: youtubeUrl,
        created: today,
      ));
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

  @override
  Widget build(BuildContext context) {
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
              TextField(
                controller: _nameController,
                style: AppText.bodyText,
                decoration: const InputDecoration(labelText: 'Name'),
              ),
              const SizedBox(height: AppSpacing.large),
              Text('Categories (pick one or more)', style: AppText.label),
              const SizedBox(height: AppSpacing.standard),
              Wrap(
                spacing: AppSpacing.small,
                runSpacing: AppSpacing.small,
                children: ExerciseCategory.values.map((c) {
                  final selected = _categories.contains(c);
                  return FilterChip(
                    label: Text(c.label),
                    selected: selected,
                    onSelected: (v) => setState(
                        () => v ? _categories.add(c) : _categories.remove(c)),
                    backgroundColor: AppColors.surface,
                    selectedColor: AppColors.accentDim,
                    labelStyle: TextStyle(
                        color: selected ? AppColors.accent : AppColors.textSecondary),
                    side: BorderSide(
                        color: selected ? AppColors.accent : AppColors.border),
                  );
                }).toList(),
              ),
              const SizedBox(height: AppSpacing.standard),
              TextField(
                controller: _youtubeController,
                style: AppText.bodyText,
                decoration:
                    const InputDecoration(labelText: 'YouTube form link (optional)'),
              ),
              const SizedBox(height: AppSpacing.large),
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
