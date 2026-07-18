import 'dart:math';

import 'package:flutter/material.dart';

import '../data/models/bodyweight_entry.dart';
import '../data/models/custom_metric.dart';
import '../data/models/custom_metric_entry.dart';
import '../data/models/cycle_entry.dart';
import '../data/models/exercise.dart';
import '../data/models/lift_set.dart';
import '../data/models/metric_entry.dart';
import '../data/models/progress_photo.dart';
import '../data/models/workout_plan.dart';
import 'app_services.dart';
import 'placeholder_image_generator.dart';
import 'training_composition_service.dart';
import 'user_profile.dart';

/// Generates ~2 months of plausible (not real) workout/metric history so the
/// dashboard, trend lines, and predictions can be reviewed with realistic
/// data instead of an empty app. Used from Settings' "Load test data" button.
class TestDataService {
  static final Random _rand = Random();

  static const Map<String, double> _startingWeights = {
    'Front Squat': 115,
    'Back Squat': 135,
    'Bench Press': 95,
    'Deadlift': 155,
    'Overhead Press': 65,
    'Barbell Row': 85,
    'Lat Pulldown': 90,
    'Leg Press': 220,
    'Barbell Curl': 45,
  };

  // Two rough cycles over the 60-day window, ~28 days apart. A period is
  // just a run of days with flow > 0 — no separate start/end record. Shared
  // between the metric-dip logic below and _loadCycleData so both agree on
  // which days are period days.
  static const _cycleStartOffsets = [4, 32];
  static const _flowPattern = [2, 4, 3, 1, 1];

  static String _fmt(DateTime d) => d.toIso8601String().substring(0, 10);

  static Set<int> _periodDayOffsets() {
    final days = <int>{};
    for (final start in _cycleStartOffsets) {
      for (var i = 0; i < _flowPattern.length; i++) {
        days.add(start + i);
      }
    }
    return days;
  }

  /// Wipes all existing data (including exercises) and inserts synthetic
  /// history for every tracked thing: lifts, bodyweight, steps, sleep,
  /// per-region soreness, and cycle entries.
  /// A representative training-routine subset to actually generate sessions
  /// for — the full seeded library is ~75 exercises now (`DatabaseHelper.
  /// _seedExercises`), and rotating synthetic sessions across all of them
  /// would spread the 60-day window too thin for any single lift's trend
  /// chart to have enough points to look like anything. The untouched
  /// exercises still exist and are browsable, just without demo history.
  static const _routineExerciseNames = [
    'Back Squat',
    'Front Squat',
    'Bench Press',
    'Deadlift',
    'Overhead Press',
    'Pull Up',
    'Push Up',
    'Barbell Row',
    'Lat Pulldown',
    'Leg Press',
    'Barbell Curl',
  ];

