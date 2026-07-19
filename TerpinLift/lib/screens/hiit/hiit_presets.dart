import '../../data/models/hiit_slot.dart';

/// One slot in a preset, keyed by exercise *name* rather than id — presets
/// are hardcoded before any particular database's exercise ids exist, so
/// `HiitSetupScreen._applyPreset` resolves each name against the currently
/// loaded exercise library at apply time (and silently skips a slot whose
/// name isn't found, same "don't crash on a missing lookup" convention as
/// the rest of the HIIT screens).
class HiitPresetSlot {
  final String exerciseName;
  final HiitTargetType targetType;
  final double? targetValue;
  final double? weight;
  final int? restAfterSeconds;

  const HiitPresetSlot({
    required this.exerciseName,
    required this.targetType,
    this.targetValue,
    this.weight,
    this.restAfterSeconds,
  });
}

/// A hardcoded starting point for `HiitSetupScreen` — applying one replaces
/// the current draft (with a confirmation if anything's already been built)
/// so the user can tweak from there rather than build from a blank screen.
class HiitPreset {
  final String name;
  final bool automatic;
  final List<List<HiitPresetSlot>> rounds;

  const HiitPreset({
    required this.name,
    required this.automatic,
    required this.rounds,
  });
}

/// A small curated set of practical examples, not a full library — see
/// designFiles/12_SCREEN_hiit.md for why only these three shipped first.
const hiitPresets = <HiitPreset>[
  HiitPreset(
    name: 'Full-Body AMRAP Ladder',
    automatic: false,
    rounds: [
      [
        HiitPresetSlot(
          exerciseName: 'Push Up',
          targetType: HiitTargetType.amrap,
          targetValue: 20,
          restAfterSeconds: 15,
        ),
        HiitPresetSlot(
          exerciseName: 'Walking Lunge',
          targetType: HiitTargetType.amrap,
          targetValue: 20,
          restAfterSeconds: 15,
        ),
        HiitPresetSlot(
          exerciseName: 'Dumbbell Curl',
          targetType: HiitTargetType.amrap,
          targetValue: 20,
          weight: 15,
          restAfterSeconds: 45,
        ),
      ],
      [
        HiitPresetSlot(
          exerciseName: 'Push Up',
          targetType: HiitTargetType.amrap,
          targetValue: 30,
          restAfterSeconds: 15,
        ),
        HiitPresetSlot(
          exerciseName: 'Walking Lunge',
          targetType: HiitTargetType.amrap,
          targetValue: 30,
          restAfterSeconds: 15,
        ),
        HiitPresetSlot(
          exerciseName: 'Dumbbell Curl',
          targetType: HiitTargetType.amrap,
          targetValue: 30,
          weight: 15,
          restAfterSeconds: 45,
        ),
      ],
      [
        HiitPresetSlot(
          exerciseName: 'Push Up',
          targetType: HiitTargetType.amrap,
          targetValue: 40,
          restAfterSeconds: 15,
        ),
        HiitPresetSlot(
          exerciseName: 'Walking Lunge',
          targetType: HiitTargetType.amrap,
          targetValue: 40,
          restAfterSeconds: 15,
        ),
        HiitPresetSlot(
          exerciseName: 'Dumbbell Curl',
          targetType: HiitTargetType.amrap,
          targetValue: 40,
          weight: 15,
        ),
      ],
    ],
  ),
  HiitPreset(
    name: 'Beginner Intro Circuit',
    automatic: false,
    rounds: [
      [
        HiitPresetSlot(
          exerciseName: 'Push Up',
          targetType: HiitTargetType.reps,
          targetValue: 8,
          restAfterSeconds: 30,
        ),
        HiitPresetSlot(
          exerciseName: 'Walking Lunge',
          targetType: HiitTargetType.reps,
          targetValue: 10,
          restAfterSeconds: 30,
        ),
        HiitPresetSlot(
          exerciseName: 'Stairs',
          targetType: HiitTargetType.time,
          targetValue: 120,
          restAfterSeconds: 60,
        ),
      ],
      [
        HiitPresetSlot(
          exerciseName: 'Push Up',
          targetType: HiitTargetType.reps,
          targetValue: 8,
          restAfterSeconds: 30,
        ),
        HiitPresetSlot(
          exerciseName: 'Walking Lunge',
          targetType: HiitTargetType.reps,
          targetValue: 10,
          restAfterSeconds: 30,
        ),
        HiitPresetSlot(
          exerciseName: 'Stairs',
          targetType: HiitTargetType.time,
          targetValue: 120,
        ),
      ],
    ],
  ),
  HiitPreset(
    name: 'Arm Day Dumbbell Circuit',
    automatic: false,
    rounds: [
      [
        HiitPresetSlot(
          exerciseName: 'Dumbbell Curl',
          targetType: HiitTargetType.reps,
          targetValue: 12,
          weight: 20,
        ),
        HiitPresetSlot(
          exerciseName: 'Hammer Curl',
          targetType: HiitTargetType.reps,
          targetValue: 12,
          weight: 20,
        ),
        HiitPresetSlot(
          exerciseName: 'Lateral Raise',
          targetType: HiitTargetType.reps,
          targetValue: 15,
          weight: 10,
        ),
        HiitPresetSlot(
          exerciseName: 'Preacher Curl',
          targetType: HiitTargetType.reps,
          targetValue: 10,
          weight: 15,
          restAfterSeconds: 60,
        ),
      ],
      [
        HiitPresetSlot(
          exerciseName: 'Dumbbell Curl',
          targetType: HiitTargetType.reps,
          targetValue: 12,
          weight: 20,
        ),
        HiitPresetSlot(
          exerciseName: 'Hammer Curl',
          targetType: HiitTargetType.reps,
          targetValue: 12,
          weight: 20,
        ),
        HiitPresetSlot(
          exerciseName: 'Lateral Raise',
          targetType: HiitTargetType.reps,
          targetValue: 15,
          weight: 10,
        ),
        HiitPresetSlot(
          exerciseName: 'Preacher Curl',
          targetType: HiitTargetType.reps,
          targetValue: 10,
          weight: 15,
          restAfterSeconds: 60,
        ),
      ],
      [
        HiitPresetSlot(
          exerciseName: 'Dumbbell Curl',
          targetType: HiitTargetType.reps,
          targetValue: 10,
          weight: 20,
        ),
        HiitPresetSlot(
          exerciseName: 'Hammer Curl',
          targetType: HiitTargetType.reps,
          targetValue: 10,
          weight: 20,
        ),
        HiitPresetSlot(
          exerciseName: 'Lateral Raise',
          targetType: HiitTargetType.reps,
          targetValue: 12,
          weight: 10,
        ),
        HiitPresetSlot(
          exerciseName: 'Preacher Curl',
          targetType: HiitTargetType.reps,
          targetValue: 8,
          weight: 15,
        ),
      ],
    ],
  ),
];
