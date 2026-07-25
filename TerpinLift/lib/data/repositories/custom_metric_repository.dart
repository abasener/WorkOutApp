import '../database.dart';
import '../models/custom_metric.dart';
import '../models/custom_metric_entry.dart';

class CustomMetricRepository {
  final DatabaseHelper _db;
  CustomMetricRepository(this._db);

  Future<List<CustomMetric>> getAllDefinitions() async {
    final rows = await (await _db.database).query(
      'custom_metrics',
      orderBy: 'created ASC',
    );
    return rows.map(CustomMetric.fromMap).toList();
  }

  Future<int> insertDefinition(CustomMetric metric) async =>
      (await _db.database).insert('custom_metrics', metric.toMap());

  /// Full editing of an existing metric's definition doesn't exist yet (kind/
  /// scaleMax/classLabels aren't safe to change once real entries exist) —
  /// this is used narrowly for the one field that is safe to change anytime,
  /// the optional goal (designFiles/05_SCREEN_metrics.md "Goals").
  Future<void> updateDefinition(CustomMetric metric) async =>
      (await _db.database).update(
        'custom_metrics',
        metric.toMap(),
        where: 'id = ?',
        whereArgs: [metric.id],
      );

  /// Deletes the definition and (via `ON DELETE CASCADE`) every entry logged
  /// against it — a metric you built by mistake shouldn't leave orphaned data
  /// behind, unlike deleting an exercise (which asks first because sessions
  /// are real training history); a mis-built metric has no such weight.
  Future<void> deleteDefinition(int id) async => (await _db.database).delete(
    'custom_metrics',
    where: 'id = ?',
    whereArgs: [id],
  );

  Future<List<CustomMetricEntry>> getEntries(int customMetricId) async {
    final rows = await (await _db.database).query(
      'custom_metric_entries',
      where: 'custom_metric_id = ?',
      whereArgs: [customMetricId],
      orderBy: 'date ASC, logged_at ASC',
    );
    return rows.map(CustomMetricEntry.fromMap).toList();
  }

  Future<CustomMetricEntry?> getLatest(int customMetricId) async {
    final rows = await (await _db.database).query(
      'custom_metric_entries',
      where: 'custom_metric_id = ?',
      whereArgs: [customMetricId],
      orderBy: 'date DESC, logged_at DESC',
      limit: 1,
    );
    return rows.isEmpty ? null : CustomMetricEntry.fromMap(rows.first);
  }

  Future<void> insertEntry(CustomMetricEntry entry) async =>
      (await _db.database).insert('custom_metric_entries', entry.toMap());

  /// Logs [entry] respecting [metric]'s `allowMultiplePerDay` setting — a
  /// plain [insertEntry] when multiples are allowed, otherwise clears out
  /// any existing entry for that same date first, so a metric built as
  /// once-a-day (the default) never silently accumulates duplicates the way
  /// the user found happening before this existed.
  Future<void> upsertEntry(CustomMetric metric, CustomMetricEntry entry) async {
    if (!metric.allowMultiplePerDay) {
      final existing = await getEntries(metric.id!);
      for (final e in existing.where((e) => e.date == entry.date)) {
        await deleteEntry(e.id!);
      }
    }
    await insertEntry(entry);
  }

  Future<void> deleteEntry(int id) async => (await _db.database).delete(
    'custom_metric_entries',
    where: 'id = ?',
    whereArgs: [id],
  );
}
