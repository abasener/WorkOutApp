import 'dart:math' as math;

import '../data/models/lift_set.dart';
import '../data/models/workout_plan.dart';
import '../data/repositories/lift_repository.dart';
import 'number_display.dart';
import 'user_profile.dart';

enum LiftIntensity { allOut, normal, recovery }

extension LiftIntensityLabel on LiftIntensity {
  String get label {
    switch (this) {
      case LiftIntensity.allOut:
        return 'All-out';
      case LiftIntensity.normal:
        return 'Normal';
      case LiftIntensity.recovery:
        return 'Light';
    }
  }
}

/// Layer 1-2 smart-trend heuristics, per designFiles/07_SMART_TRENDS.md.
/// Deliberately simple rule-based math for now — no learned model, no
/// workout-selection logic. This only judges recency and predicts a number;
/// it never picks exercises for the user.
class TrendEngine {
  /// Days since the most recent logged session, or null if never trained.
  static int? daysSinceLastTrained(List<SessionWithSets> sessions) {
    if (sessions.isEmpty) return null;
    final last = DateTime.parse(sessions.first.session.date);
    return DateTime.now().difference(last).inDays;
  }

  /// 0-5 readiness score: 0 the day of the lift, growing by a day per point,
  /// capped at 5. Purely time-based for now (see designFiles/07_SMART_TRENDS.md
  /// layer 1) — soreness/RPE-based readiness is a later layer.
  /// Never-trained lifts read as fully ready (5).
  static int readinessScore(List<SessionWithSets> sessions) {
    final days = daysSinceLastTrained(sessions);
    if (days == null) return 5;
    return days.clamp(0, 5);
  }

  /// Total logged lift time per date, in minutes — the Metrics "Workout
  /// Duration" trend chart. Base case: sums every lift session on a date
  /// with both `started_at` and `completed_at` set (i.e. "Track time" was on
  /// when logging, `04_SCREEN_quick_log.md`); sessions without a timer just
  /// don't contribute, they're not treated as 0 minutes.
  ///
  /// **`plannedSessions` overrides this per date when a completed Workout
  /// Planner session exists for it** — a real bug found on-device: summing
  /// individual lift-log windows actually measures "how long each entry
  /// form happened to stay open," which can read far short of the true
  /// workout length (e.g. sets logged in a quick burst after the fact). A
  /// completed `PlannedSession`'s own start-to-complete span is the entire
  /// workout's actual wall-clock duration, so it replaces (not adds to) the
  /// lift-session sum for any date it covers — the two would otherwise
  /// double-count the same workout.
  static Map<String, double> workoutDurationMinutesByDate(
    List<SessionWithSets> sessions, {
    List<PlannedSession> plannedSessions = const [],
  }) {
    final result = <String, double>{};
    for (final s in sessions) {
      final startedAt = s.session.startedAt;
      final completedAt = s.session.completedAt;
      if (startedAt == null || completedAt == null) continue;
      final minutes =
          DateTime.parse(
            completedAt,
          ).difference(DateTime.parse(startedAt)).inSeconds /
          60;
      if (minutes <= 0) {
        continue; // clock skew/bad data guard, not a real duration
      }
      result[s.session.date] = (result[s.session.date] ?? 0) + minutes;
    }

    final plannedByDate = <String, double>{};
    for (final p in plannedSessions) {
      if (p.status != PlannedSessionStatus.completed || p.completedAt == null) {
        continue;
      }
      final minutes =
          DateTime.parse(
            p.completedAt!,
          ).difference(DateTime.parse(p.startedAt)).inSeconds /
          60;
      if (minutes <= 0) continue;
      plannedByDate[p.date] = (plannedByDate[p.date] ?? 0) + minutes;
    }
    result.addAll(plannedByDate);
    return result;
  }

  /// How hard the most recent session was, based on its average RPE.
  static LiftIntensity? lastIntensity(List<SessionWithSets> sessions) {
    if (sessions.isEmpty) return null;
    final avgRpe = _averageRpe(sessions.first.sets);
    if (avgRpe == null) return null;
    if (avgRpe >= 9) return LiftIntensity.allOut;
    if (avgRpe <= 5) return LiftIntensity.recovery;
    return LiftIntensity.normal;
  }

