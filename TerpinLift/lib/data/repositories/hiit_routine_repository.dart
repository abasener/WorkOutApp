import '../database.dart';
import '../models/hiit_routine.dart';

class HiitRoutineRepository {
  final DatabaseHelper _db;
  HiitRoutineRepository(this._db);

  Future<int> insertRoutine(HiitRoutine routine) async =>
      (await _db.database).insert('hiit_routines', routine.toMap());

  Future<void> updateRoutine(HiitRoutine routine) async =>
      (await _db.database).update(
        'hiit_routines',
        routine.toMap(),
        where: 'id = ?',
        whereArgs: [routine.id],
      );

  Future<void> deleteRoutine(int id) async => (await _db.database).delete(
    'hiit_routines',
    where: 'id = ?',
    whereArgs: [id],
  );

  /// Every saved routine, by name — the list the merged preset/saved-routine
  /// picker shows, and how a by-name Add/Replace import decision is made.
  Future<List<HiitRoutine>> getAllRoutines() async {
    final rows = await (await _db.database).query(
      'hiit_routines',
      orderBy: 'name ASC',
    );
    return rows.map(HiitRoutine.fromMap).toList();
  }

  Future<HiitRoutine?> getRoutineByName(String name) async {
    final rows = await (await _db.database).query(
      'hiit_routines',
      where: 'name = ?',
      whereArgs: [name],
      limit: 1,
    );
    return rows.isEmpty ? null : HiitRoutine.fromMap(rows.first);
  }

  Future<List<HiitRoutineSlot>> getSlotsForRoutine(int hiitRoutineId) async {
    final rows = await (await _db.database).query(
      'hiit_routine_slots',
      where: 'hiit_routine_id = ?',
      whereArgs: [hiitRoutineId],
      orderBy: 'sequence_index ASC',
    );
    return rows.map(HiitRoutineSlot.fromMap).toList();
  }

  Future<void> insertRoutineSlots(List<HiitRoutineSlot> slots) async {
    final db = await _db.database;
    final batch = db.batch();
    for (final s in slots) {
      batch.insert('hiit_routine_slots', s.toMap());
    }
    await batch.commit(noResult: true);
  }

  /// Overwrites an existing routine's name/mode and its whole slot list —
  /// a saved routine has no history depending on it (unlike a workout-plan
  /// template's days), so a plain delete-and-reinsert of its slots is safe
  /// (designFiles/10_WORKOUT_PLANNER.md judgment call on why HIIT's replace
  /// doesn't need the same in-place-update care Workout Plan's does).
  Future<void> replaceRoutine(
    int routineId,
    HiitRoutine routine,
    List<HiitRoutineSlot> slots,
  ) async {
    final db = await _db.database;
    await db.transaction((txn) async {
      await txn.update(
        'hiit_routines',
        routine.toMap(),
        where: 'id = ?',
        whereArgs: [routineId],
      );
      await txn.delete(
        'hiit_routine_slots',
        where: 'hiit_routine_id = ?',
        whereArgs: [routineId],
      );
      final batch = txn.batch();
      for (final s in slots) {
        batch.insert('hiit_routine_slots', s.toMap());
      }
      await batch.commit(noResult: true);
    });
  }
}
