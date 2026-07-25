import 'dart:convert';
import 'dart:io';

import 'package:excel/excel.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../data/profile_manager.dart';
import 'app_services.dart';

/// Export/import of the full local database to a spreadsheet. Guards
/// against reinstall/phone-loss data loss per designFiles/06_SCREEN_settings.md.
class BackupService {
  /// Every table included in export, mapped to the sheet name it gets in
  /// the workbook (Title Case, so a non-programmer opening it sees clean
  /// tabs — the header *row* inside each sheet still uses the exact
  /// snake_case DB column names, since those need to stay unambiguous for
  /// re-importing later, not because anyone's expected to read them as
  /// prose). One sheet per table, never squashed together, per the point
  /// of moving off a single JSON blob. Order here is the order sheets
  /// appear in the file — roughly grouped by feature area.
  static const _exportTables = {
    'exercises': 'Exercises',
    'lift_sessions': 'Lift Sessions',
    'lift_sets': 'Lift Sets',
    'cardio_sessions': 'Cardio Sessions',
    'cardio_entries': 'Cardio Entries',
    'hiit_sessions': 'HIIT Sessions',
    'hiit_slots': 'HIIT Slots',
    'bodyweight_log': 'Bodyweight Log',
    'metrics_log': 'Metrics Log',
    'cycle_log': 'Cycle Log',
    'custom_metrics': 'Custom Metrics',
    'custom_metric_entries': 'Custom Metric Entries',
    'custom_goals': 'Custom Goals',
    // progress_photos is deliberately NOT exported — the `excel` package
    // has no support for embedding images in a cell (checked its source:
    // no "image"/"drawing" code anywhere), and a metadata-only row whose
    // file_path points at an image in this device's own private storage
    // is useless on a fresh install/different device — the path just
    // won't resolve to anything there. The user's own call: rather than
    // ship a spreadsheet with dead references, drop the table from backup
    // entirely rather than promise a restore this can't actually do.
    'planned_sessions': 'Planned Sessions',
    'workout_templates': 'Workout Templates',
    'workout_template_days': 'Workout Template Days',
    'todo_items': 'Todo Items',
    // Includes gender/birth year/units/hide-weight/steps-goal/home &
    // metric layout order/onboarding-complete — every plain key-value
    // setting lives in this one table already, nothing extra to add here.
    'app_settings': 'App Settings',
  };

  /// Superseded set used by `importFromJson` below, which still only
  /// understands the old JSON export shape — see that method's doc comment
  /// for why these two lists haven't been unified yet.
  static const _tables = [
    'exercises',
    'lift_sessions',
    'lift_sets',
    'bodyweight_log',
    'metrics_log',
    'cycle_log',
    'app_settings',
  ];

  /// Scoped by the active profile so a demo export can never collide with
  /// (or accidentally overwrite) a personal one, or vice versa. Written to
  /// the app's own documents directory first — Export then opens the OS
  /// share sheet on this file so the user can send it wherever they
  /// actually want it to live (email, Drive, Files, etc.); this internal
  /// copy is just the source `share_plus` reads from, not itself "the
  /// backup" the user should rely on.
  static Future<File> _exportFile() async {
    final dir = await getApplicationDocumentsDirectory();
    final suffix = AppServices.activeProfile.value == AppProfile.demo
        ? '_demo'
        : '';
    final date = DateTime.now().toIso8601String().split('T').first;
    return File(join(dir.path, 'TerrapinLift_Export_$date$suffix.xlsx'));
  }

  static Future<List<String>> _columnNames(Database db, String table) async {
    final info = await db.rawQuery('PRAGMA table_info($table)');
    return info.map((c) => c['name'] as String).toList();
  }

  static CellValue? _toCellValue(Object? value) {
    if (value == null) return null;
    if (value is int) return IntCellValue(value);
    if (value is double) {
      // The `excel` package writes a double via Dart's own toString(), but
      // its reader can't parse that back for NaN/Infinity or anything far
      // enough from zero to use scientific notation ("1e-7", "1e20", ...)
      // -- Excel.decodeBytes throws on those, which poisons the *whole*
      // import over one stray value (e.g. a rate computed from a
      // zero-length duration somewhere). Store those as text instead; a
      // normal-range double still round-trips as a real number.
      if (value.isNaN || value.isInfinite || value.toString().contains('e')) {
        return TextCellValue(value.toString());
      }
      return DoubleCellValue(value);
    }
    if (value is bool) return BoolCellValue(value);
    return TextCellValue(value.toString());
  }

