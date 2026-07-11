import 'strength_standards.dart';
import 'user_profile.dart';

/// Rep-count strength standards for bodyweight movements (`ExerciseType.
/// bodyweight`) — a parallel, smaller sibling to `StrengthStandards`. Real
/// published pull-up/push-up standards are commonly given as flat rep counts
/// (e.g. "Beginner: 1-3, Elite: 20+"), not a bodyweight-ratio-of-max-load
/// multiplier like the barbell tables, so this is a separate table shape
/// rather than reusing `StrengthStandards`' multiplier math — same 5-tier
/// ladder and gender/age-bucket adjustment pattern, though, so it plugs into
/// the same `StrengthGoalGauge`/`StrengthTier` machinery unchanged.
/// Approximate, commonly-cited-style figures — not individually measured,
/// same directional-generalization caveat as the rest of this app.
abstract class BodyweightRepStandards {
  static const Map<String, Map<Gender, Map<StrengthTier, int>>> _reps = {
    'Pull Up': {
      Gender.male: {
        StrengthTier.beginner: 1,
        StrengthTier.novice: 4,
        StrengthTier.intermediate: 8,
        StrengthTier.advanced: 14,
        StrengthTier.elite: 20,
      },
      Gender.female: {
        StrengthTier.beginner: 1,
        StrengthTier.novice: 2,
        StrengthTier.intermediate: 4,
        StrengthTier.advanced: 8,
        StrengthTier.elite: 12,
      },
    },
    'Push Up': {
      Gender.male: {
        StrengthTier.beginner: 5,
        StrengthTier.novice: 12,
        StrengthTier.intermediate: 20,
        StrengthTier.advanced: 35,
        StrengthTier.elite: 50,
      },
      Gender.female: {
        StrengthTier.beginner: 3,
        StrengthTier.novice: 8,
        StrengthTier.intermediate: 15,
        StrengthTier.advanced: 25,
        StrengthTier.elite: 40,
      },
    },
  };

  static bool hasStandard(String exerciseName) => _reps.containsKey(exerciseName);

  /// All 5 tiers' target rep counts at once, gender + age-bucket adjusted
  /// (same multiplier as the barbell tables, rounded to a whole rep and
  /// floored at 1 so a lower bracket never rounds down to "0 reps").
  static Map<StrengthTier, double>? allTargets({
    required String exerciseName,
    required Gender gender,
    required AgeBucket ageBucket,
  }) {
    final base = _reps[exerciseName]?[gender];
    if (base == null) return null;
    return {
      for (final tier in StrengthTier.values)
        tier: (base[tier]! * ageBucket.standardMultiplier).round().clamp(1, 999).toDouble(),
    };
  }
}
