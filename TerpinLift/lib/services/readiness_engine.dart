import 'package:flutter_body_heatmap/flutter_body_heatmap.dart';

import '../data/models/exercise.dart';
import '../data/models/lift_set.dart';
import '../data/models/metric_entry.dart';
import '../data/repositories/cardio_repository.dart';
import '../data/repositories/lift_repository.dart';
import 'app_services.dart';
import 'muscle_map.dart';
import 'training_composition_service.dart';
import 'user_profile.dart';

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

/// Verdict on a muscle/category's most recent workout — see
/// `ReadinessEngine.recentWorkoutPerformance`.
class WorkoutPerformance {
  final bool poor;
  const WorkoutPerformance(this.poor);
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
/// - **Recency, stretched when the most recent workout performed poorly**
///   (see `recentWorkoutPerformance`) — normally just a muscle-specific
///   recovery window (`_recoveryHours`: larger/compound muscle groups get
///   longer windows than smaller/isolated ones, a standard directional
///   generalization from strength-training recovery guidance, not an
///   individually measured number for this user). Performance is the
///   starting point, time-based recovery is what brings it back to neutral
///   either way: a normal/good workout uses that plain window; a genuinely
///   poor one (an e1RM dip or RPE jump against that *exercise's own*
///   history, not raw values pooled across every exercise sharing the
///   muscle) multiplies the window by `poorPerformanceWindowStretch` before
///   recency is measured against it, so it starts further from "ready" and
///   takes longer to get there — rather than an extra instant penalty
///   layered on top of an otherwise-unaffected recency clock. This is the
///   same verdict `computeCategoryStatus`'s icons use, so the two can't
///   disagree about whether a workout was good or bad, only how each
///   displays that.
/// - **Soreness** (category proxy, 0-5 scale) — higher soreness pulls
///   readiness down.
/// - **Sleep** (global modifier — cumulative deficit over the last 7
///   nights against a 7.5h reference, see `sleepFactorFor`) — poor recent
///   sleep reduces readiness everywhere, not just for one muscle.
/// - **Session volume** — if the most recent session's tonnage (reps ×
///   weight, same exercise only — see `_volumeSpikeDetected`) came in well
///   above that exercise's own recent average, that session earns a bit
///   more recovery credit than pure recency alone would give it.
/// - **Age** — `UserProfile.ageBucket.recoveryWindowMultiplier` scales every
///   muscle's recovery window (older brackets get longer windows — the
///   opposite direction from the strength-standard age adjustment, since
///   recovery from muscle damage slows with age while expected max strength
///   also declines; two different curves, not one).
/// - **Extra lower-body load from steps or logged cardio** (legs/hips
///   muscles only) — if today's step count, or the most recent cardio
///   session's duration/RPE, is well above your own recent norm, that reads
///   as extra endurance-style load concentrated in the muscles walking/
///   running actually taxes, per the well-documented interference effect
///   between endurance activity and strength recovery. Steps and cardio are
///   two overlapping proxies for the same event, so they're combined with
///   `min` rather than multiplied — see `computeMuscleReadiness`.
///
/// All factors combine multiplicatively into a single 0-1 score per muscle.
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

  /// Minimum sessions logged for a muscle/category before RPE/e1RM trend
  /// signals are trusted as fatigue rather than noise. A brand-new lifter's
  /// (or a lift's) first few sessions are dominated by rapid neural/
  /// technique-learning adaptation, not accumulating fatigue — trainees
  /// commonly see large session-to-session swings in this early phase that
  /// have nothing to do with overreaching (the well-documented "newbie
  /// gains" window in strength-training literature). Treating a 2-session
  /// swing as a trend also meant the "prior" baseline being compared
  /// against was sometimes a single noisy session rather than an average of
  /// several — 4 sessions guarantees at least 3 priors to average
  /// (`priorWindow` below), a much steadier baseline either way. This is
  /// also genuinely distinct from `StrengthStandards`' clinical-sounding
  /// "overtraining" framing: what this flags is *functional overreaching*
  /// (short-term RPE/performance dip, expected to resolve in days-to-weeks
  /// with a bit of easing off) — true Overtraining Syndrome is a much
  /// rarer, more severe condition (months of hormonal/immune disruption)
  /// this app makes no attempt to detect, and the UI copy (`MuscleStatusRow`
  /// ) is deliberately worded to match — "ease up on this group," not
  /// "you're overtrained."
  static const minSessionsForTrendSignal = 4;

