import 'package:flutter/material.dart';

import '../../data/models/cardio_entry.dart';
import '../../data/models/distance_unit.dart';
import '../../data/models/exercise.dart';
import '../../data/repositories/cardio_repository.dart';
import '../../services/app_services.dart';
import '../../services/cardio_units.dart';
import '../../theme/app_theme.dart';
import '../../widgets/date_picker_field.dart';
import '../../widgets/exercise_picker_field.dart';
import '../../widgets/simple_timer_sheet.dart';

class _EditableCardioEntry {
  double? distanceValue; // entered/shown in `unit`, not canonical
  DistanceUnit unit;
  double? durationMinutes;
  double? load;
  double? rpe;
  _EditableCardioEntry({
    required this.unit,
    this.distanceValue,
    this.durationMinutes,
    this.load,
    this.rpe,
  });
}

/// Edit (or delete) an already-logged cardio session — the cardio
/// counterpart to `EditLiftSessionForm`, reachable via the pencil icon on a
/// session in Cardio detail's History.
class EditCardioSessionForm extends StatefulWidget {
  final Exercise exercise;
  final CardioSessionWithEntries sessionWithEntries;
  const EditCardioSessionForm({
    super.key,
    required this.exercise,
    required this.sessionWithEntries,
  });

  @override
  State<EditCardioSessionForm> createState() => _EditCardioSessionFormState();
}

class _EditCardioSessionFormState extends State<EditCardioSessionForm> {
  late DateTime _date = DateTime.parse(widget.sessionWithEntries.session.date);
  late final _notesController =
      TextEditingController(text: widget.sessionWithEntries.session.notes ?? '');
  // Existing entries display/edit in the exercise's *current* unit — only
  // the canonical number is stored, so there's no per-entry "originally
  // logged in X" to restore; this always normalizes to the exercise's one
  // designated unit, same as `CardioDetailScreen`.
  late final List<_EditableCardioEntry> _entries = widget.sessionWithEntries.entries
      .map((e) => _EditableCardioEntry(
            unit: widget.exercise.cardioUnit ?? CardioUnits.defaultUnit,
            distanceValue: e.distanceCanonical == null
                ? null
                : CardioUnits.fromCanonical(
                    e.distanceCanonical!, widget.exercise.cardioUnit ?? CardioUnits.defaultUnit),
            durationMinutes: e.durationSeconds == null ? null : e.durationSeconds! / 60,
            load: e.load,
            rpe: e.rpe,
          ))
      .toList();
  bool _saving = false;
  late Exercise _selectedExercise = widget.exercise;
  List<Exercise> _allCardioExercises = [];

  @override
  void initState() {
    super.initState();
    _loadExerciseOptions();
  }

