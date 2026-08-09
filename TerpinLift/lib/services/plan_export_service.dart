import 'dart:io';

import 'package:excel/excel.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';

import '../data/models/distance_unit.dart';
import '../data/models/exercise.dart';
import '../data/models/hiit_routine.dart';
import '../data/models/hiit_slot.dart';
import '../data/models/workout_plan.dart';
import '../screens/hiit/hiit_presets.dart';
import 'app_services.dart';
import 'cardio_units.dart';

/// One HIIT sheet's parsed content, not yet tied to a real routine id —
/// `hiitRoutineId` on every slot is a placeholder (0), filled in once the
/// review sheet's Add/Replace decision resolves a real target id.
class ParsedHiitRoutine {
  final String name;
  final bool automatic;
  final List<HiitRoutineSlot> slots;
  final List<String> unmatchedExerciseNames;
  final bool alreadyExists;

  const ParsedHiitRoutine({
    required this.name,
    required this.automatic,
    required this.slots,
    required this.unmatchedExerciseNames,
    required this.alreadyExists,
  });
}

/// One Workout Plan sheet's parsed content, not yet tied to a real
/// template id — `templateId` on every day is a placeholder (0).
class ParsedWorkoutTemplate {
  final String name;
  final List<WorkoutTemplateDay> days;
  final List<String> unmatchedPatternLabels;
  final bool alreadyExists;

  const ParsedWorkoutTemplate({
    required this.name,
    required this.days,
    required this.unmatchedPatternLabels,
    required this.alreadyExists,
  });
}

/// One sheet's Skip-vs-apply decision from the review sheet. Whether
/// applying means an Add or a Replace isn't part of this decision at all —
/// that's just a fact about whether something by that name already
/// exists, resolved fresh at commit time (`commitHiitImport`/
/// `commitWorkoutPlanImport`), not a user choice to get wrong.
class HiitImportDecision {
  final ParsedHiitRoutine parsed;
  final bool skip;
  const HiitImportDecision({required this.parsed, required this.skip});
}

class WorkoutPlanImportDecision {
  final ParsedWorkoutTemplate parsed;
  final bool skip;
  const WorkoutPlanImportDecision({required this.parsed, required this.skip});
}

/// Friendly, human-editable Excel export/import for saved HIIT routines and
/// Workout Plan templates — deliberately different from `BackupService`'s
/// raw, id-based, roundtrip-fidelity backup: exercise **names** (never
/// ids), one sheet per routine/template named after it, light formatting
/// (bold headers/labels, italic grey usage notes) so a hand-edited file
/// stays readable. See designFiles/12_SCREEN_hiit.md and
/// designFiles/10_WORKOUT_PLANNER.md. A first pass, expected to be refined
/// once the user reviews a real exported file.
abstract class PlanExportService {
  static final _notesStyle = CellStyle(
    italic: true,
    fontColorHex: ExcelColor.fromHexString('#888888'),
  );
  static final _boldStyle = CellStyle(bold: true);

  // ---------------------------------------------------------------------
  // HIIT
  // ---------------------------------------------------------------------

  static const _hiitNotes =
      'Each round gets its own block below, with its exercises underneath. '
      'Exercise names need to match one already in the app (see the All '
      'Exercises sheet). Copy a whole round block to add another round.';

  static const _hiitColumns = [
    'Exercise',
    'Kind',
    'Target Type',
    'Target Value',
    'Unit',
    'Weight (lb)',
    'Rest After (sec)',
  ];

