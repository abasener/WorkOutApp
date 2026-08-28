import 'package:flutter/material.dart';

import '../../data/models/cardio_entry.dart';
import '../../data/models/distance_unit.dart';
import '../../data/models/exercise.dart';
import '../../data/models/hiit_session.dart';
import '../../data/models/hiit_slot.dart';
import '../../data/models/lift_set.dart';
import '../../data/repositories/cardio_repository.dart';
import '../../data/repositories/lift_repository.dart';
import '../../services/app_services.dart';
import '../../services/cardio_units.dart';
import '../../services/number_display.dart';
import '../../services/units.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_card.dart';
import 'hiit_setup_screen.dart';

/// Shown once every round is finished — a review/edit pass over what was
/// actually done (the app assumes every target was hit exactly as set, so
/// this is where that gets corrected: dropped weight, cut a run short,
/// didn't finish an AMRAP's reps) plus notes, then Save writes the real
/// `LiftSet`/`CardioEntry` rows — one exercise, one session for the day,
/// one set/entry per round it appeared in, same as any other logged
/// session. See designFiles/12_SCREEN_hiit.md.
///
/// [isEditingExisting] — reached via the pencil on a HIIT block in the
/// Workouts tab, rather than fresh off finishing a workout: Save then
/// *replaces* the day's already-logged sets/entries for each exercise
/// instead of appending a second copy, and popping just returns to that tab
/// instead of unwinding all the way back to Home.
class HiitReportScreen extends StatefulWidget {
  final int sessionId;
  final bool isEditingExisting;
  const HiitReportScreen({
    super.key,
    required this.sessionId,
    this.isEditingExisting = false,
  });

  @override
  State<HiitReportScreen> createState() => _HiitReportScreenState();
}

class _HiitReportScreenState extends State<HiitReportScreen> {
  bool _loading = true;
  bool _saving = false;
  HiitSession? _session;
  List<HiitSlot> _slots = [];
  Map<int, Exercise> _exercisesById = {};
  final _notesController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final session = await AppServices.hiit.getSession(widget.sessionId);
    final slots = await AppServices.hiit.getSlotsForSession(widget.sessionId);
    final exercises = await AppServices.exercises.getAll();
    if (!mounted) return;
    setState(() {
      _session = session;
      _slots = slots;
      _exercisesById = {
        for (final e in exercises)
          if (e.id != null) e.id!: e,
      };
      _notesController.text = session?.notes ?? '';
      _loading = false;
    });
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final session = _session!;

    final byExercise = <int, List<HiitSlot>>{};
    for (final slot in _slots) {
      byExercise.putIfAbsent(slot.exerciseId, () => []).add(slot);
    }
    for (final entry in byExercise.entries) {
      final exercise = _exercisesById[entry.key];
      if (exercise == null) continue;
      final slotsForExercise = entry.value
        ..sort((a, b) => a.sequenceIndex.compareTo(b.sequenceIndex));
      if (exercise.equipmentTags.contains(ExerciseType.cardio)) {
        final newEntries = [
          for (final s in slotsForExercise)
            CardioEntry(
              sessionId: 0,
              entryNumber: 0,
              distanceCanonical: s.actualDistance,
              durationSeconds: s.actualTimeSeconds,
              load: s.actualLoad,
            ),
        ];
        // Re-editing an already-saved HIIT workout would otherwise append a
        // second copy of every set/entry — find the same-day session this
        // exercise already has (matched by date, same convention the
        // Workouts tab uses to group HIIT-produced sessions) and replace
        // its contents instead, same as any other logged-set edit.
        CardioSessionWithEntries? existing;
        for (final s in await AppServices.cardio.getSessionsForExercise(
          exercise.id!,
        )) {
          if (s.session.date == session.date) {
            existing = s;
            break;
          }
        }
        if (existing != null) {
          await AppServices.cardio.replaceEntries(
            existing.session.id!,
            newEntries,
          );
        } else {
          await AppServices.cardio.logSession(
            exerciseId: exercise.id!,
            date: session.date,
            entries: newEntries,
          );
        }
      } else {
        final newSets = [
          for (final s in slotsForExercise)
            LiftSet(
              sessionId: 0,
              setNumber: 0,
              reps: s.actualReps ?? 0,
              weight: s.actualWeight ?? 0,
            ),
        ];
        SessionWithSets? existing;
        for (final s in await AppServices.lifts.getSessionsForExercise(
          exercise.id!,
        )) {
          if (s.session.date == session.date) {
            existing = s;
            break;
          }
        }
        if (existing != null) {
          await AppServices.lifts.replaceSets(existing.session.id!, newSets);
        } else {
          await AppServices.lifts.logSession(
            exerciseId: exercise.id!,
            date: session.date,
            sets: newSets,
          );
        }
      }
    }

