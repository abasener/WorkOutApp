import '../database.dart';
import '../models/lift_session.dart';
import '../models/lift_set.dart';

/// A session with its sets attached — the common shape screens need.
class SessionWithSets {
  final LiftSession session;
  final List<LiftSet> sets;
  const SessionWithSets(this.session, this.sets);

  /// Highest e1RM among this session's sets — used for trend charts.
  double get bestE1rm =>
      sets.isEmpty ? 0 : sets.map((s) => s.e1rm).reduce((a, b) => a > b ? a : b);
}

class LiftRepository {
  final DatabaseHelper _db;
  LiftRepository(this._db);

  Future<int> insertSession(LiftSession session) async =>
      (await _db.database).insert('lift_sessions', session.toMap());

  Future<void> updateSession(LiftSession session) async =>
      (await _db.database).update('lift_sessions', session.toMap(),
          where: 'id = ?', whereArgs: [session.id]);

  Future<int> insertSet(LiftSet set) async =>
      (await _db.database).insert('lift_sets', set.toMap());

  Future<void> deleteSession(int sessionId) async =>
      (await _db.database)
          .delete('lift_sessions', where: 'id = ?', whereArgs: [sessionId]);

  /// All sessions (with sets) for a given exercise, most recent first.
  Future<List<SessionWithSets>> getSessionsForExercise(int exerciseId) async {
    final db = await _db.database;
    final sessionRows = await db.query(
      'lift_sessions',
      where: 'exercise_id = ?',
      whereArgs: [exerciseId],
      orderBy: 'date DESC, id DESC',
    );

    final result = <SessionWithSets>[];
    for (final row in sessionRows) {
      final session = LiftSession.fromMap(row);
      final setRows = await db.query(
        'lift_sets',
        where: 'session_id = ?',
        whereArgs: [session.id],
        orderBy: 'set_number ASC',
      );
      result.add(SessionWithSets(session, setRows.map(LiftSet.fromMap).toList()));
    }
    return result;
  }

  /// Convenience: log a full session in one call (session + its sets).
  /// [startedAt]/[completedAt] are ISO datetimes captured by the silent
  /// background timer in LogLiftForm, when the "track time" toggle is on.
  Future<int> logSession({
    required int exerciseId,
    required String date,
    required List<LiftSet> sets,
    String? startedAt,
    String? completedAt,
    String? notes,
  }) async {
    final sessionId = await insertSession(
      LiftSession(
        exerciseId: exerciseId,
        date: date,
        startedAt: startedAt,
        completedAt: completedAt,
        notes: notes,
      ),
    );
    for (var i = 0; i < sets.length; i++) {
      await insertSet(LiftSet(
        sessionId: sessionId,
        setNumber: i + 1,
        reps: sets[i].reps,
        weight: sets[i].weight,
        rpe: sets[i].rpe,
      ));
    }
    return sessionId;
  }

  /// Most recent session date across ALL exercises — used for the Home heatmap.
  Future<List<String>> getAllWorkoutDates() async {
    final rows = await (await _db.database)
        .query('lift_sessions', columns: ['DISTINCT date as date'], orderBy: 'date DESC');
    return rows.map((r) => r['date'] as String).toList();
  }
}
