import 'package:flutter_body_heatmap/flutter_body_heatmap.dart';

import '../data/models/exercise.dart';

/// Maps between the app's 5 broad soreness categories and the body-heatmap
/// package's fine-grained (23-region) `Muscle` enum, plus curated per-lift
/// muscle lists for the "which muscles this hits" diagram on Lift detail.
///
/// Two different jobs share the same underlying muscle data on purpose (per
/// the user's plan): broad-group taps for soreness logging now, fine detail
/// for lift muscle-highlight diagrams — same package, same enum, just a
/// coarser vs. finer grouping.
abstract class MuscleMap {
  /// Broad category -> the specific muscles grouped under it for soreness
  /// logging. Neck/hair/head/hands are deliberately unmapped (tapping them
  /// in the soreness map is a no-op) since they don't fit any of the 5
  /// tracked categories.
  static const Map<ExerciseCategory, List<Muscle>> broadGroups = {
    ExerciseCategory.chest: [Muscle.chest],
    ExerciseCategory.arms: [
      Muscle.biceps,
      Muscle.triceps,
      Muscle.forearm,
      Muscle.deltoids,
    ],
    ExerciseCategory.core: [Muscle.abs, Muscle.obliques],
    ExerciseCategory.legs: [
      Muscle.quadriceps,
      Muscle.hamstring,
      Muscle.calves,
      Muscle.adductors,
      Muscle.gluteal,
      Muscle.tibialis,
      Muscle.knees,
      Muscle.ankles,
      Muscle.feet,
    ],
    ExerciseCategory.back: [Muscle.lowerBack, Muscle.upperBack, Muscle.trapezius],
  };

  /// Reverse lookup used when a tap on the body map comes back as a specific
  /// Muscle — which of the 5 broad categories does it belong to (if any).
  static ExerciseCategory? categoryForMuscle(Muscle muscle) {
    for (final entry in broadGroups.entries) {
      if (entry.value.contains(muscle)) return entry.key;
    }
    return null;
  }

  /// Curated fine-grained muscle lists for the 5 seeded lifts, used for the
  /// static "muscles this hits" diagram on Lift detail. Keyed by exercise
  /// name rather than id, since these are hand-picked reference data, not
  /// something derived from logged sets.
  static const Map<String, List<Muscle>> liftMuscles = {
    'Front Squat': [Muscle.quadriceps, Muscle.abs, Muscle.adductors, Muscle.gluteal],
    'Back Squat': [Muscle.quadriceps, Muscle.gluteal, Muscle.adductors, Muscle.lowerBack],
    'Bench Press': [Muscle.chest, Muscle.triceps, Muscle.deltoids],
    'Deadlift': [
      Muscle.hamstring,
      Muscle.gluteal,
      Muscle.lowerBack,
      Muscle.trapezius,
      Muscle.forearm,
    ],
    'Overhead Press': [Muscle.deltoids, Muscle.triceps, Muscle.trapezius],
  };

  /// Muscles to highlight for a given exercise: the curated list if one
  /// exists (the 5 seeded lifts), otherwise a fallback built from the
  /// exercise's own broad category tags — less precise, but better than
  /// showing nothing for custom movements.
  static List<Muscle> musclesFor(Exercise exercise) {
    final curated = liftMuscles[exercise.name];
    if (curated != null) return curated;
    return exercise.categories
        .expand((c) => broadGroups[c] ?? const <Muscle>[])
        .toSet()
        .toList();
  }
}
