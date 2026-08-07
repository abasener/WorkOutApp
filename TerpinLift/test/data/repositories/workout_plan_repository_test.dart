import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:terpinlift/data/database.dart';
import 'package:terpinlift/data/models/exercise.dart';
import 'package:terpinlift/data/models/workout_plan.dart';
import 'package:terpinlift/data/profile_manager.dart';
import 'package:terpinlift/data/repositories/workout_plan_repository.dart';

/// `replaceTemplateDays` is the core of "replace this template on import
/// without breaking history" (designFiles/10_WORKOUT_PLANNER.md) — a day a
/// past `planned_sessions` row already references must keep resolving to
/// the same id even after the template it belongs to gets replaced, rather
/// than getting deleted-and-recreated with a fresh id the old session can
/// no longer find. Exercised against real sqlite (`sqflite_common_ffi`),
/// same precedent as `backup_service_import_test.dart`.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory tempDir;
  late DatabaseHelper db;
  late WorkoutPlanRepository repo;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('workout_plan_repo_test');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => tempDir.path,
        );
    db = DatabaseHelper(profile: AppProfile.personal);
    await db.database;
    repo = WorkoutPlanRepository(db);
  });

  tearDown(() async {
    await db.close();
    await tempDir.delete(recursive: true);
  });

  Future<int> insertTemplateWithDays(List<String> labels) async {
    final templateId = await repo.insertTemplate(
      const WorkoutTemplate(name: 'Test Plan', created: '2026-08-04'),
    );
    for (var i = 0; i < labels.length; i++) {
      await repo.insertDay(
        WorkoutTemplateDay(
          templateId: templateId,
          dayOrder: i,
          dayLabel: labels[i],
          patterns: const [MovementPattern.squat],
        ),
      );
    }
    return templateId;
  }

  test('a day matched by position is updated in place, not deleted+recreated '
      '— its id stays stable', () async {
    final templateId = await insertTemplateWithDays(['Day A', 'Day B']);
    final before = await repo.getDaysForTemplate(templateId);
    final dayBId = before[1].id!;

    await repo.replaceTemplateDays(templateId, const [
      WorkoutTemplateDay(
        templateId: 0,
        dayOrder: 0,
        dayLabel: 'Day A (edited)',
        patterns: [MovementPattern.hinge],
      ),
      WorkoutTemplateDay(
        templateId: 0,
        dayOrder: 1,
        dayLabel: 'Day B (edited)',
        patterns: [MovementPattern.core],
      ),
    ]);

    final after = await repo.getDaysForTemplate(templateId);
    expect(after, hasLength(2));
    expect(after[1].id, dayBId);
    expect(after[1].dayLabel, 'Day B (edited)');
    expect(after[1].patterns, [MovementPattern.core]);
  });

  test('a day dropped from the replacement file is soft-hidden, not deleted — '
      'still resolvable by id (so old history keeps working) but excluded '
      'from getDaysForTemplate', () async {
    final templateId = await insertTemplateWithDays([
      'Day A',
      'Day B',
      'Day C',
    ]);
    final before = await repo.getDaysForTemplate(templateId);
    final dayCId = before[2].id!;

    await repo.replaceTemplateDays(templateId, const [
      WorkoutTemplateDay(
        templateId: 0,
        dayOrder: 0,
        dayLabel: 'Day A',
        patterns: [MovementPattern.squat],
      ),
      WorkoutTemplateDay(
        templateId: 0,
        dayOrder: 1,
        dayLabel: 'Day B',
        patterns: [MovementPattern.squat],
      ),
    ]);

    final active = await repo.getDaysForTemplate(templateId);
    expect(active.map((d) => d.id), isNot(contains(dayCId)));

    // Still resolvable directly by id — a `planned_sessions` row logged
    // against the old Day C must still be able to look this up.
    final stillThere = await repo.getDay(dayCId);
    expect(stillThere, isNotNull);
    expect(stillThere!.active, isFalse);

    final allById = await repo.getAllDaysById();
    expect(allById.containsKey(dayCId), isTrue);
  });

  test(
    'a replacement file with more days than exist today appends the extras',
    () async {
      final templateId = await insertTemplateWithDays(['Day A']);

      await repo.replaceTemplateDays(templateId, const [
        WorkoutTemplateDay(
          templateId: 0,
          dayOrder: 0,
          dayLabel: 'Day A',
          patterns: [MovementPattern.squat],
        ),
        WorkoutTemplateDay(
          templateId: 0,
          dayOrder: 1,
          dayLabel: 'Day B (new)',
          patterns: [MovementPattern.hinge],
        ),
      ]);

      final after = await repo.getDaysForTemplate(templateId);
      expect(after, hasLength(2));
      expect(after[1].dayLabel, 'Day B (new)');
    },
  );
}