  static Future<void> load() async {
    await AppServices.db.wipeEverythingAndReseed();
    await AppServices.workoutPlans.deleteAllSessions();
    final allExercises = await AppServices.exercises.getAll();
    final exercises =
        allExercises.where((e) => _routineExerciseNames.contains(e.name)).toList();

    // Workout Planner demo data — a real `PlannedSession` for roughly half
    // of gym days (see `isGymDay` below), rotating through the seeded
    // default template's days, so the Workouts tab, Active Day's view/edit
    // mode, and the Workout Duration chart's planned-session-priority path
    // (`TrendEngine.workoutDurationMinutesByDate`) all have something real
    // to show — previously demo data only ever wrote raw `lift_sessions`
    // rows, which meant the entire Workout Planner surface looked unused.
    final defaultTemplate = await AppServices.workoutPlans.getDefaultTemplate();
    final templateDays = defaultTemplate == null
        ? <WorkoutTemplateDay>[]
        : await AppServices.workoutPlans.getDaysForTemplate(defaultTemplate.id!);

    const totalDays = 60;
    final today = DateTime.now();
    final start = today.subtract(const Duration(days: totalDays));
    final periodDays = _periodDayOffsets();

    // Total growth amplitude per lift (10-25%) — the *shape* of how that
    // amplitude gets reached over the window (ramp / plateau / slump /
    // rebound) is the same curve for everyone, see _growthCurve.
    final amplitudeByExercise = {
      for (final e in exercises) e.id!: 0.10 + _rand.nextDouble() * 0.15,
    };

    // Soreness "events" — (day trained, category, base magnitude) — so a
    // later day can look back and apply a DOMS-style delayed-onset curve
    // (peaks the day *after* training, not the day of) instead of soreness
    // just being a same-day flag.
    final sorenessEvents = <({int day, ExerciseCategory category, double magnitude})>[];

    for (var offset = 0; offset <= totalDays; offset++) {
      final date = start.add(Duration(days: offset));
      final dateStr = _fmt(date);
      final progress = offset / totalDays;
      final onPeriod = periodDays.contains(offset);

      // A synthetic but plausible time-of-day for this day's entries.
      final loggedAt = DateTime(date.year, date.month, date.day, 8).toIso8601String();

      // Daily metrics, logged every day regardless of gym attendance.
      // Period days get a modest sleep/step dip — not a cycle-syncing claim,
      // just a bit of realistic correlated noise for later trend-reading.
      await AppServices.metrics.insert(MetricEntry(
        date: dateStr,
        metricType: MetricType.steps,
        value: ((onPeriod ? 5200 : 6500) + _rand.nextInt(6000)).toDouble(),
        loggedAt: loggedAt,
      ));
      await AppServices.metrics.insert(MetricEntry(
        date: dateStr,
        metricType: MetricType.sleepHours,
        value: double.parse(
            ((onPeriod ? 5.6 : 6.2) + _rand.nextDouble() * 2.3).toStringAsFixed(1)),
        loggedAt: loggedAt,
      ));

      final isWeekend =
          date.weekday == DateTime.saturday || date.weekday == DateTime.sunday;
      final gymChance = isWeekend ? 0.35 : 0.68; // nets out to roughly 3-5 days/week
      final isGymDay = _rand.nextDouble() < gymChance;

      if (isGymDay) {
        final primary = exercises[offset % exercises.length];
        await _logAny(primary, progress, amplitudeByExercise[primary.id]!, dateStr);
        for (final tag in primary.categories
            .where(TrainingCompositionService.bodyPartCategories.contains)) {
          sorenessEvents.add((day: offset, category: tag, magnitude: 3.5));
        }

        // Roughly 40% of gym days include a second movement at lower effort,
        // mirroring "one all-out lift, others lighter" per the user's real routine.
        if (_rand.nextDouble() < 0.4) {
          final secondary = exercises[(offset + 2) % exercises.length];
          if (secondary.id != primary.id) {
            await _logAny(
              secondary,
              progress,
              amplitudeByExercise[secondary.id]!,
              dateStr,
              forceRecovery: true,
            );
            for (final tag in secondary.categories
                .where(TrainingCompositionService.bodyPartCategories.contains)) {
              sorenessEvents.add((day: offset, category: tag, magnitude: 2.0));
            }
          }
        }

        // Roughly half of gym days also get a real Workout Planner session
        // (not just the raw lift logs above) — a completed `PlannedSession`
        // tied to the seeded default template, started ~7pm with a plausible
        // 40-80 minute span, rotating through the template's days in order.
        if (templateDays.isNotEmpty && _rand.nextDouble() < 0.5) {
          final day = templateDays[offset % templateDays.length];
          final startedAt = DateTime(date.year, date.month, date.day, 19, _rand.nextInt(45));
          final completedAt = startedAt.add(Duration(minutes: 40 + _rand.nextInt(41)));
          await AppServices.workoutPlans.insertSession(PlannedSession(
            templateDayId: day.id!,
            date: dateStr,
            startedAt: startedAt.toIso8601String(),
            completedAt: completedAt.toIso8601String(),
            status: PlannedSessionStatus.completed,
          ));
        }
      }

      await _writeSoreness(offset, dateStr, loggedAt, sorenessEvents, onPeriod);

      // Bodyweight roughly twice a week.
      if (date.weekday == DateTime.monday || date.weekday == DateTime.thursday) {
        await AppServices.bodyweight.insert(BodyweightEntry(
          date: dateStr,
          weight: double.parse(
              (152 - progress * 1.5 + _rand.nextDouble() * 1.5).toStringAsFixed(1)),
        ));
      }
    }

    // Cycle demo data only makes sense for the female-gender setting — the
    // whole feature is scoped there (`00_UX_DESIGN.md`), and generating it
    // for a male-set profile would just be irrelevant synthetic noise.
    if (UserProfile.gender == Gender.female) {
      await _loadCycleData(start);
    }
    await _loadProgressPhotos(start);
    await _loadCustomMetrics(start);

    AppServices.signalReload();
  }