  /// Every source a HIIT sheet can come from — the 3 hardcoded starting
  /// points (`hiit_presets.dart`) exactly as shown in `HiitSetupScreen`'s
  /// merged Load picker, plus every routine the user has explicitly saved.
  /// Exported together since, from the user's point of view, both are just
  /// "routines I can load" — there's no reason export should only cover
  /// the saved half.
  static Future<String> exportHiitRoutines() async {
    final routines = await AppServices.hiitRoutines.getAllRoutines();
    final exercises = await AppServices.exercises.getAll();
    final byId = {
      for (final e in exercises)
        if (e.id != null) e.id!: e,
    };
    final byName = {for (final e in exercises) e.name: e};
    final excel = Excel.createExcel();
    final sheetNames = <String>[];
    final savedNames = routines.map((r) => r.name.toLowerCase()).toSet();

    // Presets first — if a saved routine happens to share a preset's exact
    // name, the saved one (the user's own edited version) wins the sheet.
    for (final preset in hiitPresets) {
      if (savedNames.contains(preset.name.toLowerCase())) continue;
      final sheetName = _sheetName(preset.name);
      sheetNames.add(sheetName);
      _writeHiitSheet(
        excel[sheetName],
        automatic: preset.automatic,
        rounds: [
          for (final round in preset.rounds)
            [
              for (final s in round)
                _hiitExportRow(
                  exerciseName: s.exerciseName,
                  exercise: byName[s.exerciseName],
                  targetType: s.targetType,
                  targetValue: s.targetValue,
                  weight: s.weight,
                  restAfterSeconds: s.restAfterSeconds,
                ),
            ],
        ],
      );
    }

    for (final routine in routines) {
      final slots = await AppServices.hiitRoutines.getSlotsForRoutine(
        routine.id!,
      );
      final byGroup = <int, List<HiitRoutineSlot>>{};
      for (final s in slots) {
        byGroup.putIfAbsent(s.groupIndex, () => []).add(s);
      }
      final groupIndices = byGroup.keys.toList()..sort();
      final sheetName = _sheetName(routine.name);
      sheetNames.add(sheetName);
      _writeHiitSheet(
        excel[sheetName],
        automatic: routine.automatic,
        rounds: [
          for (final g in groupIndices)
            [
              for (final s
                  in byGroup[g]!..sort(
                    (a, b) => a.sequenceIndex.compareTo(b.sequenceIndex),
                  ))
                _hiitExportRow(
                  exerciseName: byId[s.exerciseId]?.name ?? '',
                  exercise: byId[s.exerciseId],
                  targetType: s.targetType,
                  targetValue: s.targetValue,
                  weight: s.weight,
                  restAfterSeconds: s.restAfterSeconds,
                ),
            ],
        ],
      );
    }

    _writeAllExercisesSheet(excel, exercises);
    sheetNames.add(_allExercisesSheetName);
    _dropDefaultSheet(excel, sheetNames);
    return _writeFile(excel, 'HIIT_Routines');
  }

  /// One row's worth of export data — [targetValue] is already converted
  /// to [unit] for a distance-type slot (the exercise's own `cardioUnit`,
  /// same as every other cardio display in the app), so the sheet never
  /// shows a bare canonical meters number the user would have to guess
  /// the meaning of.
  static ({
    String exerciseName,
    bool isCardio,
    HiitTargetType targetType,
    double? targetValue,
    DistanceUnit? unit,
    double? weight,
    int? restAfterSeconds,
  })
  _hiitExportRow({
    required String exerciseName,
    required Exercise? exercise,
    required HiitTargetType targetType,
    required double? targetValue,
    required double? weight,
    required int? restAfterSeconds,
  }) {
    final isCardio =
        exercise?.equipmentTags.contains(ExerciseType.cardio) ?? false;
    final unit = targetType == HiitTargetType.distance
        ? (exercise?.cardioUnit ?? CardioUnits.defaultUnit)
        : null;
    final displayValue = (unit != null && targetValue != null)
        ? CardioUnits.fromCanonical(targetValue, unit)
        : targetValue;
    return (
      exerciseName: exerciseName,
      isCardio: isCardio,
      targetType: targetType,
      targetValue: displayValue,
      unit: unit,
      weight: weight,
      restAfterSeconds: restAfterSeconds,
    );
  }