  /// Inverse of `_toCellValue`, for reading a workbook back in. Matches the
  /// concrete `CellValue` subclasses the `excel` package hands back when
  /// decoding (not raw Dart values) — `IntCellValue`/`DoubleCellValue`/
  /// `BoolCellValue` unwrap directly, `TextCellValue` wraps a `TextSpan`
  /// whose own `toString()` reconstructs the plain text we originally wrote
  /// (no rich-text/styling was ever used on write, so this is always just
  /// the string). Anything else (a formula, a date typed directly into the
  /// sheet by hand, etc.) falls back to `toString()` rather than throwing —
  /// a cell manually edited into a shape this didn't expect should degrade
  /// to "stored as text," not fail the whole import.
  static Object? _fromCellValue(CellValue? value) {
    if (value == null) return null;
    if (value is IntCellValue) return value.value;
    if (value is DoubleCellValue) return value.value;
    if (value is BoolCellValue) {
      return value.value ? 1 : 0; // SQLite has no bool type
    }
    if (value is TextCellValue) return value.value.toString();
    return value.toString();
  }

  /// Writes every table to an .xlsx workbook (one sheet per table, a
  /// header row of the real DB column names, then one row per record) and
  /// returns its path.
  static Future<String> exportToFile() async {
    final db = await AppServices.db.database;
    final excel = Excel.createExcel();

    for (final entry in _exportTables.entries) {
      final columns = await _columnNames(db, entry.key);
      final rows = await db.query(entry.key);
      final sheet = excel[entry.value];
      sheet.appendRow([for (final c in columns) TextCellValue(c)]);
      for (final row in rows) {
        sheet.appendRow([for (final c in columns) _toCellValue(row[c])]);
      }
    }

    // `Excel.createExcel()` starts with one default empty sheet — drop it
    // now that every real table has its own, so the workbook doesn't open
    // on a blank "Sheet1" tab.
    final defaultSheet = excel.getDefaultSheet();
    if (defaultSheet != null && !_exportTables.values.contains(defaultSheet)) {
      excel.delete(defaultSheet);
    }

    final bytes = excel.encode()!;
    final file = await _exportFile();
    await file.writeAsBytes(bytes);
    return file.path;
  }

  /// Restores from an exported .xlsx workbook's raw bytes, picked from
  /// anywhere (see `SettingsScreen._import` — a file picker, not a fixed
  /// internal path). Each recognized table is wiped (`DELETE FROM`, not
  /// dropped) immediately before its rows are inserted, so import replaces
  /// that table's data rather than piling duplicates on top of whatever
  /// was already there — the user's own call: this app has no real use for
  /// merging two datasets, and restoring onto a non-empty install should
  /// mean "make it match the file," not "combine them." Scoped to only the
  /// tables actually present as a recognized sheet, though — a partial or
  /// older export (fewer sheets than this app currently has tables) must
  /// never wipe a table it has no replacement data for; `SettingsScreen`
  /// warns before calling this if there's existing data to lose. This is
  /// the current export format's counterpart; `importFromJson` below
  /// handles an older export someone might still have lying around.
  ///
  /// Sheet → table matching is by exact sheet name against `_exportTables`
  /// (case-sensitive — a sheet renamed by hand, e.g. in real Excel, won't
  /// be recognized; same "wrong file" outcome as picking something
  /// unrelated). Column matching within a recognized sheet is by the
  /// header row's text against that table's real DB columns
  /// (`PRAGMA table_info`) — a column that doesn't exist (typo'd by hand,
  /// or from a schema version this file predates) is silently skipped
  /// rather than failing the whole row, and `id` is always skipped so
  /// autoincrement assigns fresh ones, same as the JSON path.
  ///
  /// Returns `false` (not a throw) if the workbook decodes fine but not a
  /// single sheet name matches anything TerpinLift exports — "wrong file,"
  /// not a crash. A genuine decode failure (not a real .xlsx at all) still
  /// throws, so the caller can show a different message for that case.
  static Future<bool> importFromExcel(List<int> bytes) async {
    final excel = Excel.decodeBytes(bytes);
    final tableForSheet = {
      for (final entry in _exportTables.entries) entry.value: entry.key,
    };
    final recognizedSheets = excel.sheets.keys.where(tableForSheet.containsKey);
    if (recognizedSheets.isEmpty) return false;

    final db = await AppServices.db.database;
    final validColumnsByTable = <String, Set<String>>{};
    for (final table in tableForSheet.values) {
      validColumnsByTable[table] = (await _columnNames(db, table)).toSet();
    }

    await db.transaction((txn) async {
      for (final sheetName in recognizedSheets) {
        final table = tableForSheet[sheetName]!;
        final validColumns = validColumnsByTable[table]!;
        final rows = excel.sheets[sheetName]!.rows;
        // `app_settings` upserts by key instead (see below) rather than
        // being wiped — a settings key the import predates (added in a
        // newer app version than the file was exported from) shouldn't
        // get deleted just because this file has nothing to say about it.
        if (table != 'app_settings') {
          await txn.delete(table);
        }
        if (rows.length < 2) {
          continue; // header only (or empty) — table stays wiped, nothing to insert
        }

        final headers = [
          for (final cell in rows.first) cell?.value?.toString(),
        ];
        for (final row in rows.skip(1)) {
          final map = <String, Object?>{};
          for (var i = 0; i < headers.length && i < row.length; i++) {
            final column = headers[i];
            if (column == null || column == 'id') continue;
            if (!validColumns.contains(column)) continue;
            map[column] = _fromCellValue(row[i]?.value);
          }
          if (map.isEmpty) continue;
          // Every other table's real primary key is an autoincrement `id`
          // (skipped above, so a fresh one gets assigned — never
          // collides). `app_settings` has no `id` at all; `key` IS its
          // primary key, and every existing install already has rows for
          // it (onboarding_complete, gender, ...), so a plain insert
          // always hits a UNIQUE-constraint violation on the first row
          // and aborts the whole import. Restoring settings should
          // overwrite the existing value for that key anyway, so this
          // table alone imports as an upsert.
          await txn.insert(
            table,
            map,
            conflictAlgorithm: table == 'app_settings'
                ? ConflictAlgorithm.replace
                : ConflictAlgorithm.abort,
          );
        }
      }
    });
    AppServices.signalReload();
    return true;
  }

