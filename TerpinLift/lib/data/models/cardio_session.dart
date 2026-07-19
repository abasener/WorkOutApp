/// One logged cardio session — the container; the actual distance/duration/
/// load numbers live on its `CardioEntry` rows (usually just one, but
/// interval-style cardio can log several in a single session, same shape as
/// `LiftSession`/`LiftSet`).
class CardioSession {
  final int? id;
  final int exerciseId;
  final String date; // 'YYYY-MM-DD'
  final String? notes;

  const CardioSession({
    this.id,
    required this.exerciseId,
    required this.date,
    this.notes,
  });

  factory CardioSession.fromMap(Map<String, dynamic> m) => CardioSession(
        id: m['id'] as int?,
        exerciseId: m['exercise_id'] as int,
        date: m['date'] as String,
        notes: m['notes'] as String?,
      );

  Map<String, dynamic> toMap() => {
        'exercise_id': exerciseId,
        'date': date,
        'notes': notes,
      };

  CardioSession copyWith({
    int? exerciseId,
    String? date,
    String? notes,
    bool clearNotes = false,
  }) =>
      CardioSession(
        id: id,
        exerciseId: exerciseId ?? this.exerciseId,
        date: date ?? this.date,
        notes: clearNotes ? null : (notes ?? this.notes),
      );
}