  /// Epley's e1RM (`weight × (1 + reps/30)`) with a gender-scaled divisor —
  /// used only by [predictedOneRepMax], NOT the shared `LiftSet.e1rm`/
  /// `SessionWithSets.bestE1rm` the rest of the app reads for historical
  /// e1RM charts (deliberately scoped narrowly to this one number rather
  /// than changing every e1RM figure in the app on a single flagged
  /// complaint). Rationale: research on sex differences in fatigue
  /// resistance suggests women typically show a flatter strength-vs-rep-
  /// range curve than men (relatively better muscular endurance at a given
  /// %1RM), so a straight Epley formula — effectively calibrated to a
  /// steeper, more male-typical drop-off — tends to over-project a female
  /// lifter's true 1RM from a multi-rep set. **Directional, not a precisely
  /// sourced correction** — same caveat as every other age/gender
  /// adjustment in this app (`AgeBucket`, `StrengthStandards`) — a
  /// placeholder pending the user's own repeated-lift history to check the
  /// prediction against reality.
  static double _e1rmForSet(LiftSet set, Gender gender) {
    if (set.reps <= 1) return set.weight;
    final divisor = gender == Gender.female ? 36.0 : 30.0;
    return set.weight * (1 + set.reps / divisor);
  }

  static double _bestE1rmForGender(SessionWithSets s, Gender gender) {
    if (s.sets.isEmpty) return 0;
    return s.sets
        .map((set) => _e1rmForSet(set, gender))
        .reduce((a, b) => a > b ? a : b);
  }

  /// The Goal gauge's "Predicted 1RM" line (`07_SMART_TRENDS.md`) — a
  /// gender-scaled Epley estimate (see [_e1rmForSet]) from your most recent
  /// lifting, **no time-based decay**. This used to run through a grace-
  /// period/taper curve on top (`StrengthStandards.effectiveBestE1rm`,
  /// since removed entirely); dropped per the user's call that a decay
  /// model implied more hard science behind 1RM prediction than actually
  /// exists at this level — "just predicted 1RM based on most recent
  /// history," not a detraining model. Takes the highest gender-scaled
  /// e1RM among the last 3 sessions
  /// (not just the single most recent one) so one unusually light day
  /// doesn't read as a sudden drop. `null` if nothing's logged yet.
  static double? predictedOneRepMax(
    List<SessionWithSets> sessions, {
    Gender gender = Gender.female,
  }) {
    final withSets = sessions.where((s) => s.sets.isNotEmpty).toList();
    if (withSets.isEmpty) return null;
    final recentSessions = withSets.take(3).toList();
    final best = recentSessions
        .map((s) => _bestE1rmForGender(s, gender))
        .reduce((a, b) => a > b ? a : b);

    // Precision matches what was actually logged in these recent sessions,
    // not whatever raw digits the Epley formula happens to produce — same
    // rule as predictNextAtCharacteristicReps, see NumberDisplay.
    final referenceWeights = [
      for (final s in recentSessions)
        for (final set in s.sets) set.weight,
    ];
    final precision = NumberDisplay.precisionNeeded(referenceWeights);
    return NumberDisplay.roundTo(best, precision);
  }

