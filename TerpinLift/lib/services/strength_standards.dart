import 'user_profile.dart';

/// 5-tier ladder for the bodyweight-ratio strength-standard goal system,
/// matching how most published strength-standard aggregators (Strength
/// Level, ExRx, etc.) structure their tables.
enum StrengthTier { beginner, novice, intermediate, advanced, elite }

extension StrengthTierLabel on StrengthTier {
  String get label {
    switch (this) {
      case StrengthTier.beginner:
        return 'Beginner';
      case StrengthTier.novice:
        return 'Novice';
      case StrengthTier.intermediate:
        return 'Intermediate';
      case StrengthTier.advanced:
        return 'Advanced';
      case StrengthTier.elite:
        return 'Elite';
    }
  }

  /// Short form for tight tick labels.
  String get shortLabel {
    switch (this) {
      case StrengthTier.beginner:
        return 'Beg';
      case StrengthTier.novice:
        return 'Nov';
      case StrengthTier.intermediate:
        return 'Int';
      case StrengthTier.advanced:
        return 'Adv';
      case StrengthTier.elite:
        return 'Elite';
    }
  }
}

/// Bodyweight-ratio strength-standard goals — a long-arc "main goal" to work
/// toward, separate from `TrendEngine.predictNextE1rm`'s near-term "try for
/// this next" number. Commonly-cited-style approximate figures (in the
/// spirit of aggregators like Strength Level / ExRx / Lon Kilgore's tables),
/// not individually measured for any specific user — directional, same
/// caveat pattern as the recovery windows and lean-mass-gain ranges
/// elsewhere in this app. Only covers the 4 lifts with commonly published
/// standards; Front Squat is derived (not separately sourced) as ~83% of
/// Back Squat, a commonly cited rough ratio between the two.
abstract class StrengthStandards {
  static const Map<String, Map<Gender, Map<StrengthTier, double>>> _bodyweightMultiples = {
    'Back Squat': {
      Gender.male: {
        StrengthTier.beginner: 0.75,
        StrengthTier.novice: 1.00,
        StrengthTier.intermediate: 1.35,
        StrengthTier.advanced: 1.75,
        StrengthTier.elite: 2.15,
      },
      Gender.female: {
        StrengthTier.beginner: 0.50,
        StrengthTier.novice: 0.75,
        StrengthTier.intermediate: 1.00,
        StrengthTier.advanced: 1.30,
        StrengthTier.elite: 1.60,
      },
    },
    'Bench Press': {
      Gender.male: {
        StrengthTier.beginner: 0.50,
        StrengthTier.novice: 0.75,
        StrengthTier.intermediate: 1.00,
        StrengthTier.advanced: 1.30,
        StrengthTier.elite: 1.60,
      },
      Gender.female: {
        StrengthTier.beginner: 0.30,
        StrengthTier.novice: 0.45,
        StrengthTier.intermediate: 0.60,
        StrengthTier.advanced: 0.80,
        StrengthTier.elite: 1.00,
      },
    },
    'Deadlift': {
      Gender.male: {
        StrengthTier.beginner: 1.00,
        StrengthTier.novice: 1.25,
        StrengthTier.intermediate: 1.65,
        StrengthTier.advanced: 2.10,
        StrengthTier.elite: 2.60,
      },
      Gender.female: {
        StrengthTier.beginner: 0.65,
        StrengthTier.novice: 0.90,
        StrengthTier.intermediate: 1.20,
        StrengthTier.advanced: 1.50,
        StrengthTier.elite: 1.90,
      },
    },
    'Overhead Press': {
      Gender.male: {
        StrengthTier.beginner: 0.35,
        StrengthTier.novice: 0.50,
        StrengthTier.intermediate: 0.65,
        StrengthTier.advanced: 0.85,
        StrengthTier.elite: 1.05,
      },
      Gender.female: {
        StrengthTier.beginner: 0.20,
        StrengthTier.novice: 0.30,
        StrengthTier.intermediate: 0.40,
        StrengthTier.advanced: 0.50,
        StrengthTier.elite: 0.65,
      },
    },
  };