  /// How much longer a muscle/category's recovery window gets when its most
  /// recent workout reads as a genuine performance dip (see
  /// `recentWorkoutPerformance`) — a flat, capped multiplier rather than one
  /// that scales continuously with how bad the dip was. **This number is a
  /// rough starting heuristic, not a research-backed figure** — there isn't
  /// a clean, specific literature result tying an exact performance-drop
  /// percentage to an exact extra-recovery-hours number (functional
  /// overreaching is described as resolving over "days to weeks" in general
  /// terms, not a formula). Flagged here deliberately as something to revisit
  /// once real usage shows whether it feels right, rather than presented as
  /// more precise than it actually is. A flat cap was chosen over an
  /// uncapped/continuously-scaled version specifically to avoid a data
  /// glitch (or a single very light warm-up set) producing an extreme
  /// multiplier.
  static const poorPerformanceWindowStretch = 1.3;

  static double _volume(List<LiftSet> sets) =>
      sets.fold<double>(0, (sum, s) => sum + s.reps * s.weight);

  /// Whether the most recent workout for a muscle/category reads as
  /// genuinely worse than normal — the shared, correctly-scoped replacement
  /// for the old `trendFatigueDetected`, used by both `computeCategoryStatus`
  /// and `computeMuscleReadiness` so they judge "was this a bad session" the
  /// same way instead of independently.
  ///
  /// [pooled] is the usual date-descending, cross-exercise list
  /// (`sessionsByMuscle[muscle]` / `sessionsByCategory[category]`) — every
  /// exercise that happens to share the muscle/category tag, same as before.
  /// The difference is *how* it's judged:
  ///
  /// - **"Today's workout" is every session sharing the most recent date**,
  ///   not just `pooled.first` — a workout that spanned two exercises on the
  ///   same day (e.g. Squat + Deadlift) no longer gets judged on whichever
  ///   one arbitrarily sorted first.
  /// - **Each exercise is compared only against its own prior history** —
  ///   this is the actual bug fix. The old version compared one exercise's
  ///   raw e1RM/RPE against an average pooled across *different* exercises
  ///   sharing the tag (e.g. a Squat session's e1RM against a Hip Adduction
  ///   Machine session's e1RM) — incommensurable numbers on wildly different
  ///   absolute scales, which could mask a real dip or manufacture a fake
  ///   one depending on what else happened to be logged nearby. Each
  ///   exercise here needs [minSessionsForTrendSignal] of its *own* sessions
  ///   before it's trusted (same grace-period reasoning as before, just
  ///   applied per-exercise instead of per-pool) — one without enough
  ///   history contributes nothing, for or against.
  /// - **Same-day exercises are combined by a tonnage-weighted average**,
  ///   not by picking one — a heavy primary lift and a deliberately light
  ///   cooldown/accessory sharing the tag should read as "normal," not
  ///   "overtrained" just because the cooldown alone looks light. Weighting
  ///   by each exercise's own logged tonnage means this self-adjusts to how
  ///   the user actually trains (a couple of heavy compounds vs. many
  ///   lighter accessory lifts) rather than needing a separate rule for
  ///   either style.
  static WorkoutPerformance recentWorkoutPerformance(
    List<SessionWithSets> pooled,
  ) {
    if (pooled.isEmpty) return const WorkoutPerformance(false);

    final mostRecentDate = pooled.first.session.date;
    final todaysSessions = pooled
        .where((s) => s.session.date == mostRecentDate)
        .toList();

    final sessionsByExercise = <int, List<SessionWithSets>>{};
    for (final s in pooled) {
      sessionsByExercise
          .putIfAbsent(s.session.exerciseId, () => [])
          .add(s); // pooled is already date-descending
    }

    double weightedRatioSum = 0;
    double weightedRpeJumpSum = 0;
    double totalWeight = 0;

    for (final today in todaysSessions) {
      final exerciseId = today.session.exerciseId;
      final ownHistory = sessionsByExercise[exerciseId]!;
      if (ownHistory.length < minSessionsForTrendSignal) continue;

      final priorWindow = ownHistory
          .where((s) => s.session.date != mostRecentDate)
          .take(3)
          .toList();
      if (priorWindow.isEmpty) continue;

      final weight = _volume(today.sets);
      if (weight <= 0) continue;

      final priorAvgE1rm =
          priorWindow.map((s) => s.bestE1rm).reduce((a, b) => a + b) /
          priorWindow.length;
      final ratio = priorAvgE1rm > 0 ? today.bestE1rm / priorAvgE1rm : 1.0;

      final recentAvgRpe = _avgRpe(today.sets);
      final priorAvgRpe = _avgOf(priorWindow.map((s) => _avgRpe(s.sets)));
      final rpeJump =
          recentAvgRpe != null &&
          priorAvgRpe != null &&
          recentAvgRpe - priorAvgRpe > 1.5;

      weightedRatioSum += ratio * weight;
      weightedRpeJumpSum += (rpeJump ? 1.0 : 0.0) * weight;
      totalWeight += weight;
    }

    if (totalWeight <= 0) return const WorkoutPerformance(false);

    final weightedRatio = weightedRatioSum / totalWeight;
    final weightedRpeJumpShare = weightedRpeJumpSum / totalWeight;
    // Same thresholds the old per-pool check used — an e1RM ratio below
    // 0.95, or the tonnage-weighted majority of today's exercises showing an
    // RPE jump (>0.5 share, i.e. more of today's work read as harder than
    // usual than not).
    final poor = weightedRatio < 0.95 || weightedRpeJumpShare > 0.5;
    return WorkoutPerformance(poor);
  }

