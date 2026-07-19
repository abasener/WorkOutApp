/// One entry in a user-set goal log for an exercise — the fallback (or
/// opt-in override, see `Exercise.goalSource`) for the Goal gauge when
/// there's no published strength standard for that lift, or when the user
/// just prefers their own number. Exactly one of [targetWeight]/[targetReps]
/// (lift exercises) is set, matching whichever axis that exercise's Goal
/// gauge already uses — **or**, for a cardio exercise, exactly one of
/// [targetDistance]/[targetPace], since cardio goals are two independent
/// gauges (distance and pace) rather than one axis. See
/// `designFiles/11_SCREEN_cardio.md`.
///
/// Unlike most of this app's per-exercise settings, this is a **log, not a
/// single value** — an exercise can carry many of these over time (like a
/// lift-log entry), each with its own optional [label] so old goals stay
/// visible/nameable ("August target," a date, whatever fits) rather than
/// getting silently overwritten. The most recent entry (by [created]) is the
/// one that actually drives the gauge; older ones are just browsable history.
class CustomGoal {
  final int? id;
  final int exerciseId;
  final String? label;
  final double? targetWeight; // lb, canonical
  final int? targetReps;

  /// Meters, canonical — or a raw floor count for a `DistanceUnit.floors`
  /// exercise (floors don't convert to/from a real distance, so nothing to
  /// canonicalize; see `CardioUnits`).
  final double? targetDistance;

  /// Seconds per canonical meter (or per floor) — same basis
  /// `CardioUnits.paceSecondsPerUnit` derives an entry's actual pace in, so
  /// a goal and a logged result are always comparable regardless of which
  /// display unit the exercise happens to be set to when either was entered.
  final double? targetPace;

  final String created;

  const CustomGoal({
    this.id,
    required this.exerciseId,
    this.label,
    this.targetWeight,
    this.targetReps,
    this.targetDistance,
    this.targetPace,
    required this.created,
  });

  factory CustomGoal.fromMap(Map<String, dynamic> m) => CustomGoal(
        id: m['id'] as int?,
        exerciseId: m['exercise_id'] as int,
        label: m['label'] as String?,
        targetWeight: (m['target_weight'] as num?)?.toDouble(),
        targetReps: m['target_reps'] as int?,
        targetDistance: (m['target_distance'] as num?)?.toDouble(),
        targetPace: (m['target_pace'] as num?)?.toDouble(),
        created: m['created'] as String,
      );

  Map<String, dynamic> toMap() => {
        'exercise_id': exerciseId,
        'label': label,
        'target_weight': targetWeight,
        'target_reps': targetReps,
        'target_distance': targetDistance,
        'target_pace': targetPace,
        'created': created,
      };
}