  /// The near-term "what to aim for" prediction (`07_SMART_TRENDS.md`
  /// "Predicted Next — reworked around the user's own characteristic rep
  /// range"), redesigned to avoid rep-to-1RM conversion **entirely** rather
  /// than trying to tune the conversion formula further — instead of
  /// estimating a 1RM from whatever reps you happened to log, it finds the
  /// rep count you actually tend to go heavy at, and predicts a weight at
  /// *that same rep count*, so there's no formula converting between rep
  /// ranges to get wrong in the first place.
  ///
  /// 1. **Characteristic reps**: for each session, the rep count on its
  ///    single heaviest set (by [loadOf]); the most common value across
  ///    sessions wins (ties broken toward whichever occurred more
  ///    recently, via scan order).
  /// 2. **Same-rep history**: for each session, the heaviest weight among
  ///    sets at exactly that rep count (sessions with none contribute
  ///    nothing) — a genuinely comparable weight-over-time series, since
  ///    every point is the same number of reps.
  /// 3. **Goal**: last same-rep weight + the average session-to-session
  ///    delta across up to the last 5 same-rep data points. A real newbie
  ///    stretch (rapid recent gains) and a near-plateau (~flat recent
  ///    deltas) both fall out of this on their own — no separate "assume
  ///    they're new" flag needed, the delta just reflects whatever's
  ///    actually been happening.
  /// 4. **Confidence band**: narrows as more same-rep history accumulates
  ///    (`40 / sqrt(n)` lb, clamped 5-40) — an explicit placeholder shape,
  ///    not derived from real error data yet; revisit once there's enough
  ///    real usage to check it against, same spirit as every other
  ///    "directional, not precisely sourced" placeholder in this app.
  ///
  /// [loadOf] overrides what counts as a set's "weight" — defaults to the
  /// raw `LiftSet.weight`; pass a bodyweight-adjusted selector (bodyweight +
  /// added load) for bodyweight-tagged exercises, since their `weight`
  /// field is only the added/assisted load on its own.
  static ({int reps, double low, double goal, double high, int sampleSize})?
  predictNextAtCharacteristicReps(
    List<SessionWithSets> sessions, {
    double Function(LiftSet)? loadOf,
  }) {
    final load = loadOf ?? (LiftSet s) => s.weight;
    final withSets = sessions.where((s) => s.sets.isNotEmpty).toList();
    if (withSets.isEmpty) return null;

    final heaviestSetReps = <int>[
      for (final s in withSets)
        s.sets.reduce((a, b) => load(a) >= load(b) ? a : b).reps,
    ];
    final characteristicReps = _mode(heaviestSetReps);

    final sameRepHistory = <double>[]; // date-DESC, matching withSets' order
    for (final s in withSets) {
      final atReps = s.sets.where((set) => set.reps == characteristicReps);
      if (atReps.isEmpty) continue;
      sameRepHistory.add(atReps.map(load).reduce((a, b) => a > b ? a : b));
    }
    if (sameRepHistory.isEmpty) return null;

    final lastWeight = sameRepHistory.first;
    var avgDelta = 0.0;
    if (sameRepHistory.length > 1) {
      // Oldest..newest, so consecutive deltas read as forward progress.
      final window = sameRepHistory.take(5).toList().reversed.toList();
      final deltas = [
        for (var i = 1; i < window.length; i++) window[i] - window[i - 1],
      ];
      avgDelta = deltas.reduce((a, b) => a + b) / deltas.length;
    }

    final goal = lastWeight + avgDelta;
    final n = sameRepHistory.length;
    final band = (40 / math.sqrt(n)).clamp(5.0, 40.0);

    // Precision matches what was actually logged for this rep count, not
    // whatever raw digits the averaging above happens to produce — e.g.
    // history of 1, 2.5, 3 predicts "5.3", not a falsely-precise "5.333333"
    // or an over-rounded "5".
    final precision = NumberDisplay.precisionNeeded(sameRepHistory);
    double roundedTo(double v) => NumberDisplay.roundTo(v, precision);

    return (
      reps: characteristicReps,
      low: roundedTo(goal - band),
      goal: roundedTo(goal),
      high: roundedTo(goal + band),
      sampleSize: n,
    );
  }

  /// Most frequent value in [values]; ties favor whichever candidate's
  /// count reaches the max first when scanning in [values]' own order — so
  /// for a date-DESC list (most recent first), ties lean toward the more
  /// recently-occurring value.
  static int _mode(List<int> values) {
    final counts = <int, int>{};
    for (final v in values) {
      counts[v] = (counts[v] ?? 0) + 1;
    }
    var best = values.first;
    var bestCount = 0;
    for (final v in values) {
      final c = counts[v]!;
      if (c > bestCount) {
        best = v;
        bestCount = c;
      }
    }
    return best;
  }

  static double? _averageRpe(List<LiftSet> sets) {
    final rated = sets.where((s) => s.rpe != null).map((s) => s.rpe!).toList();
    if (rated.isEmpty) return null;
    return rated.reduce((a, b) => a + b) / rated.length;
  }
}