  /// A handful of synthetic progress photos spread across the demo window —
  /// obviously can't fake a real photo, so each is just a plain black square
  /// with a simple white icon drawn on it (`PlaceholderImageGenerator`).
  /// Single-photo days are spaced out to look like periodic check-ins; a few
  /// days deliberately get 2-3 photos (different angles/poses) so the
  /// album's stacked-pile tile has real multi-photo cases to test, not just
  /// one. Icons cycle across the *whole* sequence (not reset per day), so a
  /// multi-photo day's pile shows visibly different icons per photo rather
  /// than the same one repeated. Old demo photos are cleared first so
  /// reloading test data doesn't just keep stacking up more of them.
  static const _progressPhotoIcons = [
    Icons.fitness_center,
    Icons.emoji_events,
    Icons.trending_up,
    Icons.self_improvement,
    Icons.bolt,
  ];

  static Future<void> _loadProgressPhotos(DateTime start) async {
    await AppServices.progressPhotos.deleteAll();
    const offsets = [3, 17, 24, 24, 24, 31, 38, 38, 45, 52, 58];
    // How many photos already landed on this same offset (for the 24/38
    // repeats above) — staggers same-day timestamps by an hour each,
    // otherwise every photo on a multi-photo demo day shares the exact same
    // `taken_at` and has no real chronological order within that day.
    var sameOffsetCount = 0;
    for (var i = 0; i < offsets.length; i++) {
      if (i > 0 && offsets[i] == offsets[i - 1]) {
        sameOffsetCount++;
      } else {
        sameOffsetCount = 0;
      }
      final date = start.add(Duration(days: offsets[i]));
      final icon = _progressPhotoIcons[i % _progressPhotoIcons.length];
      final bytes = await PlaceholderImageGenerator.generate(icon);
      final path = await AppServices.progressPhotos.storeBytes(bytes);
      await AppServices.progressPhotos.insert(ProgressPhoto(
        date: _fmt(date),
        filePath: path,
        takenAt:
            DateTime(date.year, date.month, date.day, 8 + sameOffsetCount).toIso8601String(),
      ));
    }
  }

  /// A single "Mood" custom metric (classes kind, once-per-day) with entries
  /// roughly every 4 days across the window — proves out the metric-builder
  /// feature end to end with real-looking data, rather than it only ever
  /// being tested empty. Any pre-existing custom metrics are cleared first,
  /// same "test data replaces everything" convention as the rest of this
  /// generator.
  static Future<void> _loadCustomMetrics(DateTime start) async {
    final existing = await AppServices.customMetrics.getAllDefinitions();
    for (final metric in existing) {
      await AppServices.customMetrics.deleteDefinition(metric.id!);
    }
    final moodId = await AppServices.customMetrics.insertDefinition(CustomMetric(
      name: 'Mood',
      kind: CustomMetricKind.classes,
      classLabels: const ['😞 Sad', '🙁 Down', '😐 Neutral', '🙂 Good', '😄 Great'],
      created: DateTime.now().toIso8601String(),
      allowMultiplePerDay: false,
    ));
    for (var offset = 0; offset <= 60; offset += 4) {
      final date = start.add(Duration(days: offset));
      await AppServices.customMetrics.insertEntry(CustomMetricEntry(
        customMetricId: moodId,
        date: _fmt(date),
        value: _rand.nextInt(5).toDouble(),
        loggedAt: DateTime(date.year, date.month, date.day, 8).toIso8601String(),
      ));
    }
  }

  /// DOMS-style delayed soreness: a training event contributes least on the
  /// day it happens (0.4x), peaks the day after (1.0x — matches real DOMS
  /// timing), and fades by two days out (0.5x), rather than soreness being a
  /// flat same-day flag. Plus a small everyday baseline noise, and a touch
  /// more on period days.
  static Future<void> _writeSoreness(
    int today,
    String dateStr,
    String loggedAt,
    List<({int day, ExerciseCategory category, double magnitude})> events,
    bool onPeriod,
  ) async {
    final raw = <ExerciseCategory, double>{
      for (final c in TrainingCompositionService.bodyPartCategories)
        c: _rand.nextDouble() * (onPeriod ? 1.5 : 1.0),
    };
    for (final event in events) {
      final daysSince = today - event.day;
      final decay = switch (daysSince) {
        0 => 0.4,
        1 => 1.0,
        2 => 0.5,
        _ => 0.0,
      };
      if (decay == 0.0) continue;
      raw[event.category] = (raw[event.category] ?? 0) + event.magnitude * decay;
    }

    for (final entry in raw.entries) {
      await AppServices.metrics.insert(MetricEntry(
        date: dateStr,
        metricType: MetricTypeKey.forSorenessRegion(_representativeRegion(entry.key)),
        value: entry.value.round().clamp(0, 5).toDouble(),
        loggedAt: loggedAt,
      ));
    }
  }

