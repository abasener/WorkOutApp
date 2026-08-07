import 'dart:io';

import 'package:excel/excel.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:terpinlift/data/database.dart';
import 'package:terpinlift/data/profile_manager.dart';
import 'package:terpinlift/services/app_services.dart';
import 'package:terpinlift/services/backup_service.dart';

/// Exercises the real import path against real sqlite (via
/// `sqflite_common_ffi`, no device/emulator needed) rather than reasoning
/// about the code by inspection alone — this is a data-migration bug fix
/// going into a real release, so it's worth the real thing.
///
/// The fixture below deliberately mirrors the shape that broke a real
/// restore (2026-07-26): an old export whose `exercises`/`lift_sessions`/
/// `lift_sets` ids don't (and structurally can't) match a freshly-seeded
/// database's own ids for the same exercises — `Deadlift`'s old id (`20`)
/// is arbitrary and collides with nothing meaningful on the target db, and
/// `Squat Rack Curls` has no name match at all, so it should land as a
/// genuinely new exercise instead.
const _fixtureJson = '''
{
  "exercises": [
    {"id": 20, "name": "Deadlift", "category": "back,legs,pull", "is_seeded": 1, "youtube_url": null, "created": "2026-07-10", "equipment_tags": "compound", "pinned": 1, "movement_patterns": "hinge", "goal_source": "standard", "progress_metric": null, "notes": null, "target_muscles": null, "cardio_unit": null},
    {"id": 999, "name": "Squat Rack Curls", "category": "arms", "is_seeded": 0, "youtube_url": null, "created": "2026-07-10", "equipment_tags": "isolation", "pinned": 0, "movement_patterns": null, "goal_source": null, "progress_metric": null, "notes": null, "target_muscles": null, "cardio_unit": null}
  ],
  "lift_sessions": [
    {"id": 165, "exercise_id": 20, "date": "2026-07-11", "started_at": "2026-07-11T18:45:52.354317", "completed_at": "2026-07-11T19:10:52.859825", "notes": null},
    {"id": 200, "exercise_id": 999, "date": "2026-07-12", "started_at": "2026-07-12T18:00:00.000000", "completed_at": "2026-07-12T18:10:00.000000", "notes": null}
  ],
  "lift_sets": [
    {"id": 554, "session_id": 165, "set_number": 1, "reps": 5, "weight": 135.0, "rpe": 7.0, "set_started_at": null, "set_completed_at": null},
    {"id": 555, "session_id": 165, "set_number": 2, "reps": 5, "weight": 135.0, "rpe": 9.0, "set_started_at": null, "set_completed_at": null},
    {"id": 700, "session_id": 200, "set_number": 1, "reps": 12, "weight": 30.0, "rpe": 6.0, "set_started_at": null, "set_completed_at": null}
  ],
  "bodyweight_log": [{"id": 1, "date": "2026-07-11", "weight": 180.5}],
  "metrics_log": [],
  "cycle_log": [],
  "app_settings": [{"key": "steps_goal", "value": "9000"}]
}
''';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('backup_service_test');
    // ProfileManager.dbPath -> getApplicationDocumentsDirectory(), which has
    // no real platform implementation under `flutter test` — fake the
    // channel to point at a throwaway temp dir instead.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => tempDir.path,
        );
    AppServices.db = DatabaseHelper(profile: AppProfile.personal);
    await AppServices.db.database; // forces onCreate + default exercise seed
  });

  tearDown(() async {
    await AppServices.db.close();
    await tempDir.delete(recursive: true);
  });

  test('importFromJson: an old export whose exercise/session ids do not match '
      'this (freshly-seeded) database imports cleanly instead of throwing '
      'FOREIGN KEY constraint failed', () async {
    final ok = await BackupService.importFromJson(_fixtureJson);
    expect(ok, isTrue);

    final db = await AppServices.db.database;

    final sessions = await db.query('lift_sessions');
    final sets = await db.query('lift_sets');
    expect(sessions, hasLength(2));
    expect(sets, hasLength(3));

    // Deadlift already existed from the default seed — matched by name,
    // not duplicated.
    final deadlifts = await db.query(
      'exercises',
      where: 'name = ?',
      whereArgs: ['Deadlift'],
    );
    expect(deadlifts, hasLength(1));

    // The genuinely new exercise was added, not silently dropped.
    final custom = await db.query(
      'exercises',
      where: 'name = ?',
      whereArgs: ['Squat Rack Curls'],
    );
    expect(custom, hasLength(1));

    // The session that referenced the *old* file's exercise_id (20)
    // resolves, via a real SQL join, to the actual Deadlift row in this
    // database — not to whatever unrelated exercise now owns id 20 (the
    // exact failure mode this fixes), and not a dangling reference.
    final deadliftSession = await db.rawQuery('''
        SELECT e.name FROM lift_sessions s
        JOIN exercises e ON e.id = s.exercise_id
        WHERE s.date = '2026-07-11'
      ''');
    expect(deadliftSession, hasLength(1));
    expect(deadliftSession.first['name'], 'Deadlift');

    final customSession = await db.rawQuery('''
        SELECT e.name FROM lift_sessions s
        JOIN exercises e ON e.id = s.exercise_id
        WHERE s.date = '2026-07-12'
      ''');
    expect(customSession.first['name'], 'Squat Rack Curls');

    // Sets correctly followed their session through the same remap.
    final deadliftSets = await db.rawQuery('''
        SELECT COUNT(*) as c FROM lift_sets ls
        JOIN lift_sessions s ON s.id = ls.session_id
        WHERE s.date = '2026-07-11'
      ''');
    expect(deadliftSets.first['c'], 2);

    // app_settings upserted (steps_goal key already exists from onboarding
    // defaults, this should overwrite it, not conflict/throw).
    final stepsGoal = await db.query(
      'app_settings',
      where: 'key = ?',
      whereArgs: ['steps_goal'],
    );
    expect(stepsGoal.single['value'], '9000');
  });

  test(
    'importFromJson: re-importing the same file a second time does not '
    'duplicate the matched-by-name exercise or double the session count',
    () async {
      await BackupService.importFromJson(_fixtureJson);
      await BackupService.importFromJson(_fixtureJson);

      final db = await AppServices.db.database;
      final deadlifts = await db.query(
        'exercises',
        where: 'name = ?',
        whereArgs: ['Deadlift'],
      );
      expect(deadlifts, hasLength(1));

      final custom = await db.query(
        'exercises',
        where: 'name = ?',
        whereArgs: ['Squat Rack Curls'],
      );
      expect(custom, hasLength(1));

      // lift_sessions/lift_sets are wiped-then-reinserted each import (by
      // design, restore replaces this table's data), so a second import
      // should still land at exactly the file's own row counts, not
      // doubled.
      final sessions = await db.query('lift_sessions');
      expect(sessions, hasLength(2));
    },
  );

  test(
    'importFromExcel: a hiit_slots row with a null lift_set_id/'
    'cardio_entry_id is not dropped as a dangling reference (2026-08-04 '
    'fix — those two nullable columns joined `_foreignKeys` alongside a '
    'fix distinguishing "nothing to remap" from "remap target missing"). '
    'hiit_sessions/hiit_slots only ever round-trip through the .xlsx path, '
    'not the legacy JSON one, so this exercises importFromExcel directly',
    () async {
      final excel = Excel.createExcel();

      final exercisesSheet = excel['Exercises'];
      exercisesSheet.appendRow([
        for (final c in [
          'id',
          'name',
          'category',
          'is_seeded',
          'youtube_url',
          'created',
          'equipment_tags',
          'pinned',
          'movement_patterns',
          'goal_source',
          'progress_metric',
          'notes',
          'target_muscles',
          'cardio_unit',
        ])
          TextCellValue(c),
      ]);
      exercisesSheet.appendRow([
        IntCellValue(20),
        TextCellValue('Deadlift'),
        TextCellValue('back,legs,pull'),
        IntCellValue(1),
        null,
        TextCellValue('2026-07-10'),
        TextCellValue('compound'),
        IntCellValue(1),
        TextCellValue('hinge'),
        TextCellValue('standard'),
        null,
        null,
        null,
        null,
      ]);

      final hiitSessionsSheet = excel['HIIT Sessions'];
      hiitSessionsSheet.appendRow([
        for (final c in [
          'id',
          'date',
          'notes',
          'started_at',
          'completed_at',
          'status',
          'automatic',
          'current_sequence_index',
          'current_phase',
          'phase_started_at',
          'phase_remaining_seconds',
          'current_reps_remaining',
          'paused',
          'total_paused_seconds',
        ])
          TextCellValue(c),
      ]);
      hiitSessionsSheet.appendRow([
        IntCellValue(5),
        TextCellValue('2026-07-11'),
        null,
        TextCellValue('2026-07-11T18:00:00.000000'),
        TextCellValue('2026-07-11T18:25:00.000000'),
        TextCellValue('completed'),
        IntCellValue(0),
        IntCellValue(0),
        TextCellValue('work'),
        null,
        null,
        null,
        IntCellValue(0),
        DoubleCellValue(0.0),
      ]);

      final hiitSlotsSheet = excel['HIIT Slots'];
      hiitSlotsSheet.appendRow([
        for (final c in [
          'id',
          'hiit_session_id',
          'sequence_index',
          'group_index',
          'exercise_id',
          'exercise_kind',
          'target_type',
          'target_value',
          'weight',
          'rest_after_seconds',
          'actual_reps',
          'actual_weight',
          'actual_time_seconds',
          'actual_distance',
          'actual_load',
          'lift_set_id',
          'cardio_entry_id',
        ])
          TextCellValue(c),
      ]);
      hiitSlotsSheet.appendRow([
        IntCellValue(40),
        IntCellValue(5),
        IntCellValue(0),
        IntCellValue(0),
        IntCellValue(20),
        TextCellValue('lift'),
        TextCellValue('reps'),
        DoubleCellValue(5.0),
        DoubleCellValue(135.0),
        IntCellValue(60),
        IntCellValue(5),
        DoubleCellValue(135.0),
        null,
        null,
        null,
        null, // lift_set_id: not yet populated by any real code path
        null, // cardio_entry_id: ditto
      ]);

      final defaultSheet = excel.getDefaultSheet();
      if (defaultSheet != null &&
          ![
            'Exercises',
            'HIIT Sessions',
            'HIIT Slots',
          ].contains(defaultSheet)) {
        excel.delete(defaultSheet);
      }

      final ok = await BackupService.importFromExcel(excel.encode()!);
      expect(ok, isTrue);

      final db = await AppServices.db.database;
      final slots = await db.query('hiit_slots');
      expect(slots, hasLength(1));
      expect(slots.single['lift_set_id'], isNull);
      expect(slots.single['cardio_entry_id'], isNull);

      // exercise_id (a required, non-null reference) still went through the
      // normal name-matched remap despite the two nullable columns sitting
      // right next to it in the same row.
      final deadliftSlot = await db.rawQuery('''
          SELECT e.name FROM hiit_slots hs
          JOIN exercises e ON e.id = hs.exercise_id
        ''');
      expect(deadliftSlot.single['name'], 'Deadlift');
    },
  );
}
