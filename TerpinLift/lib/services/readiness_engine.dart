import 'package:flutter_body_heatmap/flutter_body_heatmap.dart';

import '../data/models/exercise.dart';
import '../data/models/lift_set.dart';
import '../data/models/metric_entry.dart';
import '../data/repositories/lift_repository.dart';
import 'app_services.dart';
import 'muscle_map.dart';
import 'training_composition_service.dart';

/// One broad muscle group's actionable status — the icon-row on Home. Three
/// states, deliberately coarser than the fine-grained readiness map: this is
/// meant to be glanceable ("what should I do right now"), not a second copy
/// of the muscle heatmap.
enum MuscleGroupStatus { ready, resting, overreaching }

class CategoryStatus {
  final ExerciseCategory category;
  final MuscleGroupStatus status;
  const CategoryStatus(this.category, this.status);
}

/// Per-muscle "primed for growth" readiness, 0.0-1.0 — the Home muscle map
/// meant to work as the app's actual navigation compass, per the user's
/// framing: not a coach telling you what to do, but the clearest possible
/// read of where your body actually is right now.
///
/// Deliberately computed at **fine-grained muscle** resolution (the same 23
/// `Muscle` regions used by the lift diagrams), not just the 5 broad
/// soreness categories — "squat = legs" is a simplification useful for the
/// Training Composition chart, but this map can do better since we already
/// know exactly which specific muscles each exercise hits
/// (`MuscleMap.musclesFor`). Soreness input is still only available at
/// broad-category resolution (that's what's actually logged), so it's
/// applied as a proxy to every muscle within its category.
///
/// Inputs, per muscle:
/// - **Recency**, normalized by a muscle-specific recovery window (see
///   `_recoveryHours` — larger/compound muscle groups get longer windows
///   than smaller/isolated ones, a standard directional generalization from
///   strength-training recovery guidance, not an individually measured
///   number for this user).
/// - **Soreness** (category proxy, 0-5 scale) — higher soreness pulls
///   readiness down.
/// - **Sleep** (global modifier, last 3 nights' average vs. a 7.5h
///   reference) — poor recent sleep reduces readiness everywhere, not just
///   for one muscle.
/// - **RPE trend** — if the most recent session hitting a muscle logged a
///   notably higher average RPE than the prior few sessions, that reads as
///   accumulating fatigue, not just normal effort.
/// - **Overload trend** — if e1RM for exercises hitting a muscle is
///   trending down against its own recent average (an emerging slump/
///   overreach), readiness is pulled down rather than just reflecting time
///   elapsed.
///
/// All five combine multiplicatively into a single 0-1 score per muscle.
class ReadinessEngine {
  /// Hours before a muscle is considered fully recovered from the last time
  /// it was trained. Bigger/multi-joint muscle groups (quads, hamstrings,
  /// glutes, lower back) get longer windows than smaller/isolated ones
  /// (biceps, triceps, abs) — directional, not lab-measured for this user.
  static const Map<Muscle, double> _recoveryHours = {
    Muscle.quadriceps: 72,
    Muscle.hamstring: 72,
    Muscle.gluteal: 72,
    Muscle.lowerBack: 72,
    Muscle.upperBack: 60,
    Muscle.trapezius: 60,
    Muscle.chest: 60,
    Muscle.adductors: 48,
    Muscle.deltoids: 48,
    Muscle.knees: 48,
    Muscle.obliques: 36,
    Muscle.calves: 36,
    Muscle.abs: 24,
    Muscle.biceps: 24,
    Muscle.triceps: 24,
    Muscle.forearm: 24,
    Muscle.tibialis: 24,
    Muscle.ankles: 24,
    Muscle.feet: 24,
  };

  static double? _avgRpe(List<LiftSet> sets) {
    final rated = sets.where((s) => s.rpe != null).map((s) => s.rpe!).toList();
    if (rated.isEmpty) return null;
    return rated.reduce((a, b) => a + b) / rated.length;
  }

  static double? _avgOf(Iterable<double?> values) {
    final nonNull = values.whereType<double>().toList();
    if (nonNull.isEmpty) return null;
    return nonNull.reduce((a, b) => a + b) / nonNull.length;
  }