  /// Synthetic soreness doesn't need per-exercise sub-region precision —
  /// one representative `SorenessRegion` per broad category is enough to
  /// give the demo data plausible shape after the soreness sub-split
  /// (designFiles/05_SCREEN_metrics.md).
  static SorenessRegion _representativeRegion(ExerciseCategory category) {
    switch (category) {
      case ExerciseCategory.chest:
        return SorenessRegion.chest;
      case ExerciseCategory.core:
        return SorenessRegion.coreCenter;
      case ExerciseCategory.back:
        return SorenessRegion.upperBack;
      case ExerciseCategory.arms:
        return SorenessRegion.biceps;
      case ExerciseCategory.legs:
        return SorenessRegion.quads;
      case ExerciseCategory.push:
      case ExerciseCategory.pull:
        return SorenessRegion.chest; // unreachable: bodyPartCategories excludes these
    }
  }

  /// Dispatches to the bodyweight-narrative generator for `Pull Up`/`Push Up`
  /// (weight-as-lb progression doesn't make sense for those), plain
  /// weight-based generation for everything else.
  static Future<void> _logAny(
    Exercise exercise,
    double progress,
    double amplitude,
    String dateStr, {
    bool forceRecovery = false,
  }) async {
    if (exercise.equipmentTags.contains(ExerciseType.bodyweight)) {
      await _logBodyweightLift(exercise, progress, dateStr);
    } else {
      await _logLift(exercise, progress, amplitude, dateStr, forceRecovery: forceRecovery);
    }
  }

  /// Bodyweight narrative: `Pull Up` walks the assisted -> plain-bodyweight
  /// -> weighted arc the Goal-gauge rep-standards feature was built to show
  /// off; `Push Up` stays a simpler plain-bodyweight rep climb the whole
  /// window, since push-ups don't typically have an assisted phase. `weight`
  /// here is the signed added/assisted load (see `bodyweightAdjustedBestE1rm`),
  /// not a total — reps are the thing actually progressing.
  static Future<void> _logBodyweightLift(
    Exercise exercise,
    double progress,
    String dateStr,
  ) async {
    List<LiftSet> sets;
    if (exercise.name == 'Pull Up') {
      if (progress < 0.35) {
        final t = progress / 0.35;
        final assistance = 55 - t * 25; // 55lb assist tapering to 30lb
        sets = _buildBodyweightSets(
            weight: -assistance, repsMin: 5, repsMax: 8, rpeMin: 6, rpeMax: 8);
      } else if (progress < 0.65) {
        final t = (progress - 0.35) / 0.30;
        final repsCenter = (4 + t * 8).round(); // 4 -> 12 plain-bodyweight reps
        sets = _buildBodyweightSets(
          weight: 0,
          repsMin: (repsCenter - 1).clamp(1, 99),
          repsMax: repsCenter + 1,
          rpeMin: 7,
          rpeMax: 9,
        );
      } else {
        final t = (progress - 0.65) / 0.35;
        final added = (5 + t * 20).roundToDouble(); // 5lb -> 25lb added
        sets = _buildBodyweightSets(
            weight: added, repsMin: 4, repsMax: 7, rpeMin: 7, rpeMax: 9);
      }
    } else {
      // Push Up: plain-bodyweight reps climbing the whole window.
      final repsCenter = (8 + progress * 24).round(); // 8 -> 32
      sets = _buildBodyweightSets(
        weight: 0,
        repsMin: (repsCenter - 3).clamp(1, 99),
        repsMax: repsCenter + 3,
        rpeMin: 6,
        rpeMax: 9,
      );
    }
    await AppServices.lifts.logSession(exerciseId: exercise.id!, date: dateStr, sets: sets);
  }