  /// True if the most recent session hitting [muscle] moved notably more
  /// total weight (reps × weight) than that **same exercise's** own recent
  /// average — a session doing meaningfully more work needs a bit more
  /// recovery credit than pure recency alone accounts for. Deliberately
  /// scoped to the same exercise, not every exercise sharing this muscle
  /// tag — comparing tonnage across genuinely different lifts (e.g. a heavy
  /// Squat session against a Hip Adduction Machine session) is comparing
  /// incommensurable numbers — the same pitfall `recentWorkoutPerformance`
  /// used to have before its cross-exercise pooling fix; this factor was
  /// written scoped to one exercise from the start rather than repeat that
  /// mistake, and was never affected by it. Gated behind
  /// [minSessionsForTrendSignal] sessions of history for the same reason as
  /// the other trend signals — not enough same-exercise history yet to
  /// call anything a spike.
  static bool volumeSpikeDetected(List<SessionWithSets> sessionsForMuscle) {
    if (sessionsForMuscle.length < minSessionsForTrendSignal) return false;
    final recent = sessionsForMuscle.first;
    final sameExercisePrior = sessionsForMuscle
        .skip(1)
        .where((s) => s.session.exerciseId == recent.session.exerciseId)
        .take(3)
        .toList();
    if (sameExercisePrior.isEmpty) return false;

    final recentVolume = _volume(recent.sets);
    final priorAvgVolume =
        sameExercisePrior.map((s) => _volume(s.sets)).reduce((a, b) => a + b) /
        sameExercisePrior.length;
    return priorAvgVolume > 0 && recentVolume > priorAvgVolume * 1.3;
  }

  /// Extra fatigue factor for leg/hip muscles only, from unusually high
  /// step counts — a big walking/running day taxes the same muscles
  /// endurance work actually uses, on top of whatever lifting already
  /// happened (the well-documented interference effect between endurance
  /// activity and strength recovery). Compared against the user's own
  /// recent daily average (same self-relative pattern as every other trend
  /// factor here), not a fixed step target — a 15k-step day means something
  /// different for someone who averages 3k versus someone who averages 12k.
  ///
  /// **Placeholder for future recovery signals**: once Google Health
  /// Connect integration exists, HRV and resting heart rate would be much
  /// more direct systemic-fatigue measures than steps — they'd slot in here
  /// the same way this does (an extra multiplicative factor computed from a
  /// self-relative baseline). Steps is the only proxy available today.
  static Future<double> _stepsLoadFactor() async {
    final recentSteps = await AppServices.metrics.getByType(
      MetricType.steps,
      limit: 15,
    );
    if (recentSteps.length < 2) return 1.0;
    final today = recentSteps.first.value;
    final baseline = recentSteps.skip(1).map((e) => e.value).toList();
    final avg = baseline.reduce((a, b) => a + b) / baseline.length;
    if (avg <= 0 || today <= avg * 1.5) return 1.0;
    return 0.85; // notably more walking/running than usual
  }