  static Future<Map<Muscle, double>> computeMuscleReadiness() async {
    final exercises = await AppServices.exercises.getAll();
    final allSessions = await AppServices.lifts.getAllSessions(); // date DESC already
    final now = DateTime.now();

    // Global sleep modifier: last 3 nights' average vs. a 7.5h reference.
    final sleepEntries = await AppServices.metrics.getByType(MetricType.sleepHours, limit: 3);
    final avgSleep = sleepEntries.isEmpty
        ? 7.5
        : sleepEntries.map((e) => e.value).reduce((a, b) => a + b) / sleepEntries.length;
    final sleepFactor = (avgSleep / 7.5).clamp(0.7, 1.0);

    // Latest soreness per sub-region — the proxy applied to every muscle
    // within that region. Finer than the old 5 broad categories (see
    // designFiles/05_SCREEN_metrics.md "Soreness sub-splitting"), so quad
    // soreness no longer bleeds into the hamstring/glute readiness score
    // and vice versa.
    final sorenessByRegion = <SorenessRegion, int>{};
    for (final region in MuscleMap.sorenessRegionGroups.keys) {
      final latest =
          await AppServices.metrics.getLatest(MetricTypeKey.forSorenessRegion(region));
      sorenessByRegion[region] = latest?.value.round() ?? 0;
    }

    final exerciseMuscles = {
      for (final e in exercises)
        if (e.id != null) e.id!: MuscleMap.musclesFor(e),
    };

    // Group sessions by muscle, preserving allSessions' date-descending order.
    final sessionsByMuscle = <Muscle, List<SessionWithSets>>{};
    for (final s in allSessions) {
      final muscles = exerciseMuscles[s.session.exerciseId] ?? const <Muscle>[];
      for (final m in muscles) {
        sessionsByMuscle.putIfAbsent(m, () => []).add(s);
      }
    }

    final result = <Muscle, double>{};
    for (final entry in _recoveryHours.entries) {
      final muscle = entry.key;
      final recoveryWindowHours = entry.value;
      final sessions = sessionsByMuscle[muscle] ?? const <SessionWithSets>[];

      final recoveryFraction = sessions.isEmpty
          ? 1.0
          : (now.difference(DateTime.parse(sessions.first.session.date)).inHours /
                  recoveryWindowHours)
              .clamp(0.0, 1.0);

      final region = MuscleMap.regionForMuscle(muscle);
      final sorenessLevel = region != null ? (sorenessByRegion[region] ?? 0) : 0;
      final sorenessFactor = 1 - (sorenessLevel / 5) * 0.6;

      var rpeTrendFactor = 1.0;
      var overloadTrendFactor = 1.0;
      if (sessions.length >= 2) {
        final recent = sessions.first;
        final priorWindow = sessions.skip(1).take(3).toList();

        final recentAvgRpe = _avgRpe(recent.sets);
        final priorAvgRpe = _avgOf(priorWindow.map((s) => _avgRpe(s.sets)));
        if (recentAvgRpe != null &&
            priorAvgRpe != null &&
            recentAvgRpe - priorAvgRpe > 1.5) {
          rpeTrendFactor = 0.85; // recent effort notably harder than usual -> more fatigue
        }

        if (priorWindow.isNotEmpty) {
          final priorAvgE1rm =
              priorWindow.map((s) => s.bestE1rm).reduce((a, b) => a + b) / priorWindow.length;
          if (priorAvgE1rm > 0 && recent.bestE1rm < priorAvgE1rm * 0.95) {
            overloadTrendFactor = 0.9; // emerging slump/overreach, not just time elapsed
          }
        }
      }

      result[muscle] = (recoveryFraction *
              sorenessFactor *
              sleepFactor *
              rpeTrendFactor *
              overloadTrendFactor)
          .clamp(0.0, 1.0);
    }

    return result;
  }

