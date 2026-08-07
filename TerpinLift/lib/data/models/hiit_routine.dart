import 'hiit_slot.dart';

/// A saved, reusable HIIT circuit template — the deliberate "I want to keep
/// this" path, distinct from the hardcoded starting-point presets
/// (`hiit_presets.dart`) and from a live/completed `HiitSession` (which is a
/// fully realized run, not a reusable target). See
/// designFiles/12_SCREEN_hiit.md "Known gaps."
class HiitRoutine {
  final int? id;
  final String name;
  final bool automatic;
  final String created;

  const HiitRoutine({
    this.id,
    required this.name,
    this.automatic = false,
    required this.created,
  });

  factory HiitRoutine.fromMap(Map<String, dynamic> m) => HiitRoutine(
    id: m['id'] as int?,
    name: m['name'] as String,
    automatic: (m['automatic'] as int) == 1,
    created: m['created'] as String,
  );

  Map<String, dynamic> toMap() => {
    'name': name,
    'automatic': automatic ? 1 : 0,
    'created': created,
  };
}

/// One exercise occurrence within a saved [HiitRoutine] — the target-only
/// subset of `HiitSlot` (no `actual*`/`liftSetId`/`cardioEntryId`, since a
/// saved routine has no result yet, just a plan to load into a fresh
/// session's draft).
class HiitRoutineSlot {
  final int? id;
  final int hiitRoutineId;
  final int sequenceIndex;
  final int groupIndex;
  final int exerciseId;
  final HiitExerciseKind exerciseKind;
  final HiitTargetType targetType;
  final double? targetValue;
  final double? weight;
  final int? restAfterSeconds;

  const HiitRoutineSlot({
    this.id,
    required this.hiitRoutineId,
    required this.sequenceIndex,
    required this.groupIndex,
    required this.exerciseId,
    required this.exerciseKind,
    required this.targetType,
    this.targetValue,
    this.weight,
    this.restAfterSeconds,
  });

  factory HiitRoutineSlot.fromMap(Map<String, dynamic> m) => HiitRoutineSlot(
    id: m['id'] as int?,
    hiitRoutineId: m['hiit_routine_id'] as int,
    sequenceIndex: m['sequence_index'] as int,
    groupIndex: m['group_index'] as int,
    exerciseId: m['exercise_id'] as int,
    exerciseKind:
        HiitExerciseKindKey.fromKey(m['exercise_kind'] as String) ??
        HiitExerciseKind.lift,
    targetType:
        HiitTargetTypeKey.fromKey(m['target_type'] as String) ??
        HiitTargetType.reps,
    targetValue: (m['target_value'] as num?)?.toDouble(),
    weight: (m['weight'] as num?)?.toDouble(),
    restAfterSeconds: m['rest_after_seconds'] as int?,
  );

  Map<String, dynamic> toMap() => {
    'hiit_routine_id': hiitRoutineId,
    'sequence_index': sequenceIndex,
    'group_index': groupIndex,
    'exercise_id': exerciseId,
    'exercise_kind': exerciseKind.key,
    'target_type': targetType.key,
    'target_value': targetValue,
    'weight': weight,
    'rest_after_seconds': restAfterSeconds,
  };
}
