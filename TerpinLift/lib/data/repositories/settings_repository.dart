import 'package:sqflite/sqflite.dart';

import '../database.dart';

/// Simple key-value store for app-wide config (unit preference, rolling
/// window lengths, etc.) per designFiles/01_DATA_MODEL.md.
class SettingsRepository {
  final DatabaseHelper _db;
  SettingsRepository(this._db);

  Future<String?> get(String key) async {
    final rows = await (await _db.database).query(
      'app_settings',
      where: 'key = ?',
      whereArgs: [key],
    );
    if (rows.isEmpty) return null;
    return rows.first['value'] as String;
  }

  Future<void> set(String key, String value) async {
    final db = await _db.database;
    await db.insert('app_settings', {
      'key': key,
      'value': value,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> delete(String key) async {
    final db = await _db.database;
    await db.delete('app_settings', where: 'key = ?', whereArgs: [key]);
  }

  /// Wipes every stored setting for the current profile at once — used when
  /// resetting the demo profile back through onboarding, so the survey
  /// starts from a genuinely blank slate rather than pre-filled with
  /// whatever was set before. Never touches logged data (lifts, cardio,
  /// bodyweight, etc.), only this key-value table.
  Future<void> clearAll() async {
    final db = await _db.database;
    await db.delete('app_settings');
  }
}
