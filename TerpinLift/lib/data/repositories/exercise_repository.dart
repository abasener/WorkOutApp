import '../database.dart';
import '../models/exercise.dart';

class ExerciseRepository {
  final DatabaseHelper _db;
  ExerciseRepository(this._db);

  Future<List<Exercise>> getAll() async {
    final rows = await (await _db.database).query('exercises', orderBy: 'name ASC');
    return rows.map(Exercise.fromMap).toList();
  }

  Future<Exercise?> getById(int id) async {
    final rows = await (await _db.database)
        .query('exercises', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    return Exercise.fromMap(rows.first);
  }

  Future<int> insert(Exercise e) async =>
      (await _db.database).insert('exercises', e.toMap());

  Future<void> update(Exercise e) async => (await _db.database).update(
        'exercises',
        e.toMap(),
        where: 'id = ?',
        whereArgs: [e.id],
      );

  Future<void> delete(int id) async =>
      (await _db.database).delete('exercises', where: 'id = ?', whereArgs: [id]);
}
