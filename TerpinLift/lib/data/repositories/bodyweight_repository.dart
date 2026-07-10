import '../database.dart';
import '../models/bodyweight_entry.dart';

class BodyweightRepository {
  final DatabaseHelper _db;
  BodyweightRepository(this._db);

  Future<List<BodyweightEntry>> getAll() async {
    final rows =
        await (await _db.database).query('bodyweight_log', orderBy: 'date DESC');
    return rows.map(BodyweightEntry.fromMap).toList();
  }

  /// Most recent bodyweight entry, or null if none logged yet.
  Future<BodyweightEntry?> getLatest() async {
    final rows = await (await _db.database)
        .query('bodyweight_log', orderBy: 'date DESC', limit: 1);
    if (rows.isEmpty) return null;
    return BodyweightEntry.fromMap(rows.first);
  }

  Future<int> insert(BodyweightEntry e) async =>
      (await _db.database).insert('bodyweight_log', e.toMap());

  Future<void> delete(int id) async => (await _db.database)
      .delete('bodyweight_log', where: 'id = ?', whereArgs: [id]);
}
