import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../data/models/distance_unit.dart';
import '../../data/models/exercise.dart';
import '../../data/models/hiit_routine.dart';
import '../../data/models/hiit_session.dart';
import '../../data/models/hiit_slot.dart';
import '../../services/app_services.dart';
import '../../services/cardio_units.dart';
import '../../services/plan_export_service.dart';
import '../../services/units.dart';
import '../../theme/app_theme.dart';
import '../../widgets/exercise_picker_field.dart';
import '../../widgets/plan_import_review_sheet.dart';
import '../../widgets/tap_icon.dart';
import 'hiit_active_screen.dart';
import 'hiit_presets.dart';

/// One exercise occurrence being built, before it's ever written to the DB —
/// see `HiitSlot` for what this becomes once the routine actually starts.
class _SlotDraft {
  Exercise exercise;
  HiitTargetType targetType;
  double? targetValue;
  double? weight;
  int? restAfterSeconds;

  _SlotDraft({
    required this.exercise,
    required this.targetType,
    this.targetValue,
    this.weight,
    this.restAfterSeconds,
  });

  bool get isCardio => exercise.equipmentTags.contains(ExerciseType.cardio);

  _SlotDraft clone() => _SlotDraft(
    exercise: exercise,
    targetType: targetType,
    targetValue: targetValue,
    weight: weight,
    restAfterSeconds: restAfterSeconds,
  );
}

/// One round — a set of exercises done back to back. See
/// designFiles/12_SCREEN_hiit.md.
class _GroupDraft {
  List<_SlotDraft> slots;
  _GroupDraft({required this.slots});
  _GroupDraft clone() =>
      _GroupDraft(slots: slots.map((s) => s.clone()).toList());
}

/// Build a HIIT routine — a list of rounds ("groups"), each a list of
/// exercises ("slots") done back to back, with a rest (or "Direct," no
/// rest) configurable between any two slots and between rounds. The "+"
/// under the last round duplicates it wholesale (same shape as adding
/// another logged set) so tweaking weight/reps for the next round doesn't
/// mean rebuilding it from scratch. Reachable from Home's HIIT card.
///
/// [seedSlots]/[seedAutomatic] pre-fill the editor from an already-built
/// routine — used when aborting an active session, which deletes it but
/// hands its exact shape back here so nothing has to be rebuilt from
/// scratch (see `HiitActiveScreen._abort`).
class HiitSetupScreen extends StatefulWidget {
  final List<HiitSlot>? seedSlots;
  final bool? seedAutomatic;
  const HiitSetupScreen({super.key, this.seedSlots, this.seedAutomatic});

  @override
  State<HiitSetupScreen> createState() => _HiitSetupScreenState();
}

class _HiitSetupScreenState extends State<HiitSetupScreen> {
  bool _loading = true;
  List<Exercise> _allExercises = [];
  List<HiitRoutine> _savedRoutines = [];
  bool _automatic = false;
  final List<_GroupDraft> _groups = [];
  bool _starting = false;

  @override
  void initState() {
    super.initState();
    _automatic = widget.seedAutomatic ?? false;
    _load();
  }

  Future<void> _load() async {
    final all = await AppServices.exercises.getAll();
    final savedRoutines = await AppServices.hiitRoutines.getAllRoutines();
    if (!mounted) return;
    setState(() {
      _allExercises = all;
      _savedRoutines = savedRoutines;
      final byId = {
        for (final e in all)
          if (e.id != null) e.id!: e,
      };
      final seed = widget.seedSlots;
      if (seed == null || seed.isEmpty) {
        _groups.add(_GroupDraft(slots: []));
      } else {
        final byGroup = <int, List<_SlotDraft>>{};
        for (final s in seed) {
          final exercise = byId[s.exerciseId];
          if (exercise == null) continue;
          byGroup
              .putIfAbsent(s.groupIndex, () => [])
              .add(
                _SlotDraft(
                  exercise: exercise,
                  targetType: s.targetType,
                  targetValue: s.targetValue,
                  weight: s.weight,
                  restAfterSeconds: s.restAfterSeconds,
                ),
              );
        }
        final orderedGroupIndices = byGroup.keys.toList()..sort();
        for (final g in orderedGroupIndices) {
          _groups.add(_GroupDraft(slots: byGroup[g]!));
        }
        if (_groups.isEmpty) _groups.add(_GroupDraft(slots: []));
      }
      _loading = false;
    });
  }

