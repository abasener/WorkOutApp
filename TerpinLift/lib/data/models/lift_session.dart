class LiftSession {
  final int? id;
  final int exerciseId;
  final String date; // 'YYYY-MM-DD'
  final String? startedAt;
  final String? completedAt;
  final String? notes;

  const LiftSession({
    this.id,
    required this.exerciseId,
    required this.date,
    this.startedAt,
    this.completedAt,
    this.notes,
  });

  factory LiftSession.fromMap(Map<String, dynamic> m) => LiftSession(
        id: m['id'] as int?,
        exerciseId: m['exercise_id'] as int,
        date: m['date'] as String,
        startedAt: m['started_at'] as String?,
        completedAt: m['completed_at'] as String?,
        notes: m['notes'] as String?,
      );

  Map<String, dynamic> toMap() => {
        'exercise_id': exerciseId,
        'date': date,
        'started_at': startedAt,
        'completed_at': completedAt,
        'notes': notes,
      };

  LiftSession copyWith({int? exerciseId, String? date, String? notes}) => LiftSession(
        id: id,
        exerciseId: exerciseId ?? this.exerciseId,
        date: date ?? this.date,
        startedAt: startedAt,
        completedAt: completedAt,
        notes: notes ?? this.notes,
      );
}