  /// Aggregates the per-muscle readiness map down to a single 0-1 score for
  /// one exercise — the mean readiness across whatever muscles it hits
  /// (`MuscleMap.musclesFor`). This is the same compass everywhere it's
  /// used: the Lifts list's readiness bars and the Lift detail readiness
  /// card both read from this, rather than each having their own formula.
  /// An exercise with no mapped muscles reads as fully ready (1.0), matching
  /// the "never trained = fully ready" convention used elsewhere.
  static double readinessForExercise(
    Exercise exercise,
    Map<Muscle, double> muscleReadiness,
  ) {
    final muscles = MuscleMap.musclesFor(exercise);
    if (muscles.isEmpty) return 1.0;
    final values = muscles.map((m) => muscleReadiness[m] ?? 1.0).toList();
    return values.reduce((a, b) => a + b) / values.length;
  }

  /// Maps a 0-1 readiness score onto the same 0-5 bar scale the UI already
  /// uses (`ReadinessBars`) — deliberately reusing the existing signal-bars
  /// widget rather than introducing a second visual language for readiness.
  static int toBars(double readiness) => (readiness.clamp(0.0, 1.0) * 5).round();

  /// Per-broad-category (`TrainingCompositionService.bodyPartCategories`)
  /// actionable status, replacing the old plain-text recency flags
  /// (`TrendEngine.recencyFlag`) that were never unified with this compass.
  /// Recomputed directly at category granularity rather than derived from
  /// `computeMuscleReadiness`'s output, since that function only returns the
  /// final multiplied score, not which factor (recency vs. RPE/overload
  /// trend) drove it — this needs to tell "just resting" apart from
  /// "actively overreaching," which the fine-grained map doesn't distinguish
  /// visually today.
  ///
  /// Priority per category: **overreaching** (RPE creeping up or e1RM
  /// dipping against recent average — the same slump-detection signal
  /// `computeMuscleReadiness` uses, just not blended away into one number)
  /// beats **resting** (still inside its typical recovery window) beats
  /// **ready** (recovery window elapsed, or never trained). Deliberately a
  /// per-category verdict, not one global status — the user's framing: legs
  /// being cooked shouldn't block a nudge toward arms.
  static Future<List<CategoryStatus>> computeCategoryStatus() async {
    final exercises = await AppServices.exercises.getAll();
    final allSessions = await AppServices.lifts.getAllSessions(); // date DESC
    final now = DateTime.now();

    final exerciseCategories = {
      for (final e in exercises)
        if (e.id != null)
          e.id!: e.categories.where(TrainingCompositionService.bodyPartCategories.contains),
    };

    final sessionsByCategory = <ExerciseCategory, List<SessionWithSets>>{};
    for (final s in allSessions) {
      final cats = exerciseCategories[s.session.exerciseId] ?? const <ExerciseCategory>[];
      for (final c in cats) {
        sessionsByCategory.putIfAbsent(c, () => []).add(s);
      }
    }

    final results = <CategoryStatus>[];
    for (final category in TrainingCompositionService.bodyPartCategories) {
      final sessions = sessionsByCategory[category] ?? const <SessionWithSets>[];
      if (sessions.isEmpty) {
        results.add(CategoryStatus(category, MuscleGroupStatus.ready));
        continue;
      }

      var overreaching = false;
      if (sessions.length >= 2) {
        final recent = sessions.first;
        final priorWindow = sessions.skip(1).take(3).toList();

        final recentAvgRpe = _avgRpe(recent.sets);
        final priorAvgRpe = _avgOf(priorWindow.map((s) => _avgRpe(s.sets)));
        if (recentAvgRpe != null && priorAvgRpe != null && recentAvgRpe - priorAvgRpe > 1.5) {
          overreaching = true;
        }
        if (!overreaching && priorWindow.isNotEmpty) {
          final priorAvgE1rm =
              priorWindow.map((s) => s.bestE1rm).reduce((a, b) => a + b) / priorWindow.length;
          if (priorAvgE1rm > 0 && recent.bestE1rm < priorAvgE1rm * 0.95) {
            overreaching = true;
          }
        }
      }

      if (overreaching) {
        results.add(CategoryStatus(category, MuscleGroupStatus.overreaching));
        continue;
      }

      final muscles = MuscleMap.broadGroups[category] ?? const <Muscle>[];
      final avgWindowHours = muscles.isEmpty
          ? 48.0
          : muscles.map((m) => _recoveryHours[m] ?? 48.0).reduce((a, b) => a + b) /
              muscles.length;
      final hoursSince = now.difference(DateTime.parse(sessions.first.session.date)).inHours;
      results.add(CategoryStatus(
        category,
        hoursSince < avgWindowHours ? MuscleGroupStatus.resting : MuscleGroupStatus.ready,
      ));
    }
    return results;
  }

