import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';

import 'app_services.dart';

/// Export/import of the full local database to a single JSON file, kept in
/// the app's documents directory. Guards against reinstall/phone-loss data
/// loss per designFiles/06_SCREEN_settings.md.
class BackupService {
  static const _tables = [
    'exercises',
    'lift_sessions',
    'lift_sets',
    'bodyweight_log',
    'metrics_log',
    'cycle_log',
    'app_settings',
  ];

  static Future<File> _exportFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File(join(dir.path, 'terpinlift_export.json'));
  }

  /// Writes every table to a JSON file and returns its path.
  static Future<String> exportToFile() async {
    final db = await AppServices.db.database;
    final dump = <String, dynamic>{};
    for (final table in _tables) {
      dump[table] = await db.query(table);
    }
    final file = await _exportFile();
    await file.writeAsString(const JsonEncoder.withIndent('  ').convert(dump));
    return file.path;
  }

  /// Restores from the export file, if present. Existing rows are left in
  /// place; imported rows are inserted alongside them (no de-duplication in
  /// v1 — intended for restoring into a fresh install, not merging).
  static Future<bool> importFromFile() async {
    final file = await _exportFile();
    if (!await file.exists()) return false;

    final dump = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    final db = await AppServices.db.database;
    await db.transaction((txn) async {
      for (final table in _tables) {
        final rows = (dump[table] as List<dynamic>?) ?? [];
        for (final row in rows) {
          final map = Map<String, dynamic>.from(row as Map);
          map.remove('id'); // let autoincrement assign fresh ids
          await txn.insert(table, map);
        }
      }
    });
    AppServices.signalReload();
    return true;
  }

  static Future<String> exportFilePath() async => (await _exportFile()).path;
}
