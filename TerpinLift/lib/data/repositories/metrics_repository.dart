import '../database.dart';
import '../models/metric_entry.dart';

class MetricsRepository {
  final DatabaseHelper _db;
  MetricsRepository(this._db);

  Future<List<MetricEntry>> getByType(MetricType type, {int? limit}) async {
    // `date DESC` alone doesn't disambiguate multiple same-day entries (e.g.
    // logging soreness both morning and evening) — without a tiebreaker,
    // SQLite falls back to insertion order, so the *first* entry of the day
    // would win over a later same-day update. `logged_at DESC, id DESC`
    // makes "most recently logged" actually mean most recent.
    final rows = await (await _db.database).query(
      'metrics_log',
      where: 'metric_type = ?',
      whereArgs: [type.key],
      orderBy: 'date DESC, logged_at DESC, id DESC',
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

  /// Every logged metric entry (all types) — used by the Metrics "Days" tab
  /// to build a day-grouped, editable view across steps/sleep/soreness.
  Future<List<MetricEntry>> getAll() async {
    final rows = await (await _db.database).query('metrics_log', orderBy: 'date DESC');
    return rows.map(MetricEntry.fromMap).toList();
  }

  Future<int> insert(MetricEntry e) async =>
      (await _db.database).insert('metrics_log', e.toMap());

  Future<void> update(MetricEntry e) async => (await _db.database).update(
        'metrics_log',
        e.toMap(),
        where: 'id = ?',
        whereArgs: [e.id],
      );

  Future<void> delete(int id) async =>
      (await _db.database).delete('metrics_log', where: 'id = ?', whereArgs: [id]);
}
