class LiftSet {
  final int? id;
  final int sessionId;
  final int setNumber;
  final int reps;
  final double weight; // raw logged weight (lbs) — always stored as-is
  final double? rpe; // 1-10, nullable
  final String? setStartedAt;
  final String? setCompletedAt;

  const LiftSet({
    this.id,
    required this.sessionId,
    required this.setNumber,
    required this.reps,
    required this.weight,
    this.rpe,
    this.setStartedAt,
    this.setCompletedAt,
  });

  factory LiftSet.fromMap(Map<String, dynamic> m) => LiftSet(
        id: m['id'] as int?,
        sessionId: m['session_id'] as int,
        setNumber: m['set_number'] as int,
        reps: m['reps'] as int,
        weight: (m['weight'] as num).toDouble(),
        rpe: (m['rpe'] as num?)?.toDouble(),
        setStartedAt: m['set_started_at'] as String?,
        setCompletedAt: m['set_completed_at'] as String?,
      );

  Map<String, dynamic> toMap() => {
        'session_id': sessionId,
        'set_number': setNumber,
        'reps': reps,
        'weight': weight,
        'rpe': rpe,
        'set_started_at': setStartedAt,
        'set_completed_at': setCompletedAt,
      };

  /// Estimated 1-rep-max via the Epley formula.
  /// See designFiles/08_GLOSSARY_AND_SCIENCE.md — chosen for simplicity/consistency,
  /// not because it's more "correct" than Brzycki.
  double get e1rm => reps <= 1 ? weight : weight * (1 + reps / 30);
}