  static void _writeHiitSheet(
    Sheet sheet, {
    required bool automatic,
    required List<
      List<
        ({
          String exerciseName,
          bool isCardio,
          HiitTargetType targetType,
          double? targetValue,
          DistanceUnit? unit,
          double? weight,
          int? restAfterSeconds,
        })
      >
    >
    rounds,
  }) {
    var row = 0;
    _setCell(sheet, 0, row, _hiitNotes, style: _notesStyle);
    row += 2;
    _setCell(sheet, 0, row, 'Automatic', style: _boldStyle);
    _setCell(sheet, 1, row, automatic);
    row += 2;

    for (var g = 0; g < rounds.length; g++) {
      _setCell(sheet, 0, row, 'Round ${g + 1}', style: _boldStyle);
      row++;
      for (var c = 0; c < _hiitColumns.length; c++) {
        _setCell(sheet, c, row, _hiitColumns[c], style: _boldStyle);
      }
      row++;
      for (final s in rounds[g]) {
        _setCell(sheet, 0, row, s.exerciseName);
        _setCell(sheet, 1, row, s.isCardio ? 'Cardio' : 'Lift');
        _setCell(sheet, 2, row, _targetTypeLabel(s.targetType));
        _setCell(sheet, 3, row, s.targetValue);
        _setCell(sheet, 4, row, s.unit?.suffix);
        _setCell(sheet, 5, row, s.weight);
        _setCell(sheet, 6, row, s.restAfterSeconds?.toDouble());
        row++;
      }
      row++;
    }
  }

  static String _targetTypeLabel(HiitTargetType t) => switch (t) {
    HiitTargetType.reps => 'Reps',
    HiitTargetType.amrap => 'AMRAP',
    HiitTargetType.time => 'Time',
    HiitTargetType.distance => 'Distance',
  };

  static HiitTargetType? _targetTypeFromLabel(String text) {
    final normalized = text.trim().toLowerCase();
    for (final t in HiitTargetType.values) {
      if (_targetTypeLabel(t).toLowerCase() == normalized) return t;
    }
    return null;
  }

  /// Matches the Unit column's short suffix ("mi", "km", "m", "floors")
  /// back to a [DistanceUnit] — `null` if blank/unrecognized, in which
  /// case the caller falls back to the exercise's own default unit.
  static DistanceUnit? _distanceUnitFromText(String text) {
    final normalized = text.trim().toLowerCase();
    for (final u in DistanceUnit.values) {
      if (u.suffix.toLowerCase() == normalized) return u;
    }
    return null;
  }

