/// One entry in a user-set goal log for an exercise — the fallback (or
/// opt-in override, see `Exercise.goalSource`) for the Goal gauge when
/// there's no published strength standard for that lift, or when the user
/// just prefers their own number. Exactly one of [targetWeight]/[targetReps]
/// is set, matching whichever axis that exercise's Goal gauge already uses.
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
  final String created;

  const CustomGoal({
    this.id,
    required this.exerciseId,
    this.label,
    this.targetWeight,
    this.targetReps,
    required this.created,
  });

  factory CustomGoal.fromMap(Map<String, dynamic> m) => CustomGoal(
        id: m['id'] as int?,
        exerciseId: m['exercise_id'] as int,
        label: m['label'] as String?,
        targetWeight: (m['target_weight'] as num?)?.toDouble(),
        targetReps: m['target_reps'] as int?,
        created: m['created'] as String,
      );

  Map<String, dynamic> toMap() => {
        'exercise_id': exerciseId,
        'label': label,
        'target_weight': targetWeight,
        'target_reps': targetReps,
        'created': created,
      };
}
