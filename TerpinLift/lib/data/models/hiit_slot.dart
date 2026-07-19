/// A lift exercise (reps, or AMRAP within a time cap) vs. a cardio exercise
/// (a fixed time, or a distance) — which target types are even offered
/// depends on this. Stored redundantly alongside `exercise_id` rather than
/// re-derived from `Exercise.equipmentTags` every time, so a slot's shape
/// stays stable even if the exercise's own tags change later.
enum HiitExerciseKind { lift, cardio }

extension HiitExerciseKindKey on HiitExerciseKind {
  String get key => name;
  static HiitExerciseKind? fromKey(String? key) {
    for (final v in HiitExerciseKind.values) {
      if (v.name == key) return v;
    }
    return null;
  }
}

/// What a slot's `target_value` means:
/// - [reps] — a fixed rep count (lift slots).
/// - [amrap] — as many reps as possible within `target_value` seconds (lift
///   slots) — the ring shows the time countdown, not a rep count; actual
///   reps done are tracked live in manual mode or filled in afterward on the
///   report screen in automatic mode (see `designFiles/12_SCREEN_hiit.md`).
/// - [time] — a fixed duration in seconds (cardio slots, e.g. "5 min ruck").
/// - [distance] — a fixed distance, canonical per the exercise's own
///   `DistanceUnit` (cardio slots, e.g. "100m sprint").
enum HiitTargetType { reps, amrap, time, distance }

extension HiitTargetTypeKey on HiitTargetType {
  String get key => name;
  static HiitTargetType? fromKey(String? key) {
    for (final v in HiitTargetType.values) {
      if (v.name == key) return v;
    }
    return null;
  }
}

/// One exercise occurrence in a HIIT routine — the routine is a flat,
/// strictly-ordered sequence of these (`sequenceIndex`), with `groupIndex`
/// marking which round each belongs to (for the progress bar's round
/// markers and for grouping "curls, round 1" vs "curls, round 2" as
/// separate sets on the same day once logged). `restAfterSeconds` covers
/// both the gap to the next slot in the same round *and* the gap between
/// rounds — whichever slot happens to be last in a round just carries the
/// round's rest value. `null`/`0` = "Direct," no rest screen shown.
///
/// Target fields (`targetType`/`targetValue`/`weight`) are set once during
/// setup and never edited live; `actual*` fields start unset and get filled
/// in either live during the active session (manual mode, or automatic
/// mode's own progress) or on the report screen before saving — see
/// designFiles/12_SCREEN_hiit.md. `liftSetId`/`cardioEntryId` are set once
/// the report screen's Save actually writes the corresponding `LiftSet`/
/// `CardioEntry` row.
class HiitSlot {
  final int? id;
  final int hiitSessionId;
  final int sequenceIndex;
  final int groupIndex;
  final int exerciseId;
  final HiitExerciseKind exerciseKind;
  final HiitTargetType targetType;
  final double? targetValue;
  final double? weight;
  final int? restAfterSeconds;
  final int? actualReps;
  final double? actualWeight;
  final int? actualTimeSeconds;
  final double? actualDistance;
  final double? actualLoad;
  final int? liftSetId;
  final int? cardioEntryId;

  const HiitSlot({
    this.id,
    required this.hiitSessionId,
    required this.sequenceIndex,
    required this.groupIndex,
    required this.exerciseId,
    required this.exerciseKind,
    required this.targetType,
    this.targetValue,
    this.weight,
    this.restAfterSeconds,
    this.actualReps,
    this.actualWeight,
    this.actualTimeSeconds,
    this.actualDistance,
    this.actualLoad,
    this.liftSetId,
    this.cardioEntryId,
  });

  factory HiitSlot.fromMap(Map<String, dynamic> m) => HiitSlot(
        id: m['id'] as int?,
        hiitSessionId: m['hiit_session_id'] as int,
        sequenceIndex: m['sequence_index'] as int,
        groupIndex: m['group_index'] as int,
        exerciseId: m['exercise_id'] as int,
        exerciseKind: HiitExerciseKindKey.fromKey(m['exercise_kind'] as String) ?? HiitExerciseKind.lift,
        targetType: HiitTargetTypeKey.fromKey(m['target_type'] as String) ?? HiitTargetType.reps,
        targetValue: (m['target_value'] as num?)?.toDouble(),
        weight: (m['weight'] as num?)?.toDouble(),
        restAfterSeconds: m['rest_after_seconds'] as int?,
        actualReps: m['actual_reps'] as int?,
        actualWeight: (m['actual_weight'] as num?)?.toDouble(),
        actualTimeSeconds: m['actual_time_seconds'] as int?,
        actualDistance: (m['actual_distance'] as num?)?.toDouble(),
        actualLoad: (m['actual_load'] as num?)?.toDouble(),
        liftSetId: m['lift_set_id'] as int?,
        cardioEntryId: m['cardio_entry_id'] as int?,
      );

  Map<String, dynamic> toMap() => {
        'hiit_session_id': hiitSessionId,
        'sequence_index': sequenceIndex,
        'group_index': groupIndex,
        'exercise_id': exerciseId,
        'exercise_kind': exerciseKind.key,
        'target_type': targetType.key,
        'target_value': targetValue,
        'weight': weight,
        'rest_after_seconds': restAfterSeconds,
        'actual_reps': actualReps,
        'actual_weight': actualWeight,
        'actual_time_seconds': actualTimeSeconds,
        'actual_distance': actualDistance,
        'actual_load': actualLoad,
        'lift_set_id': liftSetId,
        'cardio_entry_id': cardioEntryId,
      };

  HiitSlot copyWith({
    int? id,
    int? actualReps,
    double? actualWeight,
    int? actualTimeSeconds,
    double? actualDistance,
    double? actualLoad,
    int? liftSetId,
    int? cardioEntryId,
  }) =>
      HiitSlot(
        id: id ?? this.id,
        hiitSessionId: hiitSessionId,
        sequenceIndex: sequenceIndex,
        groupIndex: groupIndex,
        exerciseId: exerciseId,
        exerciseKind: exerciseKind,
        targetType: targetType,
        targetValue: targetValue,
        weight: weight,
        restAfterSeconds: restAfterSeconds,
        actualReps: actualReps ?? this.actualReps,
        actualWeight: actualWeight ?? this.actualWeight,
        actualTimeSeconds: actualTimeSeconds ?? this.actualTimeSeconds,
        actualDistance: actualDistance ?? this.actualDistance,
        actualLoad: actualLoad ?? this.actualLoad,
        liftSetId: liftSetId ?? this.liftSetId,
        cardioEntryId: cardioEntryId ?? this.cardioEntryId,
      );
}