  /// Parses every sheet in an uploaded workbook as a HIIT routine. A sheet
  /// whose shape doesn't match at all (no "Automatic" row found) is
  /// silently skipped — most likely a workbook exported for the *other*
  /// kind (Workout Plan templates), not a malformed HIIT sheet.
  static Future<List<ParsedHiitRoutine>> parseHiitImport(
    List<int> bytes,
  ) async {
    final excel = Excel.decodeBytes(bytes);
    final exercises = await AppServices.exercises.getAll();
    final byName = {for (final e in exercises) e.name.toLowerCase(): e};
    final results = <ParsedHiitRoutine>[];

    for (final entry in excel.sheets.entries) {
      final sheet = entry.value;
      final rows = sheet.rows;
      var automaticRow = -1;
      for (var r = 0; r < rows.length; r++) {
        if (_textAt(rows, r, 0).toLowerCase() == 'automatic') {
          automaticRow = r;
          break;
        }
      }
      if (automaticRow == -1) continue;

      final automatic = _boolAt(rows, automaticRow, 1);
      final slots = <HiitRoutineSlot>[];
      final unmatched = <String>[];
      var groupIndex = -1;
      var sequenceIndex = 0;
      var r = automaticRow + 1;
      while (r < rows.length) {
        final col0 = _textAt(rows, r, 0);
        if (col0.toLowerCase().startsWith('round ')) {
          groupIndex++;
          r += 2; // skip the round header row + the column header row
          continue;
        }
        if (col0.isEmpty) {
          r++;
          continue;
        }
        if (groupIndex == -1) {
          // Text before the first "Round N" marker isn't a slot row.
          r++;
          continue;
        }
        final exercise = byName[col0.toLowerCase()];
        if (exercise == null) {
          unmatched.add(col0);
          r++;
          continue;
        }
        // Kind is derived from the matched exercise's real equipment tags,
        // not trusted from the sheet's own Kind column — that column is
        // for human readability, but the exercise itself is what's
        // authoritative (a hand-edited mismatch shouldn't silently create
        // a broken slot).
        final targetType =
            _targetTypeFromLabel(_textAt(rows, r, 2)) ?? HiitTargetType.reps;
        final rawTargetValue = _numAt(rows, r, 3);
        final unit = _distanceUnitFromText(_textAt(rows, r, 4));
        final targetValue =
            (targetType == HiitTargetType.distance && rawTargetValue != null)
            ? CardioUnits.toCanonical(
                rawTargetValue,
                unit ?? exercise.cardioUnit ?? CardioUnits.defaultUnit,
              )
            : rawTargetValue;
        slots.add(
          HiitRoutineSlot(
            hiitRoutineId: 0,
            sequenceIndex: sequenceIndex++,
            groupIndex: groupIndex,
            exerciseId: exercise.id!,
            exerciseKind: exercise.equipmentTags.contains(ExerciseType.cardio)
                ? HiitExerciseKind.cardio
                : HiitExerciseKind.lift,
            targetType: targetType,
            targetValue: targetValue,
            weight: _numAt(rows, r, 5),
            restAfterSeconds: _numAt(rows, r, 6)?.round(),
          ),
        );
        r++;
      }
      // Zero slots AND zero unmatched names means this sheet had an
      // "Automatic" row but no round content at all — not a real routine
      // to report. A sheet where every exercise name failed to match still
      // gets reported (with an empty slot list), so the review screen can
      // show what was skipped rather than the whole routine silently
      // vanishing (the "skip-but-report" rule this whole flow follows).
      if (slots.isEmpty && unmatched.isEmpty) continue;

      final existing = await AppServices.hiitRoutines.getRoutineByName(
        entry.key,
      );
      results.add(
        ParsedHiitRoutine(
          name: entry.key,
          automatic: automatic,
          slots: slots,
          unmatchedExerciseNames: unmatched,
          alreadyExists: existing != null,
        ),
      );
    }
    return results;
  }

  /// Applies every non-skipped sheet. Whether a given sheet becomes an Add
  /// or a Replace is resolved fresh here by name, not carried as a user
  /// choice from the review screen — a saved HIIT routine has no history
  /// depending on it, so Replace is always a plain delete-and-reinsert of
  /// its slots (`HiitRoutineRepository.replaceRoutine`), unlike Workout
  /// Plan's replace below, which has to preserve day ids for history's
  /// sake.
  static Future<void> commitHiitImport(
    List<HiitImportDecision> decisions,
  ) async {
    for (final d in decisions) {
      if (d.skip) continue;
      final p = d.parsed;
      // Nothing matched at all (every exercise name in the sheet was
      // unrecognized) — reported on the review screen, but there's
      // nothing usable to actually save.
      if (p.slots.isEmpty) continue;

      final existing = await AppServices.hiitRoutines.getRoutineByName(p.name);
      final routine = HiitRoutine(
        name: p.name,
        automatic: p.automatic,
        created: DateTime.now().toIso8601String(),
      );
      if (existing != null) {
        await AppServices.hiitRoutines.replaceRoutine(existing.id!, routine, [
          for (final s in p.slots) _withRoutineId(s, existing.id!),
        ]);
      } else {
        final routineId = await AppServices.hiitRoutines.insertRoutine(routine);
        await AppServices.hiitRoutines.insertRoutineSlots([
          for (final s in p.slots) _withRoutineId(s, routineId),
        ]);
      }
    }
  }

