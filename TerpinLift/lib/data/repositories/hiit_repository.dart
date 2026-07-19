import '../database.dart';
import '../models/hiit_session.dart';
import '../models/hiit_slot.dart';

class HiitRepository {
  final DatabaseHelper _db;
  HiitRepository(this._db);

  Future<int> insertSession(HiitSession session) async =>
      (await _db.database).insert('hiit_sessions', session.toMap());

  Future<void> updateSession(HiitSession session) async =>
      (await _db.database).update('hiit_sessions', session.toMap(),
          where: 'id = ?', whereArgs: [session.id]);

  Future<void> deleteSession(int id) async =>
      (await _db.database).delete('hiit_sessions', where: 'id = ?', whereArgs: [id]);

  Future<HiitSession?> getSession(int id) async {
    final rows =
        await (await _db.database).query('hiit_sessions', where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : HiitSession.fromMap(rows.first);
  }

  /// At most one active session at a time (enforced in app logic, same
  /// convention as `WorkoutPlanRepository.getActiveSession`).
  Future<HiitSession?> getActiveSession() async {
    final rows = await (await _db.database).query('hiit_sessions',
        where: 'status = ?', whereArgs: [HiitSessionStatus.active.key], limit: 1);
    return rows.isEmpty ? null : HiitSession.fromMap(rows.first);
  }

  /// Completed sessions only, most recent first — aborted sessions are
  /// excluded from history same as `WorkoutPlanRepository.getAllSessions`
  /// excludes aborted `PlannedSession`s (abort discards the marker rather
  /// than leaving a visible trace).
  Future<List<HiitSession>> getAllSessions() async {
    final rows = await (await _db.database).query('hiit_sessions',
        where: 'status = ?', whereArgs: [HiitSessionStatus.completed.key], orderBy: 'date DESC, id DESC');
    return rows.map(HiitSession.fromMap).toList();
  }

  Future<void> insertSlots(List<HiitSlot> slots) async {
    final db = await _db.database;
    final batch = db.batch();
    for (final s in slots) {
      batch.insert('hiit_slots', s.toMap());
    }
    await batch.commit(noResult: true);
  }

  Future<List<HiitSlot>> getSlotsForSession(int hiitSessionId) async {
    final rows = await (await _db.database).query('hiit_slots',
        where: 'hiit_session_id = ?', whereArgs: [hiitSessionId], orderBy: 'sequence_index ASC');
    return rows.map(HiitSlot.fromMap).toList();
  }

  Future<void> updateSlot(HiitSlot slot) async =>
      (await _db.database).update('hiit_slots', slot.toMap(), where: 'id = ?', whereArgs: [slot.id]);
}