    for (final s in _slots) {
      await AppServices.hiit.updateSlot(s);
    }
    await AppServices.hiit.updateSession(
      session.copyWith(
        notes: _notesController.text.trim().isEmpty
            ? null
            : _notesController.text.trim(),
        clearNotes: _notesController.text.trim().isEmpty,
      ),
    );
    AppServices.signalReload();
    if (!mounted) return;
    if (widget.isEditingExisting) {
      Navigator.of(context).pop();
    } else {
      Navigator.of(context).popUntil((r) => r.isFirst);
    }
  }

  // Reopens setup pre-filled with this workout's exact routine (same
  // template `HiitActiveScreen._abort` uses to hand a routine back) so an
  // old HIIT workout — reached via the pencil edit in the Workouts tab — can
  // be run again with tweaks (add a rep, bump the weight) rather than
  // rebuilt from scratch. Entirely non-destructive: this session's own logged
  // data is untouched, a fresh session is created when the redo is started.
  Future<void> _redo() async {
    final seedSlots = List<HiitSlot>.from(_slots);
    final seedAutomatic = _session!.automatic;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            HiitSetupScreen(seedSlots: seedSlots, seedAutomatic: seedAutomatic),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading || _session == null) {
      return const Scaffold(
        backgroundColor: AppColors.background,
        body: Center(child: CircularProgressIndicator(color: AppColors.accent)),
      );
    }

    final byGroup = <int, List<int>>{};
    for (var i = 0; i < _slots.length; i++) {
      byGroup.putIfAbsent(_slots[i].groupIndex, () => []).add(i);
    }
    final groupIndices = byGroup.keys.toList()..sort();

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(
          widget.isEditingExisting ? 'Edit HIIT Workout' : 'Workout Complete',
        ),
        actions: [
          if (widget.isEditingExisting)
            IconButton(
              icon: const Icon(Icons.replay),
              tooltip: 'Redo this workout',
              onPressed: _redo,
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.edge),
        children: [
          Text(
            'Every target below is assumed hit. Adjust anything that '
            "didn't go exactly to plan before saving.",
            style: AppText.smallText,
          ),
          const SizedBox(height: AppSpacing.large),
          for (final g in groupIndices) ...[
            Text('Round ${g + 1}', style: AppText.label),
            const SizedBox(height: AppSpacing.small),
            for (final i in byGroup[g]!) _slotReport(i),
            const SizedBox(height: AppSpacing.standard),
          ],
          Text('Notes', style: AppText.label),
          const SizedBox(height: AppSpacing.small),
          TextField(
            controller: _notesController,
            style: AppText.bodyText,
            maxLines: 3,
            decoration: const InputDecoration(hintText: 'How did it go?'),
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
                  borderRadius: BorderRadius.circular(AppRadius.button),
                ),
              ),
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text('Save'),
            ),
          ),
          const SizedBox(height: AppSpacing.xLarge),
        ],
      ),
    );
  }

  Widget _slotReport(int index) {
    final slot = _slots[index];
    final exercise = _exercisesById[slot.exerciseId];
    final isCardio = slot.exerciseKind == HiitExerciseKind.cardio;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.standard),
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(exercise?.name ?? 'Exercise', style: AppText.bodyText),
            const SizedBox(height: AppSpacing.small),
            if (isCardio)
              _cardioActualEditor(index, exercise)
            else
              _liftActualEditor(index),
          ],
        ),
      ),
    );
  }

  Widget _liftActualEditor(int index) {
    final slot = _slots[index];
    final isAmrap = slot.targetType == HiitTargetType.amrap;
    return Row(
      children: [
        Expanded(
          child: TextFormField(
            initialValue: (slot.actualReps ?? 0).toString(),
            keyboardType: TextInputType.number,
            style: AppText.bodyText,
            decoration: InputDecoration(
              labelText: isAmrap ? 'Reps done (AMRAP)' : 'Reps',
            ),
            onChanged: (v) {
              final parsed = int.tryParse(v);
              if (parsed != null) {
                _slots[index] = slot.copyWith(actualReps: parsed);
              }
            },
          ),
        ),
        const SizedBox(width: AppSpacing.small),
        Expanded(
          child: TextFormField(
            initialValue: slot.actualWeight == null
                ? ''
                : NumberDisplay.trim(Units.displayValue(slot.actualWeight!)),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: AppText.bodyText,
            decoration: InputDecoration(labelText: 'Weight (${Units.suffix})'),
            onChanged: (v) {
              final entered = double.tryParse(v);
              if (entered != null) {
                _slots[index] = slot.copyWith(
                  actualWeight: Units.toLb(entered),
                );
              }
            },
          ),
        ),
      ],
    );
  }

  Widget _cardioActualEditor(int index, Exercise? exercise) {
    final slot = _slots[index];
    final unit = exercise?.cardioUnit ?? CardioUnits.defaultUnit;
    return Row(
      children: [
        Expanded(
          child: TextFormField(
            initialValue: slot.actualDistance == null
                ? ''
                : CardioUnits.fromCanonical(
                    slot.actualDistance!,
                    unit,
                  ).toStringAsFixed(unit == DistanceUnit.floors ? 0 : 2),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: AppText.bodyText,
            decoration: InputDecoration(labelText: 'Distance (${unit.suffix})'),
            onChanged: (v) {
              final entered = double.tryParse(v);
              if (entered != null) {
                _slots[index] = slot.copyWith(
                  actualDistance: CardioUnits.toCanonical(entered, unit),
                );
              }
            },
          ),
        ),
        const SizedBox(width: AppSpacing.small),
        Expanded(
          child: TextFormField(
            initialValue: slot.actualTimeSeconds == null
                ? ''
                : (slot.actualTimeSeconds! / 60).toStringAsFixed(1),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: AppText.bodyText,
            decoration: const InputDecoration(labelText: 'Time (min)'),
            onChanged: (v) {
              final entered = double.tryParse(v);
              if (entered != null) {
                _slots[index] = slot.copyWith(
                  actualTimeSeconds: (entered * 60).round(),
                );
              }
            },
          ),
        ),
        const SizedBox(width: AppSpacing.small),
        Expanded(
          child: TextFormField(
            initialValue: slot.actualLoad?.toString() ?? '',
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: AppText.bodyText,
            decoration: const InputDecoration(labelText: 'Resistance'),
            onChanged: (v) {
              final entered = double.tryParse(v);
              if (entered != null) {
                _slots[index] = slot.copyWith(actualLoad: entered);
              }
            },
          ),
        ),
      ],
    );
  }
}