  static HiitRoutineSlot _withRoutineId(HiitRoutineSlot s, int routineId) =>
      HiitRoutineSlot(
        hiitRoutineId: routineId,
        sequenceIndex: s.sequenceIndex,
        groupIndex: s.groupIndex,
        exerciseId: s.exerciseId,
        exerciseKind: s.exerciseKind,
        targetType: s.targetType,
        targetValue: s.targetValue,
        weight: s.weight,
        restAfterSeconds: s.restAfterSeconds,
      );

  // ---------------------------------------------------------------------
  // Workout Plan
  // ---------------------------------------------------------------------

  static const _workoutPlanNotes =
      'Each day is a row, its patterns across the columns. The row below '
      'each day marks which are main lifts vs accessories. See the '
      'pattern reference below for lifts that already match each pattern.';

  /// Marks where the day table ends and the read-only pattern-reference
  /// table begins — `parseWorkoutPlanImport` stops reading days the moment
  /// it sees this in a row's first cell, so the reference table (which
  /// also has non-blank text in its first column) never gets misread as
  /// more days.
  static const _referenceMarker = 'Reference, not imported';

  static Future<String> exportWorkoutTemplates() async {
    final templates = await AppServices.workoutPlans.getAllTemplates();
    final exercises = await AppServices.exercises.getAll();
    final excel = Excel.createExcel();
    final sheetNames = <String>[];
    for (final template in templates) {
      final days = await AppServices.workoutPlans.getDaysForTemplate(
        template.id!,
      );
      final sheetName = _sheetName(template.name);
      sheetNames.add(sheetName);
      _writeWorkoutPlanSheet(excel[sheetName], days, exercises);
    }
    _writeAllExercisesSheet(excel, exercises);
    sheetNames.add(_allExercisesSheetName);
    _dropDefaultSheet(excel, sheetNames);
    return _writeFile(excel, 'Workout_Plans');
  }

  static void _writeWorkoutPlanSheet(
    Sheet sheet,
    List<WorkoutTemplateDay> days,
    List<Exercise> allExercises,
  ) {
    var row = 0;
    _setCell(sheet, 0, row, _workoutPlanNotes, style: _notesStyle);
    row += 2;
    // No cap beyond a sane floor for the header's own width — a day with
    // more slots than any other simply gets more "Pattern N" columns, read
    // by scanning each row out to its own actual width on import, not a
    // fixed column count.
    final tightestFit = days.isEmpty
        ? 0
        : days.map((d) => d.patterns.length).reduce((a, b) => a > b ? a : b);
    final maxSlots = tightestFit > 4 ? tightestFit : 4;
    _setCell(sheet, 0, row, 'Day', style: _boldStyle);
    for (var c = 0; c < maxSlots; c++) {
      _setCell(sheet, c + 1, row, 'Pattern ${c + 1}', style: _boldStyle);
    }
    row++;
    for (final day in days) {
      _setCell(sheet, 0, row, day.dayLabel, style: _boldStyle);
      for (var c = 0; c < day.patterns.length; c++) {
        _setCell(sheet, c + 1, row, day.patterns[c].label);
      }
      row++;
      // Main-vs-accessory row, aligned under the pattern it describes —
      // informational only (a pattern's main/accessory status is fixed by
      // the app, not editable here), but shown per day so it's visible at
      // a glance without cross-checking the reference table below. Left
      // blank in col 0 so the importer's day-reading loop (which skips any
      // row with a blank first cell) passes over it without treating it
      // as another day.
      for (var c = 0; c < day.patterns.length; c++) {
        _setCell(
          sheet,
          c + 1,
          row,
          day.patterns[c].isMain ? 'Main' : 'Accessory',
          style: _notesStyle,
        );
      }
      row++;
    }

    row++;
    _setCell(sheet, 0, row, _referenceMarker, style: _notesStyle);
    row++;
    for (final pattern in MovementPattern.values) {
      _setCell(
        sheet,
        0,
        row,
        '${pattern.label} (${pattern.isMain ? 'Main' : 'Accessory'})',
        style: _boldStyle,
      );
      final matching = allExercises.where((e) => e.patterns.contains(pattern));
      var c = 1;
      for (final e in matching) {
        _setCell(sheet, c, row, e.name);
        c++;
      }
      row++;
    }
  }

