import 'dart:io';

import 'package:excel/excel.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:terpinlift/data/database.dart';
import 'package:terpinlift/data/models/exercise.dart';
import 'package:terpinlift/data/models/hiit_routine.dart';
import 'package:terpinlift/data/models/hiit_slot.dart';
import 'package:terpinlift/data/models/workout_plan.dart';
import 'package:terpinlift/data/profile_manager.dart';
import 'package:terpinlift/data/repositories/exercise_repository.dart';
import 'package:terpinlift/data/repositories/hiit_routine_repository.dart';
import 'package:terpinlift/data/repositories/workout_plan_repository.dart';
import 'package:terpinlift/services/app_services.dart';
import 'package:terpinlift/services/plan_export_service.dart';

/// The friendly export/import round trip is the highest-risk new logic in
/// this pass — text written to a spreadsheet has to parse back into the
/// same shape, which `flutter analyze` can't verify. Exercised against
/// real sqlite + a real encoded `.xlsx` (via `sqflite_common_ffi`/`excel`),
/// same precedent as this session's other repository tests.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory tempDir;
  late DatabaseHelper db;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('plan_export_test');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => tempDir.path,
        );
    db = DatabaseHelper(profile: AppProfile.personal);
    await db.database;
    // PlanExportService reads through AppServices' repositories directly —
    // bind the ones it touches (mirrors AppServices._bindRepositories,
    // which is private to that file).
    AppServices.db = db;
    AppServices.exercises = ExerciseRepository(db);
    AppServices.hiitRoutines = HiitRoutineRepository(db);
    AppServices.workoutPlans = WorkoutPlanRepository(db);
  });

  tearDown(() async {
    await db.close();
    await tempDir.delete(recursive: true);
  });

  test(
    'a saved HIIT routine exports and parses back with the same shape',
    () async {
      final exercises = await AppServices.exercises.getAll();
      final pushUp = exercises.firstWhere((e) => e.name == 'Push Up');
      final curl = exercises.firstWhere((e) => e.name == 'Dumbbell Curl');

      final routineId = await AppServices.hiitRoutines.insertRoutine(
        const HiitRoutine(
          name: 'Arm Day Test',
          automatic: true,
          created: '2026-08-04',
        ),
      );
      await AppServices.hiitRoutines.insertRoutineSlots([
        HiitRoutineSlot(
          hiitRoutineId: routineId,
          sequenceIndex: 0,
          groupIndex: 0,
          exerciseId: pushUp.id!,
          exerciseKind: HiitExerciseKind.lift,
          targetType: HiitTargetType.reps,
          targetValue: 15,
          weight: 0,
          restAfterSeconds: 20,
        ),
        HiitRoutineSlot(
          hiitRoutineId: routineId,
          sequenceIndex: 1,
          groupIndex: 0,
          exerciseId: curl.id!,
          exerciseKind: HiitExerciseKind.lift,
          targetType: HiitTargetType.amrap,
          targetValue: 30,
          weight: 20,
        ),
      ]);

      final path = await PlanExportService.exportHiitRoutines();
      final bytes = await File(path).readAsBytes();
      final parsed = await PlanExportService.parseHiitImport(bytes);

      // Export also always includes the 3 hardcoded presets as their own
      // sheets — find this test's own saved routine by name rather than
      // assuming it's the only sheet.
      final routine = parsed.firstWhere((r) => r.name == 'Arm Day Test');
      expect(routine.automatic, isTrue);
      expect(routine.alreadyExists, isTrue);
      expect(routine.unmatchedExerciseNames, isEmpty);
      expect(routine.slots, hasLength(2));

      final pushUpSlot = routine.slots.firstWhere(
        (s) => s.exerciseId == pushUp.id,
      );
      expect(pushUpSlot.targetType, HiitTargetType.reps);
      expect(pushUpSlot.targetValue, 15);
      expect(pushUpSlot.restAfterSeconds, 20);

      final curlSlot = routine.slots.firstWhere((s) => s.exerciseId == curl.id);
      expect(curlSlot.targetType, HiitTargetType.amrap);
      expect(curlSlot.weight, 20);
    },
  );

  test(
    'a distance-type cardio slot round-trips through the exercise\'s own '
    "display unit, not a bare canonical number (Ruck's default is miles)",
    () async {
      final exercises = await AppServices.exercises.getAll();
      final ruck = exercises.firstWhere((e) => e.name == 'Ruck');

      final routineId = await AppServices.hiitRoutines.insertRoutine(
        const HiitRoutine(name: 'Ruck Test', created: '2026-08-04'),
      );
      await AppServices.hiitRoutines.insertRoutineSlots([
        HiitRoutineSlot(
          hiitRoutineId: routineId,
          sequenceIndex: 0,
          groupIndex: 0,
          exerciseId: ruck.id!,
          exerciseKind: HiitExerciseKind.cardio,
          targetType: HiitTargetType.distance,
          // Canonical meters for 0.5 miles.
          targetValue: 0.5 * 1609.34,
        ),
      ]);

      final path = await PlanExportService.exportHiitRoutines();
      final bytes = await File(path).readAsBytes();

      // The sheet itself should show a human distance, not raw meters.
      final excel = Excel.decodeBytes(bytes);
      final sheet = excel['Ruck Test'];
      final allCellTexts = [
        for (final row in sheet.rows)
          for (final cell in row)
            if (cell?.value != null) cell!.value.toString(),
      ];
      expect(allCellTexts.any((t) => t == 'mi'), isTrue);
      expect(allCellTexts.any((t) => t.contains('804')), isFalse);
      expect(excel.sheets.keys, contains('All Exercises'));

      final parsed = await PlanExportService.parseHiitImport(bytes);
      final routine = parsed.firstWhere((r) => r.name == 'Ruck Test');
      expect(routine.slots.single.targetValue, closeTo(0.5 * 1609.34, 0.5));
    },
  );

  test('an exercise name with no match in this install is skipped and '
      'reported, not silently dropping the whole routine', () async {
    final exercises = await AppServices.exercises.getAll();
    final pushUp = exercises.firstWhere((e) => e.name == 'Push Up');

    final routineId = await AppServices.hiitRoutines.insertRoutine(
      const HiitRoutine(name: 'Mixed Routine', created: '2026-08-04'),
    );
    await AppServices.hiitRoutines.insertRoutineSlots([
      HiitRoutineSlot(
        hiitRoutineId: routineId,
        sequenceIndex: 0,
        groupIndex: 0,
        exerciseId: pushUp.id!,
        exerciseKind: HiitExerciseKind.lift,
        targetType: HiitTargetType.reps,
        targetValue: 10,
      ),
    ]);

    final path = await PlanExportService.exportHiitRoutines();
    var bytes = await File(path).readAsBytes();

    // Delete the exercise from this "other install" before re-importing,
    // simulating a name that doesn't exist there.
    final rawDb = await db.database;
    await rawDb.delete('exercises', where: 'id = ?', whereArgs: [pushUp.id]);

    final parsed = await PlanExportService.parseHiitImport(bytes);
    final mixed = parsed.firstWhere((r) => r.name == 'Mixed Routine');
    expect(mixed.slots, isEmpty);
    expect(mixed.unmatchedExerciseNames, ['Push Up']);
  });

  test('a saved Workout Plan template exports and parses back with the same '
      'days/patterns', () async {
    final templateId = await AppServices.workoutPlans.insertTemplate(
      const WorkoutTemplate(name: 'Custom Rotation', created: '2026-08-04'),
    );
    await AppServices.workoutPlans.insertDay(
      WorkoutTemplateDay(
        templateId: templateId,
        dayOrder: 0,
        dayLabel: 'Push Day',
        patterns: const [
          MovementPattern.horizontalPush,
          MovementPattern.verticalPush,
        ],
      ),
    );
    await AppServices.workoutPlans.insertDay(
      WorkoutTemplateDay(
        templateId: templateId,
        dayOrder: 1,
        dayLabel: 'Leg Day',
        patterns: const [MovementPattern.squat],
      ),
    );

    final path = await PlanExportService.exportWorkoutTemplates();
    final bytes = await File(path).readAsBytes();
    final parsed = await PlanExportService.parseWorkoutPlanImport(bytes);

    // A fresh DB also seeds a default "Rotating Full-Body" template, whose
    // own sheet also round-trips fine — find this test's own by name
    // rather than assuming it's the only one exported.
    final template = parsed.firstWhere((t) => t.name == 'Custom Rotation');
    expect(template.alreadyExists, isTrue);
    expect(template.days, hasLength(2));
    expect(template.days[0].dayLabel, 'Push Day');
    expect(template.days[0].patterns, [
      MovementPattern.horizontalPush,
      MovementPattern.verticalPush,
    ]);
    expect(template.days[1].dayLabel, 'Leg Day');
    expect(template.days[1].patterns, [MovementPattern.squat]);
  });

  test('a day with more than 4 patterns is not truncated on export or import '
      '— no fixed column limit', () async {
    final templateId = await AppServices.workoutPlans.insertTemplate(
      const WorkoutTemplate(name: 'Bodybuilder Split', created: '2026-08-04'),
    );
    const sixPatterns = [
      MovementPattern.squat,
      MovementPattern.hinge,
      MovementPattern.horizontalPush,
      MovementPattern.verticalPush,
      MovementPattern.horizontalPull,
      MovementPattern.core,
    ];
    await AppServices.workoutPlans.insertDay(
      WorkoutTemplateDay(
        templateId: templateId,
        dayOrder: 0,
        dayLabel: 'Everything Day',
        patterns: sixPatterns,
      ),
    );

    final path = await PlanExportService.exportWorkoutTemplates();
    final bytes = await File(path).readAsBytes();
    final parsed = await PlanExportService.parseWorkoutPlanImport(bytes);

    final template = parsed.firstWhere((t) => t.name == 'Bodybuilder Split');
    expect(template.days.single.patterns, sixPatterns);
  });

  test('the pattern-reference table lists which lifts satisfy each pattern, '
      "and isn't mistaken for more days", () async {
    final templateId = await AppServices.workoutPlans.insertTemplate(
      const WorkoutTemplate(name: 'Reference Test', created: '2026-08-04'),
    );
    await AppServices.workoutPlans.insertDay(
      WorkoutTemplateDay(
        templateId: templateId,
        dayOrder: 0,
        dayLabel: 'Squat Day',
        patterns: const [MovementPattern.squat],
      ),
    );

    final path = await PlanExportService.exportWorkoutTemplates();
    final bytes = await File(path).readAsBytes();
    final parsed = await PlanExportService.parseWorkoutPlanImport(bytes);

    final template = parsed.firstWhere((t) => t.name == 'Reference Test');
    // Exactly the one real day — the reference table below it must not
    // have been read as additional days.
    expect(template.days, hasLength(1));

    final excel = Excel.decodeBytes(bytes);
    final sheet = excel['Reference Test'];
    final allCellTexts = [
      for (final row in sheet.rows)
        for (final cell in row)
          if (cell?.value != null) cell!.value.toString(),
    ];
    expect(
      allCellTexts.any((t) => t.contains('Back Squat')),
      isTrue,
      reason: 'reference table should list a real squat-pattern exercise',
    );
    // Every pattern gets a reference row, not just the ones actually used
    // in a day today — helps building a plan from scratch.
    expect(allCellTexts.any((t) => t.contains('Core')), isTrue);

    // Squat is a "main" pattern — its per-day role row should say so.
    expect(allCellTexts.any((t) => t == 'Main'), isTrue);

    // Both exports carry the same lift-name lookup sheet.
    expect(excel.sheets.keys, contains('All Exercises'));
    final exerciseSheetTexts = [
      for (final row in excel['All Exercises'].rows)
        for (final cell in row)
          if (cell?.value != null) cell!.value.toString(),
    ];
    expect(exerciseSheetTexts, contains('Back Squat'));
  });

  test('commitHiitImport: Add creates a separately-named copy, Replace '
      'overwrites the existing one', () async {
    final exercises = await AppServices.exercises.getAll();
    final pushUp = exercises.firstWhere((e) => e.name == 'Push Up');

    final routineId = await AppServices.hiitRoutines.insertRoutine(
      const HiitRoutine(name: 'Base Routine', created: '2026-08-04'),
    );
    await AppServices.hiitRoutines.insertRoutineSlots([
      HiitRoutineSlot(
        hiitRoutineId: routineId,
        sequenceIndex: 0,
        groupIndex: 0,
        exerciseId: pushUp.id!,
        exerciseKind: HiitExerciseKind.lift,
        targetType: HiitTargetType.reps,
        targetValue: 10,
      ),
    ]);

    final parsed = ParsedHiitRoutine(
      name: 'Base Routine',
      automatic: true,
      slots: [
        HiitRoutineSlot(
          hiitRoutineId: 0,
          sequenceIndex: 0,
          groupIndex: 0,
          exerciseId: pushUp.id!,
          exerciseKind: HiitExerciseKind.lift,
          targetType: HiitTargetType.reps,
          targetValue: 25,
        ),
      ],
      unmatchedExerciseNames: const [],
      alreadyExists: true,
    );

    await PlanExportService.commitHiitImport([
      HiitImportDecision(parsed: parsed, add: true),
    ]);
    final afterAdd = await AppServices.hiitRoutines.getAllRoutines();
    expect(
      afterAdd.map((r) => r.name),
      containsAll(['Base Routine', 'Base Routine (2)']),
    );

    await PlanExportService.commitHiitImport([
      HiitImportDecision(parsed: parsed, add: false),
    ]);
    final afterReplace = await AppServices.hiitRoutines.getAllRoutines();
    // Still exactly the same two names — Replace overwrote in place,
    // didn't add a third.
    expect(afterReplace, hasLength(2));
    final baseSlots = await AppServices.hiitRoutines.getSlotsForRoutine(
      routineId,
    );
    expect(baseSlots.single.targetValue, 25);
  });

  test('a HIIT sheet with blank Weight/Rest/Target Value cells parses to null '
      'for those fields instead of throwing — real users will leave cells '
      'blank for a bodyweight exercise or "no rest"', () async {
    final exercises = await AppServices.exercises.getAll();
    final pushUp = exercises.firstWhere((e) => e.name == 'Push Up');

    final excel = Excel.createExcel();
    final sheet = excel['Sparse Routine'];
    sheet.appendRow([TextCellValue('Automatic'), BoolCellValue(false)]);
    sheet.appendRow([TextCellValue('Round 1')]);
    sheet.appendRow([
      TextCellValue('Exercise'),
      TextCellValue('Kind'),
      TextCellValue('Target Type'),
      TextCellValue('Target Value'),
      TextCellValue('Unit'),
      TextCellValue('Weight (lb)'),
      TextCellValue('Rest After (sec)'),
    ]);
    // Only the exercise name and target type are filled in — everything
    // else (target value, unit, weight, rest) is left blank, same as a
    // real user just skipping cells they don't care about.
    sheet.appendRow([TextCellValue(pushUp.name), null, TextCellValue('Reps')]);
    final defaultSheet = excel.getDefaultSheet();
    if (defaultSheet != null && defaultSheet != 'Sparse Routine') {
      excel.delete(defaultSheet);
    }

    final parsed = await PlanExportService.parseHiitImport(excel.encode()!);
    final routine = parsed.firstWhere((r) => r.name == 'Sparse Routine');
    expect(routine.slots, hasLength(1));
    final slot = routine.slots.single;
    expect(slot.exerciseId, pushUp.id);
    expect(slot.targetType, HiitTargetType.reps);
    expect(slot.targetValue, isNull);
    expect(slot.weight, isNull);
    expect(slot.restAfterSeconds, isNull);
    // A blank Kind column doesn't matter — Kind is derived from the
    // matched exercise's real equipment tags, not read from the sheet.
    expect(slot.exerciseKind, HiitExerciseKind.lift);
  });

  test('commitHiitImport: Add when nothing exists yet just inserts, no '
      'suffix needed', () async {
    final exercises = await AppServices.exercises.getAll();
    final pushUp = exercises.firstWhere((e) => e.name == 'Push Up');
    final parsed = ParsedHiitRoutine(
      name: 'Brand New Routine',
      automatic: false,
      slots: [
        HiitRoutineSlot(
          hiitRoutineId: 0,
          sequenceIndex: 0,
          groupIndex: 0,
          exerciseId: pushUp.id!,
          exerciseKind: HiitExerciseKind.lift,
          targetType: HiitTargetType.reps,
          targetValue: 10,
        ),
      ],
      unmatchedExerciseNames: const [],
      alreadyExists: false,
    );
    await PlanExportService.commitHiitImport([
      HiitImportDecision(parsed: parsed, add: true),
    ]);
    final all = await AppServices.hiitRoutines.getAllRoutines();
    expect(all.map((r) => r.name), contains('Brand New Routine'));
    expect(all.map((r) => r.name), isNot(contains('Brand New Routine (2)')));
  });

  test('commitHiitImport: Replace when nothing exists yet just inserts fresh, '
      "doesn't error out looking for something to overwrite", () async {
    final exercises = await AppServices.exercises.getAll();
    final pushUp = exercises.firstWhere((e) => e.name == 'Push Up');
    final parsed = ParsedHiitRoutine(
      name: 'Never Saved Before',
      automatic: false,
      slots: [
        HiitRoutineSlot(
          hiitRoutineId: 0,
          sequenceIndex: 0,
          groupIndex: 0,
          exerciseId: pushUp.id!,
          exerciseKind: HiitExerciseKind.lift,
          targetType: HiitTargetType.reps,
          targetValue: 10,
        ),
      ],
      unmatchedExerciseNames: const [],
      alreadyExists: false,
    );
    await PlanExportService.commitHiitImport([
      HiitImportDecision(parsed: parsed, add: false),
    ]);
    final all = await AppServices.hiitRoutines.getAllRoutines();
    expect(all.map((r) => r.name), contains('Never Saved Before'));
  });

  test('repeated Add collisions increment past (2) to (3), not overwrite or '
      'collide', () async {
    final exercises = await AppServices.exercises.getAll();
    final pushUp = exercises.firstWhere((e) => e.name == 'Push Up');
    ParsedHiitRoutine makeParsed() => ParsedHiitRoutine(
      name: 'Repeat Me',
      automatic: false,
      slots: [
        HiitRoutineSlot(
          hiitRoutineId: 0,
          sequenceIndex: 0,
          groupIndex: 0,
          exerciseId: pushUp.id!,
          exerciseKind: HiitExerciseKind.lift,
          targetType: HiitTargetType.reps,
          targetValue: 10,
        ),
      ],
      unmatchedExerciseNames: const [],
      alreadyExists: false,
    );
    for (var i = 0; i < 3; i++) {
      await PlanExportService.commitHiitImport([
        HiitImportDecision(parsed: makeParsed(), add: true),
      ]);
    }
    final all = await AppServices.hiitRoutines.getAllRoutines();
    expect(
      all.map((r) => r.name),
      containsAll(['Repeat Me', 'Repeat Me (2)', 'Repeat Me (3)']),
    );
  });

  test(
    'a HIIT routine and a Workout Plan template can share the exact same '
    'name without colliding — separate tables, separate namespaces',
    () async {
      final exercises = await AppServices.exercises.getAll();
      final pushUp = exercises.firstWhere((e) => e.name == 'Push Up');
      const sharedName = 'Push Day';

      await PlanExportService.commitHiitImport([
        HiitImportDecision(
          parsed: ParsedHiitRoutine(
            name: sharedName,
            automatic: false,
            slots: [
              HiitRoutineSlot(
                hiitRoutineId: 0,
                sequenceIndex: 0,
                groupIndex: 0,
                exerciseId: pushUp.id!,
                exerciseKind: HiitExerciseKind.lift,
                targetType: HiitTargetType.reps,
                targetValue: 10,
              ),
            ],
            unmatchedExerciseNames: const [],
            alreadyExists: false,
          ),
          add: true,
        ),
      ]);
      await PlanExportService.commitWorkoutPlanImport([
        WorkoutPlanImportDecision(
          parsed: ParsedWorkoutTemplate(
            name: sharedName,
            days: const [
              WorkoutTemplateDay(
                templateId: 0,
                dayOrder: 0,
                dayLabel: 'Day 1',
                patterns: [MovementPattern.horizontalPush],
              ),
            ],
            unmatchedPatternLabels: const [],
            alreadyExists: false,
          ),
          add: true,
        ),
      ]);

      final hiitRoutines = await AppServices.hiitRoutines.getAllRoutines();
      final templates = await AppServices.workoutPlans.getAllTemplates();
      expect(hiitRoutines.map((r) => r.name), contains(sharedName));
      expect(templates.map((t) => t.name), contains(sharedName));
      // No auto-suffix on either side — sharing a name across the two
      // kinds isn't a collision at all.
      expect(
        hiitRoutines.map((r) => r.name),
        isNot(contains('$sharedName (2)')),
      );
      expect(templates.map((t) => t.name), isNot(contains('$sharedName (2)')));
    },
  );

  test('a Workout Plan sheet with an unrecognized pattern name is skipped and '
      'reported, the rest of that day still imports', () async {
    final excel = Excel.createExcel();
    final sheet = excel['Typo Plan'];
    sheet.appendRow([
      TextCellValue('Day'),
      TextCellValue('Pattern 1'),
      TextCellValue('Pattern 2'),
    ]);
    sheet.appendRow([
      TextCellValue('Day 1'),
      TextCellValue('Sqautt'), // typo, won't match anything
      TextCellValue('Core'),
    ]);
    final defaultSheet = excel.getDefaultSheet();
    if (defaultSheet != null && defaultSheet != 'Typo Plan') {
      excel.delete(defaultSheet);
    }

    final parsed = await PlanExportService.parseWorkoutPlanImport(
      excel.encode()!,
    );
    final template = parsed.firstWhere((t) => t.name == 'Typo Plan');
    expect(template.unmatchedPatternLabels, ['Sqautt']);
    expect(template.days.single.patterns, [MovementPattern.core]);
  });

  test('commitWorkoutPlanImport: Replace when nothing exists yet just inserts '
      'fresh', () async {
    const parsed = ParsedWorkoutTemplate(
      name: 'Never Saved Plan',
      days: [
        WorkoutTemplateDay(
          templateId: 0,
          dayOrder: 0,
          dayLabel: 'Day 1',
          patterns: [MovementPattern.squat],
        ),
      ],
      unmatchedPatternLabels: [],
      alreadyExists: false,
    );
    await PlanExportService.commitWorkoutPlanImport([
      WorkoutPlanImportDecision(parsed: parsed, add: false),
    ]);
    final all = await AppServices.workoutPlans.getAllTemplates();
    expect(all.map((t) => t.name), contains('Never Saved Plan'));
  });

  test('commitWorkoutPlanImport: repeated Add collisions increment past (2) '
      'to (3)', () async {
    ParsedWorkoutTemplate makeParsed() => const ParsedWorkoutTemplate(
      name: 'Repeat Plan',
      days: [
        WorkoutTemplateDay(
          templateId: 0,
          dayOrder: 0,
          dayLabel: 'Day 1',
          patterns: [MovementPattern.squat],
        ),
      ],
      unmatchedPatternLabels: [],
      alreadyExists: false,
    );
    for (var i = 0; i < 3; i++) {
      await PlanExportService.commitWorkoutPlanImport([
        WorkoutPlanImportDecision(parsed: makeParsed(), add: true),
      ]);
    }
    final all = await AppServices.workoutPlans.getAllTemplates();
    expect(
      all.map((t) => t.name),
      containsAll(['Repeat Plan', 'Repeat Plan (2)', 'Repeat Plan (3)']),
    );
  });
}
