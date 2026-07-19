import 'package:flutter/material.dart';

import '../../data/models/cardio_entry.dart';
import '../../data/models/distance_unit.dart';
import '../../data/models/exercise.dart';
import '../../services/app_services.dart';
import '../../services/cardio_units.dart';
import '../../theme/app_theme.dart';
import '../../widgets/date_picker_field.dart';
import '../../widgets/exercise_picker_field.dart';
import '../../widgets/simple_timer_sheet.dart';

class _PendingCardioEntry {
  double? distanceValue; // entered in `unit`, not canonical
  DistanceUnit unit;
  double? durationMinutes;
  double? load;
  double? rpe;
  _PendingCardioEntry({required this.unit});
}

/// Distance/duration/load entry form for a cardio exercise (Run, Ruck, Bike,
/// Rowing, Stairs, general cardio) — the cardio counterpart to `LogLiftForm`,
/// same overall shape (exercise picker, one row per logged effort, "add
/// another," notes, Done) but with cardio's own fields instead of
/// reps/weight. Each effort's distance can be entered in any unit compatible
/// with the exercise's own family (miles/km/meters convert to each other;
/// floors doesn't convert to anything) — converted to that exercise's
/// canonical storage on save. See designFiles/11_SCREEN_cardio.md.
class LogCardioForm extends StatefulWidget {
  final Exercise? preselected;
  const LogCardioForm({super.key, this.preselected});

  @override
  State<LogCardioForm> createState() => _LogCardioFormState();
}

class _LogCardioFormState extends State<LogCardioForm> {
  List<Exercise> _allCardioExercises = [];
  Exercise? _selected;
  List<_PendingCardioEntry> _entries = [];
  bool _saving = false;
  bool _loading = true;
  DateTime _date = DateTime.now();
  final _notesController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadExercises();
  }

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  DistanceUnit get _selectedUnit =>
      _selected?.cardioUnit ?? CardioUnits.defaultUnit;

  Future<void> _loadExercises() async {
    final all = await AppServices.exercises.getAll();
    final cardio = all
        .where((e) => e.equipmentTags.contains(ExerciseType.cardio))
        .toList();
    if (!mounted) return;
    setState(() {
      _allCardioExercises = cardio;
      _selected =
          widget.preselected != null &&
              cardio.any((e) => e.id == widget.preselected!.id)
          ? cardio.firstWhere((e) => e.id == widget.preselected!.id)
          : (cardio.isNotEmpty ? cardio.first : null);
      _entries = [_PendingCardioEntry(unit: _selectedUnit)];
      _loading = false;
    });
  }

  Future<void> _submit() async {
    if (_selected?.id == null) return;
    setState(() => _saving = true);
    final dateStr = _date.toIso8601String().substring(0, 10);
    await AppServices.cardio.logSession(
      exerciseId: _selected!.id!,
      date: dateStr,
      entries: _entries
          .map(
            (e) => CardioEntry(
              sessionId: 0,
              entryNumber: 0,
              distanceCanonical: e.distanceValue == null
                  ? null
                  : CardioUnits.toCanonical(e.distanceValue!, e.unit),
              durationSeconds: e.durationMinutes == null
                  ? null
                  : (e.durationMinutes! * 60).round(),
              load: e.load,
              rpe: e.rpe,
            ),
          )
          .toList(),
      notes: _notesController.text.trim().isEmpty
          ? null
          : _notesController.text.trim(),
    );
    AppServices.signalReload();
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        constraints: BoxConstraints(
          minHeight: screenHeight * 0.5,
          maxHeight: screenHeight * 0.85,
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
        child: _loading
            ? const Center(
                child: CircularProgressIndicator(color: AppColors.accent),
              )
            : SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Log Cardio', style: AppText.subHeader),
                    const SizedBox(height: AppSpacing.standard),
                    Row(
                      children: [
                        DatePickerField(
                          date: _date,
                          onChanged: (d) => setState(() => _date = d),
                        ),
                        const SizedBox(width: AppSpacing.small),
                        OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: AppColors.border),
                            foregroundColor: AppColors.textPrimary,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                          ),
                          onPressed: () => SimpleTimerSheet.show(context),
                          child: const Icon(Icons.timer_outlined, size: 16),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.standard),
                    if (_allCardioExercises.isEmpty)
                      Text(
                        'No cardio exercises yet. Add one from the Lifts tab '
                        '(tag it "Cardio" under Type) first.',
                        style: AppText.smallText,
                      )
                    else ...[
                      ExercisePickerField(
                        allOptions: _allCardioExercises,
                        defaultOptions: _allCardioExercises,
                        selected: _selected,
                        onSelected: (e) => setState(() => _selected = e),
                      ),
                      const SizedBox(height: AppSpacing.large),
                      ...List.generate(
                        _entries.length,
                        (i) => _buildEntryRow(i),
                      ),
                      const SizedBox(height: AppSpacing.small),
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: AppColors.border),
                          foregroundColor: AppColors.textPrimary,
                          minimumSize: const Size(double.infinity, 44),
                        ),
                        onPressed: () => setState(
                          () => _entries.add(
                            _PendingCardioEntry(unit: _selectedUnit),
                          ),
                        ),
                        icon: const Icon(Icons.add),
                        label: const Text('Add another effort'),
                      ),
                      const SizedBox(height: AppSpacing.large),
                      TextField(
                        controller: _notesController,
                        style: AppText.bodyText,
                        maxLines: 2,
                        decoration: const InputDecoration(
                          labelText: 'Notes (optional)',
                        ),
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
                              borderRadius: BorderRadius.circular(
                                AppRadius.button,
                              ),
                            ),
                          ),
                          onPressed: _saving ? null : _submit,
                          child: _saving
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Text('Done'),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildEntryRow(int i) {
    final entry = _entries[i];
    // Floors doesn't convert to/from a real distance, so a floors-unit
    // exercise's entries are always logged in floors — no unit choice to
    // make. Everything else picks among the mutually-convertible family.
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
                onPressed: _entries.length <= 1
                    ? null
                    : () => setState(() => _entries.removeAt(i)),
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
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
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
                      .map(
                        (u) =>
                            DropdownMenuItem(value: u, child: Text(u.suffix)),
                      )
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
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  style: AppText.bodyText,
                  decoration: const InputDecoration(
                    labelText: 'Duration (min)',
                  ),
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
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  style: AppText.bodyText,
                  decoration: const InputDecoration(
                    labelText: 'Resistance (optional)',
                  ),
                  onChanged: (v) => entry.load = double.tryParse(v),
                ),
              ),
              const SizedBox(width: AppSpacing.small),
              Expanded(
                child: TextFormField(
                  key: ValueKey('rpe_$i'),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  style: AppText.bodyText,
                  decoration: const InputDecoration(labelText: 'Effort (1-10)'),
                  onChanged: (v) =>
                      entry.rpe = double.tryParse(v)?.clamp(1, 10).toDouble(),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
