import 'dart:math';

import '../data/models/bodyweight_entry.dart';
import '../data/models/cycle_entry.dart';
import '../data/models/exercise.dart';
import '../data/models/lift_set.dart';
import '../data/models/metric_entry.dart';
import 'app_services.dart';
import 'training_composition_service.dart';

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
  };

  static String _fmt(DateTime d) => d.toIso8601String().substring(0, 10);

  /// Wipes all existing data (including exercises) and inserts synthetic
  /// history for every tracked thing: lifts, bodyweight, steps, sleep,
  /// soreness, and cycle entries.
  static Future<void> load() async {
    await AppServices.db.wipeEverythingAndReseed();
    final exercises = await AppServices.exercises.getAll();

    const totalDays = 60;
    final today = DateTime.now();
    final start = today.subtract(const Duration(days: totalDays));

    // Slight per-lift variance in how fast "you" progress over the window.
    final growthByExercise = {
      for (final e in exercises) e.id!: 0.10 + _rand.nextDouble() * 0.10, // 10-20%
    };

    for (var offset = 0; offset <= totalDays; offset++) {
      final date = start.add(Duration(days: offset));
      final dateStr = _fmt(date);
      final progress = offset / totalDays;

      // A synthetic but plausible time-of-day for this day's entries.
      final loggedAt = DateTime(date.year, date.month, date.day, 8).toIso8601String();

      // Daily metrics, logged every day regardless of gym attendance.
      await AppServices.metrics.insert(MetricEntry(
        date: dateStr,
        metricType: MetricType.steps,
        value: (6500 + _rand.nextInt(6000)).toDouble(),
        loggedAt: loggedAt,
      ));
      await AppServices.metrics.insert(MetricEntry(
        date: dateStr,
        metricType: MetricType.sleepHours,
        value: double.parse((6.2 + _rand.nextDouble() * 2.3).toStringAsFixed(1)),
        loggedAt: loggedAt,
      ));

      final isWeekend =
          date.weekday == DateTime.saturday || date.weekday == DateTime.sunday;
      final gymChance = isWeekend ? 0.35 : 0.68; // nets out to roughly 3-5 days/week
      final isGymDay = _rand.nextDouble() < gymChance;

      // Mild everyday baseline (0-1) for every region, bumped up for whatever
      // got trained today — so soreness correlates with what was actually hit.
      final soreness = <ExerciseCategory, int>{
        for (final c in TrainingCompositionService.bodyPartCategories) c: _rand.nextInt(2),
      };
      void bumpSoreness(Exercise exercise, int amount) {
        for (final tag in exercise.categories
            .where(TrainingCompositionService.bodyPartCategories.contains)) {
          soreness[tag] = ((soreness[tag] ?? 0) + amount).clamp(0, 5);
        }
      }

      if (isGymDay) {
        final primary = exercises[offset % exercises.length];
        await _logLift(primary, progress, growthByExercise[primary.id]!, dateStr);
        bumpSoreness(primary, 2 + _rand.nextInt(2));

        // Roughly 40% of gym days include a second movement at lower effort,
        // mirroring "one all-out lift, others lighter" per the user's real routine.
        if (_rand.nextDouble() < 0.4) {
          final secondary = exercises[(offset + 2) % exercises.length];
          if (secondary.id != primary.id) {
            await _logLift(
              secondary,
              progress,
              growthByExercise[secondary.id]!,
              dateStr,
              forceRecovery: true,
            );
            bumpSoreness(secondary, 1 + _rand.nextInt(2));
          }
        }
      }

      for (final entry in soreness.entries) {
        await AppServices.metrics.insert(MetricEntry(
          date: dateStr,
          metricType: MetricTypeKey.forSorenessCategory(entry.key),
          value: entry.value.toDouble(),
          loggedAt: loggedAt,
        ));
      }

      // Bodyweight roughly twice a week.
      if (date.weekday == DateTime.monday || date.weekday == DateTime.thursday) {
        await AppServices.bodyweight.insert(BodyweightEntry(
          date: dateStr,
          weight: double.parse(
              (152 - progress * 1.5 + _rand.nextDouble() * 1.5).toStringAsFixed(1)),
        ));
      }
    }

    await _loadCycleData(start);

    AppServices.signalReload();
  }

  static Future<void> _logLift(
    Exercise exercise,
    double progress,
    double growth,
    String dateStr, {
    bool forceRecovery = false,
  }) async {
    final baseline = _startingWeights[exercise.name] ?? 100.0;
    final workingWeight = baseline * (1 + growth * progress);

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
    // Two rough periods over the 60-day window, ~28 days apart. A period is
    // just a run of days with flow > 0 — no separate start/end record.
    const flowPattern = [2, 4, 3, 1, 1];
    for (final cycleStartOffset in [4, 32]) {
      final periodStart = start.add(Duration(days: cycleStartOffset));
      for (var i = 0; i < flowPattern.length; i++) {
        await AppServices.cycle.setFlow(
          _fmt(periodStart.add(Duration(days: i))),
          flowPattern[i],
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