  /// Same interference-effect reasoning as the steps factor above, but from
  /// actually-logged cardio sessions (duration, scaled by RPE when logged)
  /// rather than raw daily step count — a more specific, intensity-aware
  /// signal than steps alone for the same well-documented endurance/
  /// strength recovery interference. [sessions] must be date-descending,
  /// same convention as everywhere else in this file. Pure/testable, same
  /// split as `volumeSpikeDetected` — this does the actual comparison,
  /// `_cardioLoadFactor` below just fetches the data.
  ///
  /// Two gates before a spike can trigger, same shape as the other trend
  /// signals in this file:
  /// - **Recency** — the most recent session must be within the last 48h
  ///   (the shortest muscle recovery window used elsewhere here); a hard run
  ///   from a week ago isn't still loading today's legs.
  /// - **History** — at least [minSessionsForTrendSignal] - 1 prior sessions
  ///   to compare against, so a single early session isn't judged against
  ///   nothing (same reasoning as `trendFatigueDetected`'s grace period).
  ///
  /// Deliberately HIIT-free for now — a HIIT session's load doesn't reduce
  /// to one comparable number as cleanly (mixed reps/weight/time/distance
  /// slots), a real modeling question rather than a quick addition. Noted
  /// here as the next natural extension, not implemented.
  static bool cardioLoadSpikeDetected(
    List<CardioSessionWithEntries> sessions,
    DateTime now,
  ) {
    if (sessions.isEmpty) return false;
    final recent = sessions.first;
    final hoursSince = now
        .difference(DateTime.parse(recent.session.date))
        .inHours;
    if (hoursSince > 48) return false;

    final priorSessions = sessions.skip(1).take(5).toList();
    if (priorSessions.length < minSessionsForTrendSignal - 1) return false;

    double load(CardioSessionWithEntries s) {
      final duration = s.totalDurationSeconds.toDouble();
      // 6/10 stands in for "moderate effort" when a session has no logged
      // RPE, so an un-rated session still contributes a load number instead
      // of being skipped — scales duration up for a harder-than-usual
      // effort and down for an easy one, rather than treating duration
      // alone as the whole story.
      final intensity = (s.avgRpe ?? 6.0) / 6.0;
      return duration * intensity;
    }

    final recentLoad = load(recent);
    final priorAvgLoad =
        priorSessions.map(load).reduce((a, b) => a + b) / priorSessions.length;
    return priorAvgLoad > 0 && recentLoad > priorAvgLoad * 1.3;
  }

  static Future<double> _cardioLoadFactor() async {
    final sessions = await AppServices.cardio.getAllSessions(); // date DESC
    return cardioLoadSpikeDetected(sessions, DateTime.now()) ? 0.85 : 1.0;
  }

  /// Sleep's contribution to the global readiness modifier — cumulative
  /// deficit against a 7.5h reference over up to [nightlyHours]' worth of
  /// nights (newest-first order doesn't matter here, only the values do),
  /// rather than a plain average. This is the standard framing in
  /// sleep-debt research (e.g. Van Dongen et al. on cumulative restriction):
  /// deficit accumulates across short nights and isn't meaningfully offset
  /// by one good night mixed in, so a night *above* the reference is
  /// clamped to zero deficit rather than banking credit against a prior bad
  /// night. Pure/testable, same split as the cardio/volume factors above.
  ///
  /// A sustained ~1h/night average deficit is roughly where the literature
  /// places a meaningful next-day performance effect — that's where this
  /// hits the same 0.7 floor the previous flat-average version used, just
  /// reached by a steadier week-long signal instead of 3 noisy nights.
  static double sleepFactorFor(List<double> nightlyHours) {
    if (nightlyHours.isEmpty) return 1.0;
    const referenceHours = 7.5;
    final totalDeficit = nightlyHours.fold<double>(
      0,
      (sum, hours) =>
          sum + (referenceHours - hours).clamp(0.0, double.infinity),
    );
    final avgNightlyDeficit = totalDeficit / nightlyHours.length;
    return (1.0 - avgNightlyDeficit * 0.3).clamp(0.7, 1.0);
  }

