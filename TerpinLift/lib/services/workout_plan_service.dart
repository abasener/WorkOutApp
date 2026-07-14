import 'package:flutter_body_heatmap/flutter_body_heatmap.dart' show Muscle;

import '../data/models/exercise.dart';
import '../data/models/workout_plan.dart';
import '../data/repositories/lift_repository.dart';
import 'readiness_engine.dart';

/// Pure helpers for the Workout Planner's Active Day page — no DB access,
/// just derivation over already-loaded data. See
/// designFiles/10_WORKOUT_PLANNER.md "Data model — revised" for why there's
/// no stored per-slot completion: a slot's matches are computed live here,
/// from same-day logged sessions whose exercise carries that slot's
/// pattern, so logging from anywhere (FAB, a lift's own "+") just shows up
/// automatically without a write-time hook.
abstract class WorkoutPlanService {
  /// Sessions logged on [date] whose exercise carries [pattern] — the
  /// "what's already done for this slot" list. A single session can satisfy
  /// more than one pattern's slot (e.g. Clean and Jerk hitting both Hinge
  /// and Vertical Push) since this is just a filter, not an exclusive claim.
  static List<SessionWithSets> matchedSessions(
    String date,
    MovementPattern pattern,
    List<SessionWithSets> allSessions,
    Map<int, Exercise> exercisesById,
  ) {
    return allSessions.where((s) {
      if (s.session.date != date) return false;
      final exercise = exercisesById[s.session.exerciseId];
      return exercise != null && exercise.patterns.contains(pattern);
    }).toList();
  }

  /// Fraction of [patterns] that have at least one matched session on
  /// [date] — the Active Day page's soft progress bar. Not a requirement,
  /// just a glance-able signal.
  static double progressFraction(
    String date,
    List<MovementPattern> patterns,
    List<SessionWithSets> allSessions,
    Map<int, Exercise> exercisesById,
  ) {
    if (patterns.isEmpty) return 0;
    final done = patterns
        .where((p) => matchedSessions(date, p, allSessions, exercisesById).isNotEmpty)
        .length;
    return done / patterns.length;
  }

  /// For the Workouts tab: which `PlannedSession` (if any) each logged
  /// session on its date belongs to — a lift session "belongs" to the
  /// earliest-started `PlannedSession` that day whose day-patterns it
  /// matches. Deterministic tie-break for the rare same-day-multiple-
  /// sessions case; a lift matching no day's patterns maps to nothing (not
  /// grouped, shown as a normal ungrouped row).
  static Map<int, PlannedSession> assignToSessions(
    List<SessionWithSets> sessionsForDate,
    List<PlannedSession> plannedSessionsForDate,
    Map<int, WorkoutTemplateDay> daysById,
    Map<int, Exercise> exercisesById,
  ) {
    final sorted = [...plannedSessionsForDate]
      ..sort((a, b) => a.startedAt.compareTo(b.startedAt));
    final result = <int, PlannedSession>{};
    for (final liftSession in sessionsForDate) {
      if (liftSession.session.id == null) continue;
      final exercise = exercisesById[liftSession.session.exerciseId];
      if (exercise == null) continue;
      for (final planned in sorted) {
        final day = daysById[planned.templateDayId];
        if (day == null) continue;
        if (exercise.patterns.any(day.patterns.contains)) {
          result[liftSession.session.id!] = planned;
          break;
        }
      }
    }
    return result;
  }

  /// A day's overall readiness (0-5 bars, same scale as `ReadinessEngine.
  /// toBars`/`ReadinessBars`) for the Day Select list — goes beside the
  /// plain "N days ago" recency label so days sharing fatigued muscles show
  /// up even when the *pattern itself* wasn't trained recently (e.g. just
  /// squatted, so a hinge day is still worth waiting on even though
  /// deadlift specifically has the longer recency gap — legs/hips overlap).
  /// Averages `ReadinessEngine.readinessForExercise` across every exercise
  /// that carries any of the day's patterns, reusing the same muscle-level
  /// readiness signal the Lifts tab already shows per exercise rather than
  /// introducing a second readiness model.
  static int dayReadinessBars(
    List<MovementPattern> patterns,
    List<Exercise> exercises,
    Map<Muscle, double> muscleReadiness,
  ) {
    final pool = exercises.where((e) => e.patterns.any(patterns.contains)).toList();
    if (pool.isEmpty) return 5; // no known exercises to be fatigued by -> nothing holding it back
    final avg = pool
            .map((e) => ReadinessEngine.readinessForExercise(e, muscleReadiness))
            .reduce((a, b) => a + b) /
        pool.length;
    return ReadinessEngine.toBars(avg);
  }
}
