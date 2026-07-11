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
  static Future<void> load() async {
    await AppServices.db.wipeEverythingAndReseed();
    final exercises = await AppServices.exercises.getAll();

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
        await _logLift(
          primary,
          progress,
          amplitudeByExercise[primary.id]!,
          dateStr,
        );
        for (final tag in primary.categories
            .where(TrainingCompositionService.bodyPartCategories.contains)) {
          sorenessEvents.add((day: offset, category: tag, magnitude: 3.5));
        }

        // Roughly 40% of gym days include a second movement at lower effort,
        // mirroring "one all-out lift, others lighter" per the user's real routine.
        if (_rand.nextDouble() < 0.4) {
          final secondary = exercises[(offset + 2) % exercises.length];
          if (secondary.id != primary.id) {
            await _logLift(
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

    await _loadCycleData(start);

    AppServices.signalReload();
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
        metricType: MetricTypeKey.forSorenessCategory(entry.key),
        value: entry.value.round().clamp(0, 5).toDouble(),
        loggedAt: loggedAt,
      ));
    }
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
