import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:terpinlift/data/database.dart';
import 'package:terpinlift/data/models/hiit_routine.dart';
import 'package:terpinlift/data/models/hiit_slot.dart';
import 'package:terpinlift/data/profile_manager.dart';
import 'package:terpinlift/data/repositories/hiit_routine_repository.dart';

/// A saved HIIT routine round-trips correctly, and `replaceRoutine`
/// overwrites both the routine row and its whole slot list in one go — a
/// saved routine has no history depending on it (unlike a workout-plan
/// template's days), so a plain delete+reinsert is the correct, simpler
/// behavior here (see designFiles/10_WORKOUT_PLANNER.md). Exercised against
/// real sqlite, same precedent as the other repository tests this session.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory tempDir;
  late DatabaseHelper db;
  late HiitRoutineRepository repo;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('hiit_routine_repo_test');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => tempDir.path,
        );
    db = DatabaseHelper(profile: AppProfile.personal);
    await db.database;
    repo = HiitRoutineRepository(db);
  });

  tearDown(() async {
    await db.close();
    await tempDir.delete(recursive: true);
  });

  test('a saved routine and its slots round-trip', () async {
    final routineId = await repo.insertRoutine(
      const HiitRoutine(
        name: 'Arm Day',
        automatic: true,
        created: '2026-08-04',
      ),
    );
    await repo.insertRoutineSlots([
      HiitRoutineSlot(
        hiitRoutineId: routineId,
        sequenceIndex: 0,
        groupIndex: 0,
        exerciseId: 1,
        exerciseKind: HiitExerciseKind.lift,
        targetType: HiitTargetType.reps,
        targetValue: 12,
        weight: 20,
        restAfterSeconds: 30,
      ),
    ]);

    final routines = await repo.getAllRoutines();
    expect(routines, hasLength(1));
    expect(routines.single.name, 'Arm Day');
    expect(routines.single.automatic, isTrue);

    final slots = await repo.getSlotsForRoutine(routineId);
    expect(slots, hasLength(1));
    expect(slots.single.targetValue, 12);
    expect(slots.single.weight, 20);
  });

  test(
    'replaceRoutine overwrites the name/mode and swaps out every slot',
    () async {
      final routineId = await repo.insertRoutine(
        const HiitRoutine(name: 'Old Name', created: '2026-08-04'),
      );
      await repo.insertRoutineSlots([
        HiitRoutineSlot(
          hiitRoutineId: routineId,
          sequenceIndex: 0,
          groupIndex: 0,
          exerciseId: 1,
          exerciseKind: HiitExerciseKind.lift,
          targetType: HiitTargetType.reps,
          targetValue: 10,
        ),
      ]);

      await repo.replaceRoutine(
        routineId,
        const HiitRoutine(
          name: 'New Name',
          automatic: true,
          created: '2026-08-04',
        ),
        [
          HiitRoutineSlot(
            hiitRoutineId: routineId,
            sequenceIndex: 0,
            groupIndex: 0,
            exerciseId: 2,
            exerciseKind: HiitExerciseKind.cardio,
            targetType: HiitTargetType.distance,
            targetValue: 500,
          ),
        ],
      );

      final routines = await repo.getAllRoutines();
      expect(routines, hasLength(1));
      expect(routines.single.name, 'New Name');
      expect(routines.single.automatic, isTrue);

      final slots = await repo.getSlotsForRoutine(routineId);
      expect(slots, hasLength(1));
      expect(slots.single.exerciseId, 2);
      expect(slots.single.targetType, HiitTargetType.distance);
    },
  );

  test('getRoutineByName finds an exact match, null otherwise', () async {
    await repo.insertRoutine(
      const HiitRoutine(name: 'Leg Day', created: '2026-08-04'),
    );
    expect((await repo.getRoutineByName('Leg Day'))?.name, 'Leg Day');
    expect(await repo.getRoutineByName('Nonexistent'), isNull);
  });
}