  void _addSlot(_GroupDraft group) {
    if (_allExercises.isEmpty) return;
    setState(() {
      final exercise = _allExercises.first;
      final isCardio = exercise.equipmentTags.contains(ExerciseType.cardio);
      group.slots.add(
        _SlotDraft(
          exercise: exercise,
          targetType: isCardio ? HiitTargetType.time : HiitTargetType.reps,
          targetValue: isCardio ? 60 : 10,
        ),
      );
    });
  }

  void _removeSlot(_GroupDraft group, _SlotDraft slot) =>
      setState(() => group.slots.remove(slot));

  void _duplicateLastGroup() =>
      setState(() => _groups.add(_groups.last.clone()));

  void _removeGroup(_GroupDraft group) {
    if (_groups.length <= 1) return;
    setState(() => _groups.remove(group));
  }

  bool get _canStart =>
      _groups.isNotEmpty && _groups.every((g) => g.slots.isNotEmpty);

  // Confirms first if the draft already has anything in it, since loading a
  // preset/saved routine replaces the whole thing rather than merging.
  Future<bool> _confirmReplaceIfNeeded(String name) async {
    final hasContent = _groups.any((g) => g.slots.isNotEmpty);
    if (!hasContent) return true;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceRaised,
        title: Text('Load "$name"?', style: AppText.subHeader),
        content: Text(
          'This replaces what you\'ve already built here.',
          style: AppText.bodyText,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: AppText.bodyText),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Replace',
              style: TextStyle(color: AppColors.accent),
            ),
          ),
        ],
      ),
    );
    return confirmed == true;
  }

  // Loads a hardcoded example routine (see hiit_presets.dart) as a starting
  // point to tweak from.
  Future<void> _applyPreset(HiitPreset preset) async {
    if (!await _confirmReplaceIfNeeded(preset.name)) return;

    final byName = {for (final e in _allExercises) e.name: e};
    final newGroups = <_GroupDraft>[];
    for (final round in preset.rounds) {
      final slots = <_SlotDraft>[];
      for (final s in round) {
        final exercise = byName[s.exerciseName];
        if (exercise == null) continue;
        slots.add(
          _SlotDraft(
            exercise: exercise,
            targetType: s.targetType,
            targetValue: s.targetValue,
            weight: s.weight,
            restAfterSeconds: s.restAfterSeconds,
          ),
        );
      }
      if (slots.isNotEmpty) newGroups.add(_GroupDraft(slots: slots));
    }
    if (newGroups.isEmpty) return;
    setState(() {
      _groups
        ..clear()
        ..addAll(newGroups);
      _automatic = preset.automatic;
    });
  }

  // Loads a user-saved routine (distinct from the hardcoded presets above —
  // see designFiles/12_SCREEN_hiit.md "Known gaps").
  Future<void> _applySavedRoutine(HiitRoutine routine) async {
    if (!await _confirmReplaceIfNeeded(routine.name)) return;
    final slots = await AppServices.hiitRoutines.getSlotsForRoutine(
      routine.id!,
    );
    final byId = {
      for (final e in _allExercises)
        if (e.id != null) e.id!: e,
    };
    final byGroup = <int, List<_SlotDraft>>{};
    for (final s in slots) {
      final exercise = byId[s.exerciseId];
      if (exercise == null) continue;
      byGroup
          .putIfAbsent(s.groupIndex, () => [])
          .add(
            _SlotDraft(
              exercise: exercise,
              targetType: s.targetType,
              targetValue: s.targetValue,
              weight: s.weight,
              restAfterSeconds: s.restAfterSeconds,
            ),
          );
    }
    final orderedGroupIndices = byGroup.keys.toList()..sort();
    final newGroups = [
      for (final g in orderedGroupIndices) _GroupDraft(slots: byGroup[g]!),
    ];
    if (newGroups.isEmpty) return;
    if (!mounted) return;
    setState(() {
      _groups
        ..clear()
        ..addAll(newGroups);
      _automatic = routine.automatic;
    });
  }

  // The deliberate, named "keep this" path — distinct from a preset/saved
  // routine load above (which replace the draft) and from Abort's unnamed
  // hand-back (which never persists anything). A name that already matches
  // a saved routine overwrites it (delete+reinsert its slots) rather than
  // creating a second entry with the same name.
  Future<void> _saveRoutine() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceRaised,
        title: Text('Save routine', style: AppText.subHeader),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: AppText.bodyText,
          decoration: const InputDecoration(hintText: 'Routine name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: AppText.bodyText),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text(
              'Save',
              style: TextStyle(color: AppColors.accent),
            ),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;

    final existing = await AppServices.hiitRoutines.getRoutineByName(name);
    if (existing != null) {
      if (!mounted) return;
      final overwrite = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppColors.surfaceRaised,
          title: Text('"$name" already exists', style: AppText.subHeader),
          content: Text(
            'Overwrite the saved routine with this one?',
            style: AppText.bodyText,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('Cancel', style: AppText.bodyText),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text(
                'Overwrite',
                style: TextStyle(color: AppColors.accent),
              ),
            ),
          ],
        ),
      );
      if (overwrite != true) return;
    }

    final routine = HiitRoutine(
      name: name,
      automatic: _automatic,
      created: DateTime.now().toIso8601String(),
    );
    // The target routine's id is only known once it's been inserted (a
    // fresh save) or was already known (an overwrite) — build the slot list
    // against that id rather than a placeholder.
    final routineId =
        existing?.id ?? await AppServices.hiitRoutines.insertRoutine(routine);

    var sequenceIndex = 0;
    final routineSlots = <HiitRoutineSlot>[
      for (var g = 0; g < _groups.length; g++)
        for (final s in _groups[g].slots)
          HiitRoutineSlot(
            hiitRoutineId: routineId,
            sequenceIndex: sequenceIndex++,
            groupIndex: g,
            exerciseId: s.exercise.id!,
            exerciseKind: s.isCardio
                ? HiitExerciseKind.cardio
                : HiitExerciseKind.lift,
            targetType: s.targetType,
            targetValue: s.targetValue,
            weight: s.weight,
            restAfterSeconds: s.restAfterSeconds,
          ),
    ];

    if (existing != null) {
      await AppServices.hiitRoutines.replaceRoutine(
        routineId,
        routine,
        routineSlots,
      );
    } else {
      await AppServices.hiitRoutines.insertRoutineSlots(routineSlots);
    }

    final savedRoutines = await AppServices.hiitRoutines.getAllRoutines();
    if (!mounted) return;
    setState(() => _savedRoutines = savedRoutines);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Saved "$name"')));
  }

  // Every routine the merged Load picker can show — the 3 hardcoded
  // presets plus every routine actually saved — one sheet each, named
  // after it. A friendly, human-editable format (real exercise names, not
  // ids), distinct from Settings' raw whole-app backup. See
  // plan_export_service.dart.
  Future<void> _exportRoutines() async {
    final path = await PlanExportService.exportHiitRoutines();
    if (!mounted) return;
    await SharePlus.instance.share(
      ShareParams(files: [XFile(path)], subject: 'TerrapinLift HIIT routines'),
    );
  }

  // Same "browse phone/Drive/wherever" native picker Settings' backup
  // import already uses (`SettingsScreen._import`), not a raw path field.
  Future<void> _importRoutines() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.any,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final picked = result.files.single;
    Uint8List? bytes = picked.bytes;
    if (bytes == null && picked.path != null) {
      bytes = await File(picked.path!).readAsBytes();
    }
    if (bytes == null || bytes.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not read that file.')),
      );
      return;
    }

    final parsed = await PlanExportService.parseHiitImport(bytes);
    if (!mounted) return;
    final rows = [
      for (final p in parsed)
        ImportReviewRow(
          name: p.name,
          alreadyExists: p.alreadyExists,
          unmatchedNames: p.unmatchedExerciseNames,
        ),
    ];
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => PlanImportReviewSheet(rows: rows),
    );
    if (confirmed != true) return;

    await PlanExportService.commitHiitImport([
      for (var i = 0; i < parsed.length; i++)
        HiitImportDecision(parsed: parsed[i], add: rows[i].add),
    ]);
    final savedRoutines = await AppServices.hiitRoutines.getAllRoutines();
    if (!mounted) return;
    setState(() => _savedRoutines = savedRoutines);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Import complete.')));
  }

  Future<void> _start() async {
    if (!_canStart || _starting) return;
    setState(() => _starting = true);

    final slots = <_SlotDraft>[];
    final groupIndexOf = <_SlotDraft, int>{};
    for (var g = 0; g < _groups.length; g++) {
      for (final s in _groups[g].slots) {
        slots.add(s);
        groupIndexOf[s] = g;
      }
    }

    final now = DateTime.now();
    final nowIso = now.toIso8601String();
    final firstSlot = slots.first;
    final firstIsReps = firstSlot.targetType == HiitTargetType.reps;
    final firstIsAmrap = firstSlot.targetType == HiitTargetType.amrap;
    final firstIsDistance = firstSlot.targetType == HiitTargetType.distance;

    final sessionId = await AppServices.hiit.insertSession(
      HiitSession(
        date: now.toIso8601String().substring(0, 10),
        startedAt: nowIso,
        status: HiitSessionStatus.active,
        automatic: _automatic,
        currentSequenceIndex: 0,
        currentPhase: HiitPhase.work,
        paused: false,
        phaseStartedAt: nowIso,
        phaseRemainingSeconds: firstIsReps
            ? null
            : (firstIsDistance ? 0 : firstSlot.targetValue),
        currentRepsRemaining: firstIsReps
            ? firstSlot.targetValue?.round()
            : (firstIsAmrap ? 0 : null),
      ),
    );

    await AppServices.hiit.insertSlots([
      for (var i = 0; i < slots.length; i++)
        HiitSlot(
          hiitSessionId: sessionId,
          sequenceIndex: i,
          groupIndex: groupIndexOf[slots[i]]!,
          exerciseId: slots[i].exercise.id!,
          exerciseKind: slots[i].isCardio
              ? HiitExerciseKind.cardio
              : HiitExerciseKind.lift,
          targetType: slots[i].targetType,
          targetValue: slots[i].targetValue,
          weight: slots[i].weight,
          restAfterSeconds: slots[i].restAfterSeconds,
        ),
    ]);
    AppServices.signalReload();

    if (!mounted) return;
    await Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => HiitActiveScreen(sessionId: sessionId)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Set Up HIIT'),
        actions: [
          IconButton(
            tooltip: 'Save this routine',
            icon: const Icon(Icons.save_outlined),
            onPressed: _canStart ? _saveRoutine : null,
          ),
          // Merged picker — hardcoded starting-point presets and the
          // user's own saved routines, sectioned. One shared "pick a saved
          // thing from a list" icon/interaction with the Workout Planner's
          // Switch Plan action (designFiles/12_SCREEN_hiit.md), rather than
          // two different metaphors for the same shape of action.
          PopupMenuButton<Object>(
            tooltip: 'Load a routine',
            icon: const Icon(Icons.list_alt_outlined),
            onSelected: (value) => value is HiitRoutine
                ? _applySavedRoutine(value)
                : _applyPreset(value as HiitPreset),
            itemBuilder: (context) => [
              if (_savedRoutines.isNotEmpty) ...[
                PopupMenuItem(
                  enabled: false,
                  child: Text('Your routines', style: AppText.label),
                ),
                for (final routine in _savedRoutines)
                  PopupMenuItem(value: routine, child: Text(routine.name)),
                const PopupMenuDivider(),
              ],
              PopupMenuItem(
                enabled: false,
                child: Text('Presets', style: AppText.label),
              ),
              for (final preset in hiitPresets)
                PopupMenuItem(value: preset, child: Text(preset.name)),
            ],
          ),
          IconButton(
            tooltip: 'Export saved routines',
            icon: const Icon(Icons.upload_outlined),
            onPressed: _exportRoutines,
          ),
          IconButton(
            tooltip: 'Import routines',
            icon: const Icon(Icons.download_outlined),
            onPressed: _importRoutines,
          ),
        ],
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.accent),
            )
          : ListView(
              padding: const EdgeInsets.all(AppSpacing.edge),
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _automatic
                            ? 'Moves on automatically'
                            : 'Tap Next between steps',
                        style: AppText.bodyText,
                      ),
                    ),
                    Switch(
                      value: _automatic,
                      activeThumbColor: AppColors.accent,
                      onChanged: (v) => setState(() => _automatic = v),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.small),
                Text(
                  _automatic
                      ? 'Timers and reached goals move you to the next step on their own.'
                      : "You tap Next when you're ready to move on. Timers still run for reference.",
                  style: AppText.smallText,
                ),
                const SizedBox(height: AppSpacing.large),
                for (var g = 0; g < _groups.length; g++) ...[
                  _groupCard(_groups[g], g),
                  if (g < _groups.length - 1) _interGroupRest(_groups[g]),
                ],
                const SizedBox(height: AppSpacing.standard),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: AppColors.border),
                    foregroundColor: AppColors.textPrimary,
                    minimumSize: const Size(double.infinity, 48),
                  ),
                  onPressed: _groups.last.slots.isEmpty
                      ? null
                      : _duplicateLastGroup,
                  icon: const Icon(Icons.add),
                  label: const Text('Add another round'),
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
                    onPressed: _canStart && !_starting ? _start : null,
                    child: _starting
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text('Start'),
                  ),
                ),
                const SizedBox(height: AppSpacing.xLarge),
              ],
            ),
    );
  }

  Widget _groupCard(_GroupDraft group, int index) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.standard),
      padding: const EdgeInsets.all(AppSpacing.cardPad),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Round ${index + 1}', style: AppText.subHeader),
              const Spacer(),
              if (_groups.length > 1)
                TapIcon(
                  icon: Icons.delete_outline,
                  onTap: () => _removeGroup(group),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.small),
          if (group.slots.isEmpty)
            Text('No exercises yet.', style: AppText.smallText)
          else
            for (var i = 0; i < group.slots.length; i++) ...[
              _slotEditor(group, group.slots[i]),
              if (i < group.slots.length - 1) _intraGroupRest(group.slots[i]),
              const SizedBox(height: AppSpacing.standard),
            ],
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: AppColors.border),
              foregroundColor: AppColors.textPrimary,
              minimumSize: const Size(double.infinity, 40),
            ),
            onPressed: () => _addSlot(group),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Add exercise'),
          ),
        ],
      ),
    );
  }

  Widget _slotEditor(_GroupDraft group, _SlotDraft slot) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.small),
      decoration: BoxDecoration(
        color: AppColors.surfaceRaised,
        borderRadius: BorderRadius.circular(AppRadius.button),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: ExercisePickerField(
                  allOptions: _allExercises,
                  defaultOptions: _allExercises,
                  selected: slot.exercise,
                  onSelected: (e) => setState(() {
                    slot.exercise = e;
                    final isCardio = e.equipmentTags.contains(
                      ExerciseType.cardio,
                    );
                    // Reset the target to something sane for the new kind.
                    // A rep count doesn't mean anything for cardio and vice
                    // versa.
                    slot.targetType = isCardio
                        ? HiitTargetType.time
                        : HiitTargetType.reps;
                    slot.targetValue = isCardio ? 60 : 10;
                    slot.weight = null;
                  }),
                ),
              ),
              TapIcon(
                icon: Icons.remove_circle_outline,
                size: 20,
                onTap: () => _removeSlot(group, slot),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.small),
          slot.isCardio ? _cardioTargetEditor(slot) : _liftTargetEditor(slot),
        ],
      ),
    );
  }

  Widget _liftTargetEditor(_SlotDraft slot) {
    final isAmrap = slot.targetType == HiitTargetType.amrap;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            ChoiceChip(
              label: const Text('Reps'),
              selected: !isAmrap,
              showCheckmark: false,
              onSelected: (_) => setState(() {
                slot.targetType = HiitTargetType.reps;
                slot.targetValue = 10;
              }),
            ),
            const SizedBox(width: AppSpacing.small),
            ChoiceChip(
              label: const Text('AMRAP'),
              selected: isAmrap,
              showCheckmark: false,
              onSelected: (_) => setState(() {
                slot.targetType = HiitTargetType.amrap;
                slot.targetValue = 30;
              }),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.small),
        Row(
          children: [
            Expanded(
              child: TextFormField(
                key: ValueKey('target_${slot.hashCode}_${slot.targetType}'),
                initialValue: slot.targetValue?.toStringAsFixed(
                  isAmrap ? 0 : 0,
                ),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                style: AppText.bodyText,
                decoration: InputDecoration(
                  labelText: isAmrap ? 'AMRAP (sec)' : 'Reps',
                ),
                onChanged: (v) => slot.targetValue = double.tryParse(v),
              ),
            ),
            const SizedBox(width: AppSpacing.small),
            Expanded(
              child: TextFormField(
                key: ValueKey('weight_${slot.hashCode}'),
                initialValue: slot.weight == null
                    ? ''
                    : Units.displayValue(slot.weight!).toStringAsFixed(0),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                style: AppText.bodyText,
                decoration: InputDecoration(
                  labelText: 'Weight (${Units.suffix})',
                ),
                onChanged: (v) {
                  final entered = double.tryParse(v);
                  slot.weight = entered == null ? null : Units.toLb(entered);
                },
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _cardioTargetEditor(_SlotDraft slot) {
    final isDistance = slot.targetType == HiitTargetType.distance;
    final unit = slot.exercise.cardioUnit ?? CardioUnits.defaultUnit;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            ChoiceChip(
              label: const Text('Time'),
              selected: !isDistance,
              showCheckmark: false,
              onSelected: (_) => setState(() {
                slot.targetType = HiitTargetType.time;
                slot.targetValue = 60;
              }),
            ),
            const SizedBox(width: AppSpacing.small),
            ChoiceChip(
              label: const Text('Distance'),
              selected: isDistance,
              showCheckmark: false,
              onSelected: (_) => setState(() {
                slot.targetType = HiitTargetType.distance;
                slot.targetValue = CardioUnits.toCanonical(100, unit);
              }),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.small),
        Row(
          children: [
            Expanded(
              child: TextFormField(
                key: ValueKey('target_${slot.hashCode}_${slot.targetType}'),
                initialValue: isDistance
                    ? (slot.targetValue == null
                          ? ''
                          : CardioUnits.fromCanonical(
                              slot.targetValue!,
                              unit,
                            ).toStringAsFixed(
                              unit == DistanceUnit.floors ? 0 : 1,
                            ))
                    : (slot.targetValue == null
                          ? ''
                          : (slot.targetValue! / 60).toStringAsFixed(1)),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                style: AppText.bodyText,
                decoration: InputDecoration(
                  labelText: isDistance
                      ? 'Distance (${unit.suffix})'
                      : 'Time (min)',
                ),
                onChanged: (v) {
                  final entered = double.tryParse(v);
                  if (entered == null) {
                    slot.targetValue = null;
                  } else {
                    slot.targetValue = isDistance
                        ? CardioUnits.toCanonical(entered, unit)
                        : entered * 60;
                  }
                },
              ),
            ),
            const SizedBox(width: AppSpacing.small),
            Expanded(
              child: TextFormField(
                key: ValueKey('load_${slot.hashCode}'),
                initialValue: slot.weight?.toString() ?? '',
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                style: AppText.bodyText,
                decoration: const InputDecoration(
                  labelText: 'Resistance (optional)',
                ),
                onChanged: (v) => slot.weight = double.tryParse(v),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _restControl({
    required String label,
    required bool hasRest,
    required int seconds,
    required ValueChanged<bool> onToggle,
    required ValueChanged<int> onSecondsChanged,
  }) {
    return Row(
      children: [
        Text(label, style: AppText.smallText),
        const SizedBox(width: AppSpacing.small),
        ChoiceChip(
          label: const Text('Direct'),
          selected: !hasRest,
          showCheckmark: false,
          visualDensity: VisualDensity.compact,
          onSelected: (_) => onToggle(false),
        ),
        const SizedBox(width: AppSpacing.micro),
        ChoiceChip(
          label: const Text('Rest'),
          selected: hasRest,
          showCheckmark: false,
          visualDensity: VisualDensity.compact,
          onSelected: (_) => onToggle(true),
        ),
        if (hasRest) ...[
          const SizedBox(width: AppSpacing.small),
          SizedBox(
            width: 56,
            child: TextFormField(
              initialValue: seconds.toString(),
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              style: AppText.smallText,
              onChanged: (v) => onSecondsChanged(int.tryParse(v) ?? seconds),
            ),
          ),
          Text(' sec', style: AppText.smallText),
        ],
      ],
    );
  }

  Widget _intraGroupRest(_SlotDraft slot) {
    final hasRest = (slot.restAfterSeconds ?? 0) > 0;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.micro),
      child: _restControl(
        label: 'Then:',
        hasRest: hasRest,
        seconds: slot.restAfterSeconds ?? 30,
        onToggle: (v) => setState(() => slot.restAfterSeconds = v ? 30 : null),
        onSecondsChanged: (v) => setState(() => slot.restAfterSeconds = v),
      ),
    );
  }

  Widget _interGroupRest(_GroupDraft group) {
    if (group.slots.isEmpty) return const SizedBox.shrink();
    final lastSlot = group.slots.last;
    final hasRest = (lastSlot.restAfterSeconds ?? 0) > 0;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.standard),
      child: Center(
        child: _restControl(
          label: 'Between rounds:',
          hasRest: hasRest,
          seconds: lastSlot.restAfterSeconds ?? 30,
          onToggle: (v) =>
              setState(() => lastSlot.restAfterSeconds = v ? 30 : null),
          onSecondsChanged: (v) =>
              setState(() => lastSlot.restAfterSeconds = v),
        ),
      ),
    );
  }
}