  static List<LiftSet> _buildBodyweightSets({
    required double weight,
    required int repsMin,
    required int repsMax,
    required int rpeMin,
    required int rpeMax,
  }) {
    final setCount = 3 + _rand.nextInt(2); // 3-4 sets
    return List.generate(setCount, (_) {
      final reps = repsMin + _rand.nextInt((repsMax - repsMin + 1).clamp(1, 999));
      final rpe = (rpeMin + _rand.nextInt(rpeMax - rpeMin + 1)).toDouble();
      return LiftSet(sessionId: 0, setNumber: 0, reps: reps, weight: weight, rpe: rpe);
    });
  }

  static Future<void> _logLift(
    Exercise exercise,
    double progress,
    double amplitude,
    String dateStr, {
    bool forceRecovery = false,
  }) async {
    final baseline = _startingWeights[exercise.name] ?? 100.0;
    final workingWeight = baseline * (1 + _growthCurve(progress) * amplitude);

    final roll = forceRecovery ? 0.2 : _rand.nextDouble();
    List<LiftSet> sets;
    if (!forceRecovery && roll < 0.15) {
      // All-out day: near-max effort, low reps, high RPE.
      sets = _buildSets(workingWeight, effort: 1.0, repsMin: 1, repsMax: 3, rpeMin: 9, rpeMax: 10);
    } else if (roll < 0.30) {
      // Recovery/light day: the "70/30% effort" case that shouldn't read as a strength loss.
      sets = _buildSets(workingWeight, effort: 0.65, repsMin: 5, repsMax: 8, rpeMin: 3, rpeMax: 5);
    } else {
      // Normal working day.
      sets = _buildSets(workingWeight, effort: 0.85, repsMin: 4, repsMax: 6, rpeMin: 6, rpeMax: 8);
    }

    await AppServices.lifts.logSession(
      exerciseId: exercise.id!,
      date: dateStr,
      sets: sets,
    );
  }

  /// Shape of progress over the 60-day window, as a fraction of each lift's
  /// total growth amplitude: fast early gains, a plateau, a slump (a stretch
  /// of overreaching/understraining that reads as a real regression, not
  /// just noise), then a rebound past the pre-slump level. Deliberately NOT
  /// a smooth monotonic curve — the whole point is giving the adaptive
  /// polynomial trend fit (see designFiles/00_UX_DESIGN.md) actual shape to
  /// find, and giving Home's status/readiness reasoning something interesting
  /// to eventually chew on.
  static double _growthCurve(double progress) {
    const rampEnd = 0.33;
    const plateauEnd = 0.55;
    const slumpEnd = 0.72;

    const rampPeak = 0.70; // fraction of full amplitude reached by rampEnd
    const slumpTrough = 0.55; // dips back down to this fraction during the slump

    if (progress <= rampEnd) {
      return rampPeak * (progress / rampEnd);
    }
    if (progress <= plateauEnd) {
      return rampPeak;
    }
    if (progress <= slumpEnd) {
      final t = (progress - plateauEnd) / (slumpEnd - plateauEnd);
      return rampPeak + (slumpTrough - rampPeak) * t;
    }
    final t = (progress - slumpEnd) / (1 - slumpEnd);
    return slumpTrough + (1.0 - slumpTrough) * t;
  }

  static List<LiftSet> _buildSets(
    double workingWeight, {
    required double effort,
    required int repsMin,
    required int repsMax,
    required int rpeMin,
    required int rpeMax,
  }) {
    final setCount = 3 + _rand.nextInt(2); // 3-4 sets
    final weight = ((workingWeight * effort) / 5).round() * 5.0;
    return List.generate(setCount, (_) {
      final reps = repsMin + _rand.nextInt(repsMax - repsMin + 1);
      final rpe = (rpeMin + _rand.nextInt(rpeMax - rpeMin + 1)).toDouble();
      return LiftSet(sessionId: 0, setNumber: 0, reps: reps, weight: weight, rpe: rpe);
    });
  }

  static Future<void> _loadCycleData(DateTime start) async {
    for (final cycleStartOffset in _cycleStartOffsets) {
      final periodStart = start.add(Duration(days: cycleStartOffset));
      for (var i = 0; i < _flowPattern.length; i++) {
        await AppServices.cycle.setFlow(
          _fmt(periodStart.add(Duration(days: i))),
          _flowPattern[i],
        );
      }
      await AppServices.cycle.insert(CycleEntry(
        date: _fmt(periodStart.add(const Duration(days: 1))),
        entryType: CycleEntryType.symptom,
        symptomTag: 'low_energy',
      ));
    }
  }
}
