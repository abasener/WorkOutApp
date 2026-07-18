import '../database.dart';
import '../models/custom_goal.dart';

class CustomGoalRepository {
  final DatabaseHelper _db;
  CustomGoalRepository(this._db);

  /// All goal-log entries for one exercise, newest first — the first
  /// element (if any) is the one currently driving the gauge.
  Future<List<CustomGoal>> getAllForExercise(int exerciseId) async {
    final rows = await (await _db.database).query(
      'custom_goals',
      where: 'exercise_id = ?',
      whereArgs: [exerciseId],
      orderBy: 'created DESC, id DESC',
    );
    return rows.map(CustomGoal.fromMap).toList();
  }

  /// The most recent entry per exercise, keyed by exercise id — for screens
  /// that need to know "does this exercise have a current custom goal"
  /// across the whole list at once rather than a query per lift.
  Future<Map<int, CustomGoal>> getCurrentByExercise() async {
    final rows = await (await _db.database)
        .query('custom_goals', orderBy: 'created DESC, id DESC');
    final result = <int, CustomGoal>{};
    for (final g in rows.map(CustomGoal.fromMap)) {
      result.putIfAbsent(g.exerciseId, () => g);
    }
    return result;
  }

  Future<void> insert(CustomGoal goal) async =>
      (await _db.database).insert('custom_goals', goal.toMap());

  Future<void> delete(int id) async =>
      (await _db.database).delete('custom_goals', where: 'id = ?', whereArgs: [id]);
}