  static MovementPattern? _patternByLabel(String text) {
    final normalized = text.trim().toLowerCase();
    for (final p in MovementPattern.values) {
      if (p.label.toLowerCase() == normalized) return p;
    }
    return null;
  }

  /// Parses every sheet as a Workout Plan template — same "skip a sheet
  /// that doesn't match this shape" tolerance as `parseHiitImport` (no
  /// "Day" header row found means it's most likely a HIIT-routine sheet).
  static Future<List<ParsedWorkoutTemplate>> parseWorkoutPlanImport(
    List<int> bytes,
  ) async {
    final excel = Excel.decodeBytes(bytes);
    final results = <ParsedWorkoutTemplate>[];

    for (final entry in excel.sheets.entries) {
      final sheet = entry.value;
      final rows = sheet.rows;
      var headerRow = -1;
      for (var r = 0; r < rows.length; r++) {
        if (_textAt(rows, r, 0).toLowerCase() == 'day') {
          headerRow = r;
          break;
        }
      }
      if (headerRow == -1) continue;

      final days = <WorkoutTemplateDay>[];
      final unmatched = <String>[];
      var dayOrder = 0;
      for (var r = headerRow + 1; r < rows.length; r++) {
        final label = _textAt(rows, r, 0);
        if (label.isEmpty) continue;
        // The read-only pattern-reference table starts here — stop reading
        // days, its rows have non-blank first cells too (pattern names)
        // and would otherwise get misread as more days.
        if (label.toLowerCase().startsWith('reference')) break;
        final patterns = <MovementPattern>[];
        final colCount = rows[r].length;
        for (var c = 1; c < colCount; c++) {
          final text = _textAt(rows, r, c);
          if (text.isEmpty) continue;
          final pattern = _patternByLabel(text);
          if (pattern == null) {
            unmatched.add(text);
          } else {
            patterns.add(pattern);
          }
        }
        days.add(
          WorkoutTemplateDay(
            templateId: 0,
            dayOrder: dayOrder++,
            dayLabel: label,
            patterns: patterns,
          ),
        );
      }
      if (days.isEmpty) continue;

      final existing = await AppServices.workoutPlans.getTemplateByName(
        entry.key,
      );
      results.add(
        ParsedWorkoutTemplate(
          name: entry.key,
          days: days,
          unmatchedPatternLabels: unmatched,
          alreadyExists: existing != null,
        ),
      );
    }
    return results;
  }

  /// Applies every non-skipped sheet. Whether a given sheet becomes an Add
  /// or a Replace is resolved fresh here by name, not carried as a user
  /// choice from the review screen. Unlike HIIT's replace, Workout Plan's
  /// Replace must never delete a day `planned_sessions.template_day_id`
  /// might already reference — that's exactly what
  /// `WorkoutPlanRepository.replaceTemplateDays` handles (match by
  /// position, update in place, soft-hide anything dropped).
  static Future<void> commitWorkoutPlanImport(
    List<WorkoutPlanImportDecision> decisions,
  ) async {
    for (final d in decisions) {
      if (d.skip) continue;
      final p = d.parsed;
      final existing = await AppServices.workoutPlans.getTemplateByName(p.name);
      if (existing != null) {
        await AppServices.workoutPlans.replaceTemplateDays(
          existing.id!,
          p.days,
        );
      } else {
        final templateId = await AppServices.workoutPlans.insertTemplate(
          WorkoutTemplate(
            name: p.name,
            created: DateTime.now().toIso8601String(),
          ),
        );
        for (final day in p.days) {
          await AppServices.workoutPlans.insertDay(
            WorkoutTemplateDay(
              templateId: templateId,
              dayOrder: day.dayOrder,
              dayLabel: day.dayLabel,
              patterns: day.patterns,
            ),
          );
        }
      }
    }
  }

