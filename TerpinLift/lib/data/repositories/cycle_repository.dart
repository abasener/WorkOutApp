import '../database.dart';
import '../models/cycle_entry.dart';

class CycleRepository {
  final DatabaseHelper _db;
  CycleRepository(this._db);

  Future<List<CycleEntry>> getAll({int? limit}) async {
    final rows = await (await _db.database)
        .query('cycle_log', orderBy: 'date DESC', limit: limit);
    return rows.map(CycleEntry.fromMap).toList();
  }

  /// All 'flow' entries, ascending by date — the basis for period/cycle
  /// length analysis.
  Future<List<CycleEntry>> getFlowEntries() async {
    final rows = await (await _db.database).query(
      'cycle_log',
      where: 'entry_type = ?',
      whereArgs: [CycleEntryType.flow.key],
      orderBy: 'date ASC',
    );
    return rows.map(CycleEntry.fromMap).toList();
  }

  /// Sets (or replaces) the flow score for a given date. 0 = logged, no
  /// bleeding that day — distinct from no entry at all.
  Future<void> setFlow(String date, int flowValue) async {
    final db = await _db.database;
    final existing = await db.query(
      'cycle_log',
      where: 'date = ? AND entry_type = ?',
      whereArgs: [date, CycleEntryType.flow.key],
    );
    if (existing.isEmpty) {
      await db.insert(
        'cycle_log',
        CycleEntry(date: date, entryType: CycleEntryType.flow, flowValue: flowValue)
            .toMap(),
      );
    } else {
      await db.update(
        'cycle_log',
        {'flow_value': flowValue},
        where: 'id = ?',
        whereArgs: [existing.first['id']],
      );
    }
  }

  Future<int> insert(CycleEntry e) async =>
      (await _db.database).insert('cycle_log', e.toMap());

  Future<void> delete(int id) async =>
      (await _db.database).delete('cycle_log', where: 'id = ?', whereArgs: [id]);
}