  Future<void> _loadExerciseOptions() async {
    final all = await AppServices.exercises.getAll();
    final cardio = all.where((e) => e.equipmentTags.contains(ExerciseType.cardio)).toList();
    if (!mounted) return;
    setState(() {
      _allCardioExercises = cardio;
      _selectedExercise =
          cardio.firstWhere((e) => e.id == widget.exercise.id, orElse: () => widget.exercise);
    });
  }

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final dateStr = _date.toIso8601String().substring(0, 10);
    await AppServices.cardio.updateSession(widget.sessionWithEntries.session.copyWith(
      exerciseId: _selectedExercise.id,
      date: dateStr,
      notes: _notesController.text.trim().isEmpty ? null : _notesController.text.trim(),
      clearNotes: _notesController.text.trim().isEmpty,
    ));
    await AppServices.cardio.replaceEntries(
      widget.sessionWithEntries.session.id!,
      _entries
          .map((e) => CardioEntry(
                sessionId: 0,
                entryNumber: 0,
                distanceCanonical: e.distanceValue == null
                    ? null
                    : CardioUnits.toCanonical(e.distanceValue!, e.unit),
                durationSeconds: e.durationMinutes == null ? null : (e.durationMinutes! * 60).round(),
                load: e.load,
                rpe: e.rpe,
              ))
          .toList(),
    );
    AppServices.signalReload();
    if (mounted) Navigator.pop(context);
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceRaised,
        title: Text('Delete this session?', style: AppText.subHeader),
        content: Text(
          'This permanently deletes this logged session and all its efforts. This cannot be undone.',
          style: AppText.bodyText,
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false), child: Text('Cancel', style: AppText.bodyText)),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: AppColors.accent)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await AppServices.cardio.deleteSession(widget.sessionWithEntries.session.id!);
    AppServices.signalReload();
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        constraints: BoxConstraints(minHeight: screenHeight * 0.5, maxHeight: screenHeight * 0.85),
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
              Row(
                children: [
                  Text('Edit Session', style: AppText.subHeader),
                  const Spacer(),
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: AppColors.border),
                      foregroundColor: AppColors.textPrimary,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                    onPressed: () => SimpleTimerSheet.show(context),
                    child: const Icon(Icons.timer_outlined, size: 16),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.standard),
              if (_allCardioExercises.isEmpty)
                TextFormField(
                  enabled: false,
                  initialValue: _selectedExercise.name,
                  decoration: const InputDecoration(labelText: 'Exercise'),
                )
              else
                ExercisePickerField(
                  allOptions: _allCardioExercises,
                  defaultOptions: _allCardioExercises,
                  selected: _selectedExercise,
                  onSelected: (e) => setState(() => _selectedExercise = e),
                ),
              const SizedBox(height: AppSpacing.standard),
              DatePickerField(date: _date, onChanged: (d) => setState(() => _date = d)),
              const SizedBox(height: AppSpacing.large),
              ...List.generate(_entries.length, (i) => _buildEntryRow(i)),
              const SizedBox(height: AppSpacing.small),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: AppColors.border),
                  foregroundColor: AppColors.textPrimary,
                  minimumSize: const Size(double.infinity, 44),
                ),
                onPressed: () => setState(() => _entries.add(_EditableCardioEntry(
                      unit: _selectedExercise.cardioUnit ?? CardioUnits.defaultUnit,
                    ))),
                icon: const Icon(Icons.add),
                label: const Text('Add another effort'),
              ),
              const SizedBox(height: AppSpacing.large),
              TextField(
                controller: _notesController,
                style: AppText.bodyText,
                maxLines: 2,
                decoration: const InputDecoration(labelText: 'Notes (optional)'),
              ),
              const SizedBox(height: AppSpacing.large),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.button)),
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
                  child: const Text('Delete Session'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEntryRow(int i) {
    final entry = _entries[i];
    final unitOptions = entry.unit == DistanceUnit.floors
        ? [DistanceUnit.floors]
        : const [DistanceUnit.miles, DistanceUnit.km, DistanceUnit.meters];
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.standard),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Effort ${i + 1}', style: AppText.smallText),
              const SizedBox(width: AppSpacing.small),
              IconButton(
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: _entries.length <= 1 ? null : () => setState(() => _entries.removeAt(i)),
                icon: const Icon(Icons.remove_circle_outline, size: 18),
                color: AppColors.textSecondary,
                disabledColor: AppColors.border,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.small),
          Row(
            children: [
              Expanded(
                flex: 3,
                child: TextFormField(
                  key: ValueKey('distance_$i'),
                  initialValue: entry.distanceValue?.toStringAsFixed(2) ?? '',
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  style: AppText.bodyText,
                  decoration: const InputDecoration(labelText: 'Distance'),
                  onChanged: (v) => entry.distanceValue = double.tryParse(v),
                ),
              ),
              const SizedBox(width: AppSpacing.small),
              Expanded(
                flex: 2,
                child: DropdownButtonFormField<DistanceUnit>(
                  key: ValueKey('unit_$i'),
                  initialValue: entry.unit,
                  isExpanded: true,
                  items: unitOptions
                      .map((u) => DropdownMenuItem(value: u, child: Text(u.suffix)))
                      .toList(),
                  onChanged: unitOptions.length <= 1
                      ? null
                      : (u) => setState(() => entry.unit = u ?? entry.unit),
                ),
              ),
              const SizedBox(width: AppSpacing.small),
              Expanded(
                flex: 3,
                child: TextFormField(
                  key: ValueKey('duration_$i'),
                  initialValue: entry.durationMinutes?.toStringAsFixed(1) ?? '',
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  style: AppText.bodyText,
                  decoration: const InputDecoration(labelText: 'Duration (min)'),
                  onChanged: (v) => entry.durationMinutes = double.tryParse(v),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.small),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  key: ValueKey('load_$i'),
                  initialValue: entry.load?.toString() ?? '',
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  style: AppText.bodyText,
                  decoration: const InputDecoration(labelText: 'Resistance (optional)'),
                  onChanged: (v) => entry.load = double.tryParse(v),
                ),
              ),
              const SizedBox(width: AppSpacing.small),
              Expanded(
                child: TextFormField(
                  key: ValueKey('rpe_$i'),
                  initialValue: entry.rpe?.toStringAsFixed(0) ?? '',
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  style: AppText.bodyText,
                  decoration: const InputDecoration(labelText: 'Effort (1-10)'),
                  onChanged: (v) => entry.rpe = double.tryParse(v)?.clamp(1, 10).toDouble(),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