  static Future<Map<Muscle, double>> computeMuscleReadiness() async {
    final exercises = await AppServices.exercises.getAll();
    final allSessions = await AppServices.lifts
        .getAllSessions(); // date DESC already
    final now = DateTime.now();

    // Global sleep modifier: cumulative deficit over the last 7 nights
    // against a 7.5h reference — see `sleepFactorFor`.
    final sleepEntries = await AppServices.metrics.getByType(
      MetricType.sleepHours,
      limit: 7,
    );
    final sleepFactor = sleepFactorFor(
      sleepEntries.map((e) => e.value).toList(),
    );

    // Effective (decayed) soreness per sub-region — the proxy applied to
    // every muscle within that region. Finer than the old 5 broad
    // categories (see designFiles/05_SCREEN_metrics.md "Soreness
    // sub-splitting"), so quad soreness no longer bleeds into the
    // hamstring/glute readiness score and vice versa. Uses
    // `MetricsRepository.effectiveSorenessLevel`, not a raw `getLatest` —
    // an old log fades back toward 0 the longer it goes unconfirmed rather
    // than being treated as still fully current forever; see that method's
    // doc comment.
    final sorenessByRegion = <SorenessRegion, double>{};
    for (final region in MuscleMap.sorenessRegionGroups.keys) {
      sorenessByRegion[region] = await AppServices.metrics
          .effectiveSorenessLevel(region, now: now);
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

    final ageMultiplier = UserProfile.ageBucket.recoveryWindowMultiplier;
    // Steps and logged cardio are two overlapping proxies for the same
    // underlying event (a big run day shows up in both) — combined with
    // `min`, not multiplied, so one hard run doesn't get double-penalized
    // for tripping both signals at once. Whichever one actually fires wins.
    final legLoadFactor = [
      await _stepsLoadFactor(),
      await _cardioLoadFactor(),
    ].reduce((a, b) => a < b ? a : b);
    final legMuscles =
        MuscleMap.broadGroups[ExerciseCategory.legs] ?? const <Muscle>[];

    final result = <Muscle, double>{};
    for (final entry in _recoveryHours.entries) {
      final muscle = entry.key;
      final sessions = sessionsByMuscle[muscle] ?? const <SessionWithSets>[];

      // Performance sets the starting point, time-based recovery brings it
      // back to neutral either way: a normal/good workout uses the plain
      // recovery window (unchanged from before); a genuinely poor one
      // stretches that same window by `poorPerformanceWindowStretch`, so it
      // starts further from "ready" and takes longer to get there, rather
      // than applying a separate instant penalty on top of recency. Replaces
      // the old rpeTrendFactor/overloadTrendFactor multiplicative penalties,
      // which compared raw values across every exercise sharing this muscle
      // tag — see `recentWorkoutPerformance`.
      final poor = recentWorkoutPerformance(sessions).poor;
      final recoveryWindowHours =
          entry.value *
          ageMultiplier *
          (poor ? poorPerformanceWindowStretch : 1.0);

      final recoveryFraction = sessions.isEmpty
          ? 1.0
          : (now
                        .difference(DateTime.parse(sessions.first.session.date))
                        .inHours /
                    recoveryWindowHours)
                .clamp(0.0, 1.0);

      final region = MuscleMap.regionForMuscle(muscle);
      final sorenessLevel = region != null
          ? (sorenessByRegion[region] ?? 0)
          : 0;
      final sorenessFactor = 1 - (sorenessLevel / 5) * 0.6;

      final volumeFactor = volumeSpikeDetected(sessions) ? 0.9 : 1.0;

      result[muscle] =
          (recoveryFraction *
                  volumeFactor *
                  (legMuscles.contains(muscle) ? legLoadFactor : 1.0) *
                  sorenessFactor *
                  sleepFactor)
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
  static int toBars(double readiness) =>
      (readiness.clamp(0.0, 1.0) * 5).round();

  /// Per-broad-category (`TrainingCompositionService.bodyPartCategories`)
  /// actionable status, replacing the old plain-text recency flags
  /// (`TrendEngine.recencyFlag`) that were never unified with this compass.
  /// Recomputed directly at category granularity rather than derived from
  /// `computeMuscleReadiness`'s output, since that function only returns the
  /// final multiplied score, not the underlying recency-vs-window numbers
  /// this needs to draw its own boundary — this needs to tell "just resting"
  /// apart from "actively overreaching," which the fine-grained map doesn't
  /// distinguish visually today.
  ///
  /// Uses the exact same `recentWorkoutPerformance` verdict the heatmap
  /// does, so the two can never disagree about whether the last workout was
  /// good or bad — only in how each *displays* it. Per category: **ready**
  /// once `hoursSince` clears the (possibly stretched) window; below that,
  /// **overreaching** if the last workout read as poor (still inside the
  /// *extra*, stretched portion of recovery) or **resting** otherwise (a
  /// normal recovery window, nothing wrong, just not done yet). Deliberately
  /// a per-category verdict, not one global status — the user's framing:
  /// legs being cooked shouldn't block a nudge toward arms.
  static Future<List<CategoryStatus>> computeCategoryStatus() async {
    final exercises = await AppServices.exercises.getAll();
    final allSessions = await AppServices.lifts.getAllSessions(); // date DESC
    final now = DateTime.now();

    final exerciseCategories = {
      for (final e in exercises)
        if (e.id != null)
          e.id!: e.categories.where(
            TrainingCompositionService.bodyPartCategories.contains,
          ),
    };

    final sessionsByCategory = <ExerciseCategory, List<SessionWithSets>>{};
    for (final s in allSessions) {
      final cats =
          exerciseCategories[s.session.exerciseId] ??
          const <ExerciseCategory>[];
      for (final c in cats) {
        sessionsByCategory.putIfAbsent(c, () => []).add(s);
      }
    }

    final results = <CategoryStatus>[];
    for (final category in TrainingCompositionService.bodyPartCategories) {
      final sessions =
          sessionsByCategory[category] ?? const <SessionWithSets>[];
      if (sessions.isEmpty) {
        results.add(CategoryStatus(category, MuscleGroupStatus.ready));
        continue;
      }

      final muscles = MuscleMap.broadGroups[category] ?? const <Muscle>[];
      final avgWindowHours = muscles.isEmpty
          ? 48.0
          : muscles
                    .map((m) => _recoveryHours[m] ?? 48.0)
                    .reduce((a, b) => a + b) /
                muscles.length;
      final hoursSince = now
          .difference(DateTime.parse(sessions.first.session.date))
          .inHours;

      // Same shared verdict `computeMuscleReadiness` uses, so the icons and
      // the heatmap never disagree about whether a workout was good or bad
      // — only how they each *display* that. "Overreaching" now specifically
      // means "still inside the stretched portion of recovery because the
      // last workout read as poor," not an independent instant penalty.
      final poor = recentWorkoutPerformance(sessions).poor;
      final stretchedWindowHours =
          avgWindowHours * (poor ? poorPerformanceWindowStretch : 1.0);

      final MuscleGroupStatus status;
      if (hoursSince >= stretchedWindowHours) {
        status = MuscleGroupStatus.ready;
      } else if (poor) {
        status = MuscleGroupStatus.overreaching;
      } else {
        status = MuscleGroupStatus.resting;
      }
      results.add(CategoryStatus(category, status));
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
  /// Candidates are excluded outright if they'd also work a muscle below
  /// [restThreshold] (same cutoff as `ReadinessBands`' "Needs rest" band,
  /// kept in sync by convention rather than a shared import across the
  /// service/widget layers) — a lift shouldn't get suggested here just
  /// because it happens to also hit something sore or overreaching.
  static List<Exercise> suggestPrimedLifts(
    List<Exercise> exercises,
    Map<Muscle, double> muscleReadiness, {
    int maxLifts = 4,
    double primedThreshold = 0.6,
    double restThreshold = 0.3,
  }) {
    final primedMuscles = {
      for (final entry in muscleReadiness.entries)
        if (entry.value >= primedThreshold) entry.key: entry.value,
    };
    if (primedMuscles.isEmpty) return const [];

    final covered = <Muscle>{};
    final picks = <Exercise>[];
    final remaining = exercises
        .where(
          (e) => MuscleMap.musclesFor(
            e,
          ).every((m) => (muscleReadiness[m] ?? 1.0) >= restThreshold),
        )
        .toList();

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
        final avgGain =
            newlyCovered.fold<double>(0, (sum, m) => sum + primedMuscles[m]!) /
            newlyCovered.length;
        final better =
            avgGain > bestAvgGain ||
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
      covered.addAll(
        MuscleMap.musclesFor(best).where(primedMuscles.containsKey),
      );
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
        final patterns =
            exercisePatterns[s.session.exerciseId] ?? const <MovementPattern>[];
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