  /// Restores from an older export file's raw JSON content — the format
  /// `exportToFile` produced before it switched to `.xlsx`. Kept around so
  /// a backup made before that change is still restorable; not reachable
  /// from a fresh export anymore. Same insert-alongside-existing-rows
  /// behavior as `importFromExcel`, just over the original 7-table list
  /// that JSON export ever covered (`_tables`, not the fuller
  /// `_exportTables`) — those 7 are also the only ones a pre-2026-07-21
  /// export could possibly contain.
  ///
  /// Returns `false` (rather than throwing) for a file that parses as JSON
  /// but isn't recognizably a TerpinLift export (no known table keys at
  /// all) — a wrong-file pick should read as "that's not it," not crash the
  /// app. A genuine parse failure (not JSON at all) still throws, since the
  /// caller needs to distinguish "not our format" from "not JSON," which
  /// get different error messages shown back to the user.
  static Future<bool> importFromJson(String jsonContent) async {
    final dump = jsonDecode(jsonContent) as Map<String, dynamic>;
    if (!_tables.any(dump.containsKey)) return false;

    final db = await AppServices.db.database;
    await db.transaction((txn) async {
      for (final table in _tables) {
        // Skip a table this particular file has nothing for entirely,
        // rather than wiping it anyway — same reasoning as
        // importFromExcel: a table the export doesn't cover shouldn't
        // lose its existing data with nothing to replace it.
        if (!dump.containsKey(table)) continue;
        final rows = dump[table] as List<dynamic>? ?? [];
        if (table != 'app_settings') {
          await txn.delete(table);
        }
        for (final row in rows) {
          final map = Map<String, dynamic>.from(row as Map);
          map.remove('id'); // let autoincrement assign fresh ids
          // Same fix as importFromExcel: app_settings' real primary key is
          // `key`, not `id`, and every existing install already has rows
          // for it — a plain insert always conflicts, so this table
          // upserts instead.
          await txn.insert(
            table,
            map,
            conflictAlgorithm: table == 'app_settings'
                ? ConflictAlgorithm.replace
                : ConflictAlgorithm.abort,
          );
        }
      }
    });
    AppServices.signalReload();
    return true;
  }

  static Future<String> exportFilePath() async => (await _exportFile()).path;

  /// Whether the active profile has anything a wipe-then-import would
  /// actually destroy, so `SettingsScreen` can skip the "this will erase
  /// your data" warning on a genuinely fresh install. Deliberately
  /// excludes `exercises` (always populated by seeded defaults, even on a
  /// brand new profile) and `app_settings` (import upserts it rather than
  /// wiping it, and it always has rows from onboarding regardless) — this
  /// checks for real logged content, not just "has this profile been
  /// opened before."
  static Future<bool> hasAnyLoggedData() async {
    final db = await AppServices.db.database;
    for (final table in _exportTables.keys) {
      if (table == 'exercises' || table == 'app_settings') continue;
      final result = await db.rawQuery('SELECT 1 FROM $table LIMIT 1');
      if (result.isNotEmpty) return true;
    }
    return false;
  }
}
