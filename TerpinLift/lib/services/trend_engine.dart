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
        return 'Recovery / light';
    }
  }
}

/// Layer 1-2 smart-trend heuristics, per designFiles/07_SMART_TRENDS.md.
/// Deliberately simple rule-based math for now — no learned model, no
/// workout-selection logic. This only judges recency and predicts a number;
/// it never picks exercises for the user.
class TrendEngine {
  /// Simple day-count status message for a lift, based on days since last session.
  static String? recencyFlag(List<SessionWithSets> sessions, String exerciseName) {
    if (sessions.isEmpty) return null;
    final days = daysSinceLastTrained(sessions);
    if (days == null) return null;
    if (days >= 6) {
      return '$exerciseName hasn\'t been trained in $days days — looks primed.';
    }
    if (days <= 1) {
      return '$exerciseName was just trained — likely still recovering.';
    }
    return null;
  }

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
  static (double low, double goal, double high)? predictNextE1rm(
    List<SessionWithSets> sessions,
  ) {
    final withSets = sessions.where((s) => s.sets.isNotEmpty).toList();
    if (withSets.isEmpty) return null;

    // Recent window for the rolling trend (most recent 5 sessions).
    final recent = withSets.take(5).toList();
    final e1rms = recent.map((s) => s.bestE1rm).toList();
    final avgE1rm = e1rms.reduce((a, b) => a + b) / e1rms.length;

    final lastSession = recent.first;
    final avgRpe = _averageRpe(lastSession.sets);

    // RPE-weighted confidence: near-max effort -> trust the last session's
    // number more; low effort -> lean on the rolling average instead.
    final rpeWeight = avgRpe == null ? 0.5 : (avgRpe / 10).clamp(0.2, 1.0);
    final blended = (lastSession.bestE1rm * rpeWeight) + (avgE1rm * (1 - rpeWeight));

    const smallOverloadStep = 1.02; // conservative +2% suggestion
    final goal = blended * smallOverloadStep;

    const band = 50.0;
    return (goal - band, goal, goal + band);
  }

  static double? _averageRpe(List<LiftSet> sets) {
    final rated = sets.where((s) => s.rpe != null).map((s) => s.rpe!).toList();
    if (rated.isEmpty) return null;
    return rated.reduce((a, b) => a + b) / rated.length;
  }
}
