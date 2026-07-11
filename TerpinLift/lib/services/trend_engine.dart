import '../data/models/lift_set.dart';
import '../data/repositories/lift_repository.dart';

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

  /// How hard the most recent session was, based on its average RPE.
  static LiftIntensity? lastIntensity(List<SessionWithSets> sessions) {
    if (sessions.isEmpty) return null;
    final avgRpe = _averageRpe(sessions.first.sets);
    if (avgRpe == null) return null;
    if (avgRpe >= 9) return LiftIntensity.allOut;
    if (avgRpe <= 5) return LiftIntensity.recovery;
    return LiftIntensity.normal;
  }

  /// Predicted next e1RM as (low, goal, high), where low/high are a fixed
  /// +/-50lb band around the goal per the user's request — a placeholder
  /// band width until a real error-region model (recovery-aware, growing
  /// with distance from known data) replaces it later.
  ///
  /// This is a "try for this next" progressive-overload target, NOT a
  /// same-day prediction — it deliberately does not factor in today's
  /// soreness/sleep/recency (that's `ReadinessEngine`'s job, kept separate:
  /// this answers "what should I aim for over time," Primed for Growth
  /// answers "how do I look today"). A navigation aid toward a sensible next
  /// PR, not a coach claiming to know what you'll hit on any given day.
  /// [valueOf] overrides what "e1RM" means per session — defaults to plain
  /// weight-based `bestE1rm`; pass `SessionWithSets.bodyweightAdjustedBestE1rm`
  /// (bound to a bodyweight) for bodyweight-tagged exercises, since their
  /// `weight` field is only the added/assisted load, not the total load
  /// moved. [band] is the fixed +/- width around the goal — lb for a normal
  /// lift, left as a caller-supplied value here since a bodyweight lift's
  /// caller converts the whole result to reps afterward anyway.
  static (double low, double goal, double high)? predictNextE1rm(
    List<SessionWithSets> sessions, {
    double Function(SessionWithSets)? valueOf,
    double band = 50.0,
  }) {
    final e1rmOf = valueOf ?? (s) => s.bestE1rm;
    final withSets = sessions.where((s) => s.sets.isNotEmpty).toList();
    if (withSets.isEmpty) return null;

    // Recent window for the rolling trend (most recent 5 sessions).
    final recent = withSets.take(5).toList();
    final e1rms = recent.map(e1rmOf).toList();
    final avgE1rm = e1rms.reduce((a, b) => a + b) / e1rms.length;

    final lastSession = recent.first;
    final lastE1rm = e1rmOf(lastSession);
    final avgRpe = _averageRpe(lastSession.sets);

    // RPE-weighted confidence: near-max effort -> trust the last session's
    // number more; low effort -> lean on the rolling average instead.
    final rpeWeight = avgRpe == null ? 0.5 : (avgRpe / 10).clamp(0.2, 1.0);
    final blended = (lastE1rm * rpeWeight) + (avgE1rm * (1 - rpeWeight));

    // Scale the suggested overload step by the recent trend direction —
    // same slump-detection comparison `ReadinessEngine.overloadTrendFactor`
    // uses (last session vs. the average of the prior up-to-3), so a fixed
    // step doesn't get suggested regardless of whether progress is actually
    // happening. Real progressive-overload practice: push harder while
    // trending up, hold/consolidate during a plateau or emerging slump
    // rather than chasing a new number anyway.
    final priorWindow = recent.skip(1).take(3).toList();
    var overloadStep = 1.015; // default: modest nudge when the trend is flat
    if (priorWindow.isNotEmpty) {
      final priorAvgE1rm =
          priorWindow.map(e1rmOf).reduce((a, b) => a + b) / priorWindow.length;
      if (priorAvgE1rm > 0) {
        if (lastE1rm < priorAvgE1rm * 0.95) {
          overloadStep = 1.0; // emerging slump -> consolidate, don't chase a new number
        } else if (lastE1rm > priorAvgE1rm * 1.02) {
          overloadStep = 1.03; // clearly trending up -> a bigger ask is reasonable
        }
      }
    }

    final goal = blended * overloadStep;

    return (goal - band, goal, goal + band);
  }

  static double? _averageRpe(List<LiftSet> sets) {
    final rated = sets.where((s) => s.rpe != null).map((s) => s.rpe!).toList();
    if (rated.isEmpty) return null;
    return rated.reduce((a, b) => a + b) / rated.length;
  }
}