  // ---------------------------------------------------------------------
  // Shared: the "All Exercises" reference sheet on both exports
  // ---------------------------------------------------------------------

  static const _allExercisesSheetName = 'All Exercises';

  /// A plain lift-name lookup appended to both exports — the whole point is
  /// making the exact spelling for the Exercise/pattern-reference columns
  /// easy to find without leaving the spreadsheet. Not shaped like a
  /// routine or a day table, so both parsers already skip it untouched.
  static void _writeAllExercisesSheet(Excel excel, List<Exercise> exercises) {
    final sheet = excel[_allExercisesSheetName];
    const headers = ['Name', 'Category', 'Kind'];
    for (var c = 0; c < headers.length; c++) {
      _setCell(sheet, c, 0, headers[c], style: _boldStyle);
    }
    final sorted = [...exercises]..sort((a, b) => a.name.compareTo(b.name));
    for (var i = 0; i < sorted.length; i++) {
      final e = sorted[i];
      _setCell(sheet, 0, i + 1, e.name);
      _setCell(sheet, 1, i + 1, e.categories.map((c) => c.label).join(', '));
      _setCell(
        sheet,
        2,
        i + 1,
        e.equipmentTags.contains(ExerciseType.cardio) ? 'Cardio' : 'Lift',
      );
    }
  }

  // ---------------------------------------------------------------------
  // Shared helpers
  // ---------------------------------------------------------------------

  static void _setCell(
    Sheet sheet,
    int col,
    int row,
    Object? value, {
    CellStyle? style,
  }) {
    final cell = sheet.cell(
      CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row),
    );
    if (value == null) {
      cell.value = null;
    } else if (value is bool) {
      cell.value = BoolCellValue(value);
    } else if (value is double) {
      cell.value = DoubleCellValue(value);
    } else {
      cell.value = TextCellValue(value.toString());
    }
    if (style != null) cell.cellStyle = style;
  }

  static String _textAt(List<List<Data?>> rows, int r, int c) {
    if (r >= rows.length || c >= rows[r].length) return '';
    final value = rows[r][c]?.value;
    if (value == null) return '';
    if (value is TextCellValue) return value.value.toString().trim();
    return value.toString().trim();
  }

  static double? _numAt(List<List<Data?>> rows, int r, int c) {
    if (r >= rows.length || c >= rows[r].length) return null;
    final value = rows[r][c]?.value;
    if (value == null) return null;
    if (value is IntCellValue) return value.value.toDouble();
    if (value is DoubleCellValue) return value.value;
    return double.tryParse(value.toString());
  }

  static bool _boolAt(List<List<Data?>> rows, int r, int c) {
    if (r >= rows.length || c >= rows[r].length) return false;
    final value = rows[r][c]?.value;
    if (value is BoolCellValue) return value.value;
    return _textAt(rows, r, c).toLowerCase() == 'true';
  }

  /// Excel sheet names can't contain `: \ / ? * [ ]` and cap at 31 chars.
  static String _sheetName(String name) {
    final sanitized = name.replaceAll(RegExp(r'[:\\/?*\[\]]'), '-');
    return sanitized.length > 31 ? sanitized.substring(0, 31) : sanitized;
  }

  static void _dropDefaultSheet(Excel excel, List<String> writtenNames) {
    final defaultSheet = excel.getDefaultSheet();
    if (defaultSheet != null &&
        !writtenNames.contains(defaultSheet) &&
        excel.sheets.length > 1) {
      excel.delete(defaultSheet);
    }
  }

  static Future<String> _writeFile(Excel excel, String baseName) async {
    final dir = await getApplicationDocumentsDirectory();
    final date = DateTime.now().toIso8601String().split('T').first;
    final file = File(join(dir.path, '${baseName}_$date.xlsx'));
    final bytes = excel.encode()!;
    await file.writeAsBytes(bytes);
    return file.path;
  }
}
