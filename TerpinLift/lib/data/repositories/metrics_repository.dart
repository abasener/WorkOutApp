import '../database.dart';
import '../models/metric_entry.dart';

class MetricsRepository {
  final DatabaseHelper _db;
  MetricsRepository(this._db);

  Future<List<MetricEntry>> getByType(MetricType type, {int? limit}) async {
    final rows = await (await _db.database).query(
      'metrics_log',
      where: 'metric_type = ?',
      whereArgs: [type.key],
      orderBy: 'date DESC',
      limit: limit,
    );
    return rows.map(MetricEntry.fromMap).toList();
  }

  Future<MetricEntry?> getLatest(MetricType type) async {
    final rows = await getByType(type, limit: 1);
    return rows.isEmpty ? null : rows.first;
  }

  /// All entries of [type] on a specific date, most recently logged first —
  /// used where multiple same-day entries are expected (e.g. soreness).
  Future<List<MetricEntry>> getByTypeAndDate(MetricType type, String date) async {
    final rows = await (await _db.database).query(
      'metrics_log',
      where: 'metric_type = ? AND date = ?',
      whereArgs: [type.key, date],
      orderBy: 'logged_at DESC',
    );
    return rows.map(MetricEntry.fromMap).toList();
  }

  Future<int> insert(MetricEntry e) async =>
      (await _db.database).insert('metrics_log', e.toMap());

  Future<void> delete(int id) async =>
      (await _db.database).delete('metrics_log', where: 'id = ?', whereArgs: [id]);
}