  static const _frontSquatRatio = 0.83; // derived from Back Squat, not separately sourced

  static Map<StrengthTier, double>? _multiplesFor(String exerciseName, Gender gender) {
    if (exerciseName == 'Front Squat') {
      final backSquat = _bodyweightMultiples['Back Squat']?[gender];
      if (backSquat == null) return null;
      return backSquat.map((tier, mult) => MapEntry(tier, mult * _frontSquatRatio));
    }
    return _bodyweightMultiples[exerciseName]?[gender];
  }

  static bool hasStandard(String exerciseName) =>
      exerciseName == 'Front Squat' || _bodyweightMultiples.containsKey(exerciseName);

  /// Target e1RM for [tier], adjusted for gender + age bucket — or null if
  /// there's no standard for this exercise.
  static double? targetWeight({
    required String exerciseName,
    required StrengthTier tier,
    required double bodyweightLb,
    required Gender gender,
    required AgeBucket ageBucket,
  }) {
    final multiples = _multiplesFor(exerciseName, gender);
    final base = multiples?[tier];
    if (base == null) return null;
    return bodyweightLb * base * ageBucket.standardMultiplier;
  }

  /// All 5 tiers' target weights at once — the shape the gauge widget wants.
  static Map<StrengthTier, double>? allTargets({
    required String exerciseName,
    required double bodyweightLb,
    required Gender gender,
    required AgeBucket ageBucket,
  }) {
    if (!hasStandard(exerciseName)) return null;
    return {
      for (final tier in StrengthTier.values)
        tier: targetWeight(
          exerciseName: exerciseName,
          tier: tier,
          bodyweightLb: bodyweightLb,
          gender: gender,
          ageBucket: ageBucket,
        )!,
    };
  }

  /// The highest tier whose threshold the given e1RM has reached, or null if
  /// below Beginner.
  static StrengthTier? currentTier(double e1rmLb, Map<StrengthTier, double> targets) {
    StrengthTier? reached;
    for (final tier in StrengthTier.values) {
      if (e1rmLb >= targets[tier]!) reached = tier;
    }
    return reached;
  }

  /// The tier to aim for next — one above [current], or Elite itself if
  /// already there (nothing higher to show).
  static StrengthTier nextTier(StrengthTier? current) {
    if (current == null) return StrengthTier.beginner;
    final idx = StrengthTier.values.indexOf(current);
    if (idx >= StrengthTier.values.length - 1) return current;
    return StrengthTier.values[idx + 1];
  }

  /// A slow, forgiving decay applied to an all-time-best e1RM for the Goal
  /// gauge's current-position marker. Detraining research (e.g. Mujika &
  /// Padilla's reviews) finds strength is the most resilient trait to time
  /// off — trained lifters hold a peak for months with little to no loss,
  /// well past the kind of 2-4 week windows used elsewhere in this app for
  /// muscle recovery. So: no decay at all for the first ~10 weeks, then a
  /// slow taper toward a floor that still credits most of the peak (in
  /// keeping with "muscle memory" — a well-earned peak doesn't reset to
  /// zero, it just stops being assumed current). Deliberately a single
  /// number, not a confidence band — no new UI, just a more realistic input
  /// to the same gauge.
  static double effectiveBestE1rm(double bestE1rm, DateTime achievedOn, DateTime now) {
    const graceDays = 70; // ~10 weeks with no decay
    const decayHorizonDays = 270; // ~9 months to reach the max taper
    const maxDecayFraction = 0.15; // never treat more than 15% as "lost"
    final daysSince = now.difference(achievedOn).inDays;
    if (daysSince <= graceDays) return bestE1rm;
    final progress = ((daysSince - graceDays) / decayHorizonDays).clamp(0.0, 1.0);
    return bestE1rm * (1 - maxDecayFraction * progress);
  }
}