  /// Up to [maxLifts] exercises that, together, cover as much of the
  /// currently-primed muscle readiness as possible — a greedy weighted
  /// set-cover, not a ranked "best lift" list. Each pick is whichever
  /// remaining exercise adds the most *additional* primed-muscle coverage
  /// (muscles at or above [primedThreshold], weighted by how primed they
  /// are), so overlapping lifts that hit mostly the same primed muscles
  /// (e.g. Front Squat and Back Squat both hitting primed quads) don't both
  /// get suggested — the second one only earns a slot if it covers primed
  /// muscles the first one didn't. A guide toward good options, not a
  /// prescription ("here's what covers what's primed," not "do this").
  static List<Exercise> suggestPrimedLifts(
    List<Exercise> exercises,
    Map<Muscle, double> muscleReadiness, {
    int maxLifts = 5,
    double primedThreshold = 0.6,
  }) {
    final primedMuscles = {
      for (final entry in muscleReadiness.entries)
        if (entry.value >= primedThreshold) entry.key: entry.value,
    };
    if (primedMuscles.isEmpty) return const [];

    final covered = <Muscle>{};
    final picks = <Exercise>[];
    final remaining = [...exercises];

    while (picks.length < maxLifts && remaining.isNotEmpty) {
      Exercise? best;
      var bestAvgGain = 0.0;
      var bestNewCount = 0;
      for (final e in remaining) {
        final newlyCovered = MuscleMap.musclesFor(e)
            .where((m) => primedMuscles.containsKey(m) && !covered.contains(m))
            .toList();
        if (newlyCovered.isEmpty) continue;
        // Average, not sum, of newly-covered readiness — a lift hitting
        // many muscles that are only barely over the primed threshold
        // (e.g. a big compound like Clean and Jerk brushing several
        // moderately-primed muscles) shouldn't outrank a lift hitting one
        // or two muscles that are genuinely well-primed, just because the
        // total adds up higher. This is what "does it match the map" comes
        // down to — the map shows *how* primed, not just *how many*.
        final avgGain = newlyCovered.fold<double>(0, (sum, m) => sum + primedMuscles[m]!) /
            newlyCovered.length;
        final better = avgGain > bestAvgGain ||
            (avgGain == bestAvgGain && newlyCovered.length > bestNewCount);
        if (better) {
          bestAvgGain = avgGain;
          bestNewCount = newlyCovered.length;
          best = e;
        }
      }
      if (best == null) break; // no remaining exercise adds new coverage
      picks.add(best);
      remaining.remove(best);
      covered.addAll(MuscleMap.musclesFor(best).where(primedMuscles.containsKey));
    }
    return picks;
  }

  /// Days since any exercise tagged with [pattern] was last logged, or null
  /// if never trained — the recency cue for the Workout Planner's pattern
  /// picker (designFiles/10_WORKOUT_PLANNER.md phase 1). Deliberately just
  /// recency, not the fuller RPE/overload-trend signal `computeCategoryStatus`
  /// uses — patterns are movement categories, not muscle groups, so the
  /// slump-detection signal doesn't map onto them as cleanly, and "what
  /// hasn't been hit in a while" is really the whole ask here.
  static Map<MovementPattern, int?> computePatternRecency(
    List<Exercise> exercises,
    List<SessionWithSets> allSessions, // date DESC
  ) {
    final now = DateTime.now();
    final exercisePatterns = {
      for (final e in exercises)
        if (e.id != null) e.id!: e.patterns,
    };

    final result = <MovementPattern, int?>{};
    for (final pattern in MovementPattern.values) {
      SessionWithSets? mostRecent;
      for (final s in allSessions) {
        final patterns = exercisePatterns[s.session.exerciseId] ?? const <MovementPattern>[];
        if (patterns.contains(pattern)) {
          mostRecent = s; // allSessions is already date-descending
          break;
        }
      }
      result[pattern] = mostRecent == null
          ? null
          : now.difference(DateTime.parse(mostRecent.session.date)).inDays;
    }
    return result;
  }
}
