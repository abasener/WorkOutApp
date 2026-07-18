import '../database.dart';
import '../models/todo_item.dart';

class TodoRepository {
  final DatabaseHelper _db;
  TodoRepository(this._db);

  Future<List<TodoItem>> getAll() async {
    final rows = await (await _db.database).query('todo_items', orderBy: 'sort_order ASC');
    return rows.map(TodoItem.fromMap).toList();
  }

  Future<int> insert(TodoItem item) async =>
      (await _db.database).insert('todo_items', item.toMap());

  Future<void> update(TodoItem item) async => (await _db.database)
      .update('todo_items', item.toMap(), where: 'id = ?', whereArgs: [item.id]);

  Future<void> delete(int id) async =>
      (await _db.database).delete('todo_items', where: 'id = ?', whereArgs: [id]);

  /// Toggles today's check state for one item — sets `last_checked_date` to
  /// today, or clears it back to `null` if it was already today.
  Future<void> setCheckedToday(TodoItem item, String todayStr, bool checked) async {
    await update(item.copyWith(
      lastCheckedDate: checked ? todayStr : null,
      clearLastCheckedDate: !checked,
    ));
  }

  /// Replaces the entire list in one go — the edit sheet works on a full
  /// local copy (add/remove/reorder rows) and saves it all at once, same
  /// "batch edit" shape as a lift session's set list. Existing rows keep
  /// their id (and thus their `last_checked_date`) when the same one is
  /// present in [items]; anything removed is deleted, anything new is
  /// inserted.
  Future<void> replaceAll(List<TodoItem> items) async {
    final db = await _db.database;
    final existingIds = (await getAll()).map((e) => e.id).whereType<int>().toSet();
    final keptIds = items.map((e) => e.id).whereType<int>().toSet();
    for (final id in existingIds.difference(keptIds)) {
      await db.delete('todo_items', where: 'id = ?', whereArgs: [id]);
    }
    for (var i = 0; i < items.length; i++) {
      final item = items[i].copyWith(sortOrder: i);
      if (item.id == null) {
        await db.insert('todo_items', item.toMap());
      } else {
        await db.update('todo_items', item.toMap(), where: 'id = ?', whereArgs: [item.id]);
      }
    }
  }
}
