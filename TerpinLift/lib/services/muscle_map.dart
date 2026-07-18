import 'package:flutter_body_heatmap/flutter_body_heatmap.dart';

import '../data/models/exercise.dart';
import '../data/models/metric_entry.dart';

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

  /// Soreness sub-region -> specific muscles, finer than [broadGroups] —
  /// used for soreness *logging* specifically (`SorenessBodyMapForm`, the
  /// Metrics soreness preview, and `ReadinessEngine`'s soreness proxy).
  /// [broadGroups]/[categoryForMuscle] stay as-is for everything else
  /// (Training Composition, the Home status icons' recovery-window
  /// averaging) — this is a parallel, finer split just for soreness, not a
  /// replacement. Minor joint-adjacent regions (knees, tibialis, ankles,
  /// feet) fold into the nearest major region (quads/calves) rather than
  /// getting their own tap target.
  static const Map<SorenessRegion, List<Muscle>> sorenessRegionGroups = {
    SorenessRegion.chest: [Muscle.chest],
    SorenessRegion.coreCenter: [Muscle.abs],
    SorenessRegion.coreSides: [Muscle.obliques],
    SorenessRegion.upperBack: [Muscle.upperBack, Muscle.trapezius],
    SorenessRegion.lowerBack: [Muscle.lowerBack],
    SorenessRegion.biceps: [Muscle.biceps],
    SorenessRegion.triceps: [Muscle.triceps],
    SorenessRegion.shoulders: [Muscle.deltoids],
    SorenessRegion.forearms: [Muscle.forearm],
    SorenessRegion.quads: [Muscle.quadriceps, Muscle.knees],
    SorenessRegion.hamstrings: [Muscle.hamstring],
    SorenessRegion.glutes: [Muscle.gluteal],
    SorenessRegion.calves: [Muscle.calves, Muscle.tibialis, Muscle.ankles, Muscle.feet],
    SorenessRegion.innerThigh: [Muscle.adductors],
  };

  static SorenessRegion? regionForMuscle(Muscle muscle) {
    for (final entry in sorenessRegionGroups.entries) {
      if (entry.value.contains(muscle)) return entry.key;
    }
    return null;
  }

  /// Curated fine-grained muscle lists for the 5 seeded lifts, used for the
  /// static "muscles this hits" diagram on Lift detail. Keyed by exercise
  /// name rather than id, since these are hand-picked reference data, not
  /// something derived from logged sets.
  static const Map<String, List<Muscle>> liftMuscles = {
    // --- Squat pattern ---
    'Front Squat': [Muscle.quadriceps, Muscle.abs, Muscle.adductors, Muscle.gluteal],
    'Back Squat': [Muscle.quadriceps, Muscle.gluteal, Muscle.adductors, Muscle.lowerBack],
    'Hack Squat': [Muscle.quadriceps, Muscle.gluteal, Muscle.adductors],
    'Smith Machine Squat': [Muscle.quadriceps, Muscle.gluteal, Muscle.adductors],
    'Bulgarian Split Squat': [Muscle.quadriceps, Muscle.gluteal, Muscle.adductors],
    'Walking Lunge': [Muscle.quadriceps, Muscle.gluteal, Muscle.adductors],
    'Reverse Lunge': [Muscle.quadriceps, Muscle.gluteal, Muscle.adductors],

    // --- Hinge pattern ---
    'Deadlift': [
      Muscle.hamstring,
      Muscle.gluteal,
      Muscle.lowerBack,
      Muscle.trapezius,
      Muscle.forearm,
    ],
    // Wider stance shifts more load onto quads/adductors and less onto the
    // lower back than a conventional pull, per how sumo is usually coached.
    'Sumo Deadlift': [Muscle.quadriceps, Muscle.gluteal, Muscle.adductors, Muscle.lowerBack],
    'Romanian Deadlift': [Muscle.hamstring, Muscle.gluteal, Muscle.lowerBack],
    'Trap Bar Deadlift': [Muscle.quadriceps, Muscle.hamstring, Muscle.gluteal, Muscle.trapezius],
    'Good Morning': [Muscle.hamstring, Muscle.lowerBack, Muscle.gluteal],
    'Hip Thrust': [Muscle.gluteal, Muscle.hamstring],
    'Hip Thrust Machine': [Muscle.gluteal, Muscle.hamstring],
    'Glute Bridge Machine': [Muscle.gluteal, Muscle.hamstring],
    'Glute Ham Raise': [Muscle.hamstring, Muscle.gluteal],
    'Cable Pull-Through': [Muscle.gluteal, Muscle.hamstring],
    'Leg Curl': [Muscle.hamstring],
    // Olympic pulls — hinge-dominant, with a trap/shoulder finish.
    'Power Clean': [Muscle.hamstring, Muscle.gluteal, Muscle.trapezius, Muscle.quadriceps],
    'Snatch': [Muscle.hamstring, Muscle.gluteal, Muscle.trapezius, Muscle.deltoids],
    'Clean and Jerk': [
      Muscle.hamstring,
      Muscle.gluteal,
      Muscle.trapezius,
      Muscle.deltoids,
      Muscle.quadriceps,
    ],

    // --- Horizontal push ---
    'Bench Press': [Muscle.chest, Muscle.triceps, Muscle.deltoids],
    'Incline Bench Press': [Muscle.chest, Muscle.deltoids, Muscle.triceps],
    'Decline Bench Press': [Muscle.chest, Muscle.triceps, Muscle.deltoids],
    // Narrower grip shifts emphasis onto triceps over chest.
    'Close-Grip Bench Press': [Muscle.triceps, Muscle.chest, Muscle.deltoids],
    'Dumbbell Bench Press': [Muscle.chest, Muscle.triceps, Muscle.deltoids],
    'Chest Press Machine': [Muscle.chest, Muscle.triceps, Muscle.deltoids],
    'Smith Machine Bench Press': [Muscle.chest, Muscle.triceps, Muscle.deltoids],
    'Push Up': [Muscle.chest, Muscle.triceps, Muscle.deltoids, Muscle.abs],
    'Dip': [Muscle.chest, Muscle.triceps, Muscle.deltoids],
    // Isolation fly-pattern movements — chest only, minimal triceps/delt
    // involvement compared to a press.
    'Pec Deck': [Muscle.chest],
    'Cable Fly': [Muscle.chest],

    // --- Vertical push ---
    'Overhead Press': [Muscle.deltoids, Muscle.triceps, Muscle.trapezius],
    'Push Press': [Muscle.deltoids, Muscle.triceps, Muscle.quadriceps, Muscle.trapezius],
    'Dumbbell Shoulder Press': [Muscle.deltoids, Muscle.triceps, Muscle.trapezius],
    'Arnold Press': [Muscle.deltoids, Muscle.triceps, Muscle.trapezius],
    'Shoulder Press Machine': [Muscle.deltoids, Muscle.triceps],
    'Landmine Press': [Muscle.deltoids, Muscle.triceps, Muscle.chest],
    'Split Jerk': [Muscle.deltoids, Muscle.triceps, Muscle.quadriceps],
    'Push Jerk': [Muscle.deltoids, Muscle.triceps, Muscle.quadriceps],

    // --- Horizontal pull ---
    'Barbell Row': [Muscle.upperBack, Muscle.lowerBack, Muscle.biceps, Muscle.forearm],
    'Pendlay Row': [Muscle.upperBack, Muscle.lowerBack, Muscle.biceps, Muscle.forearm],
    'Dumbbell Row': [Muscle.upperBack, Muscle.biceps, Muscle.forearm],
    'Seated Cable Row': [Muscle.upperBack, Muscle.biceps, Muscle.forearm],
    'T-Bar Row': [Muscle.upperBack, Muscle.lowerBack, Muscle.biceps, Muscle.forearm],

    // --- Vertical pull ---
    'Pull Up': [Muscle.upperBack, Muscle.biceps, Muscle.forearm, Muscle.trapezius],
    // Supinated grip biases more biceps than a pull-up, same muscle group set.
    'Chin Up': [Muscle.upperBack, Muscle.biceps, Muscle.forearm, Muscle.trapezius],
    'Lat Pulldown': [Muscle.upperBack, Muscle.biceps, Muscle.forearm],
    // Straight-arm variant isolates the lats out of the elbow-flexion
    // (biceps) role a normal pulldown/pull-up has.
    'Straight-Arm Cable Pulldown': [Muscle.upperBack, Muscle.triceps],

    // --- Shoulder prehab / rear delt ---
    'Face Pull': [Muscle.deltoids, Muscle.upperBack, Muscle.trapezius],
    'Rear Delt Fly': [Muscle.deltoids, Muscle.upperBack],

    // --- Arms / aesthetic isolation ---
    'Barbell Curl': [Muscle.biceps, Muscle.forearm],
    'Dumbbell Curl': [Muscle.biceps, Muscle.forearm],
    'Hammer Curl': [Muscle.biceps, Muscle.forearm],
    'Preacher Curl': [Muscle.biceps],
    'Cable Bicep Curl': [Muscle.biceps, Muscle.forearm],
    'Skull Crushers': [Muscle.triceps],
    'Overhead Triceps Extension': [Muscle.triceps],
    'Cable Triceps Pushdown': [Muscle.triceps],
    'Lateral Raise': [Muscle.deltoids],
    'Front Raise': [Muscle.deltoids],
    'Barbell Shrug': [Muscle.trapezius],
    'Dumbbell Shrug': [Muscle.trapezius],
    'Wrist Curl': [Muscle.forearm],

    // --- Quad/glute & hamstring/glute accessory machines ---
    'Leg Press': [Muscle.quadriceps, Muscle.gluteal, Muscle.adductors],
    'Leg Extension': [Muscle.quadriceps],
    'Standing Calf Raise': [Muscle.calves],
    'Seated Calf Raise': [Muscle.calves],
    'Seated Calf Raise Machine': [Muscle.calves],

    // --- Adductor/abductor ---
    'Hip Adduction Machine': [Muscle.adductors],
    // No dedicated "abductor" region in this package's muscle set — glute
    // medius/minimus (the actual hip abductors) fold under `gluteal`.
    'Hip Abduction Machine': [Muscle.gluteal],

    // --- Core ---
    'Sit Up': [Muscle.abs],
    'Crunch': [Muscle.abs],
    // A straight-leg raise is ab/hip-flexor dominant, not an oblique/rotary
    // movement — narrower than the broad "core" fallback, plus grip.
    'Hanging Leg Raise': [Muscle.abs, Muscle.forearm],
    'Cable Woodchopper': [Muscle.obliques, Muscle.abs],
    'Pallof Press': [Muscle.obliques, Muscle.abs],
    // A rotational twist — obliques lead, abs assist.
    'Russian Twist': [Muscle.obliques, Muscle.abs],
    // Anti-extension core-stability drill (opposite-arm/leg reach) — no
    // rotation, so abs only, unlike Russian Twist/Bicycle Crunch.
    'Dead Bug': [Muscle.abs],
    'Bicycle Crunch': [Muscle.abs, Muscle.obliques],
    'Flutter Kicks': [Muscle.abs],
    'V-Up': [Muscle.abs],
    'Leg Raise': [Muscle.abs],
    // Anti-rotation stability, same pattern as Dead Bug but face-down —
    // light lower-back involvement holding the extended position.
    'Bird Dog': [Muscle.abs, Muscle.lowerBack],
    // Prone back extension — the reverse of a crunch, works the posterior
    // chain (lower back + glutes) rather than the abs.
    'Superman': [Muscle.lowerBack, Muscle.gluteal],

    // --- Machines added v11 (Precor lineup cross-check) ---
    'Ab Crunch Machine': [Muscle.abs],
    'Back Extension Machine': [Muscle.lowerBack, Muscle.gluteal],
    'Rotary Torso Machine': [Muscle.obliques],
    'Glute Extension Machine': [Muscle.gluteal, Muscle.hamstring],
    'Bicep Curl Machine': [Muscle.biceps, Muscle.forearm],
    'Triceps Extension Machine': [Muscle.triceps],
    'Seated Dip Machine': [Muscle.chest, Muscle.triceps, Muscle.deltoids],
    'Low Row Machine': [Muscle.upperBack, Muscle.biceps, Muscle.forearm],

    // --- Cardio ---
    'Rowing Machine': [Muscle.upperBack, Muscle.quadriceps, Muscle.hamstring, Muscle.forearm],
  };

  /// Muscles to highlight for a given exercise: the user's own
  /// [Exercise.targetMuscles] if they've set any (either at creation or via
  /// the muscle-selector popup), otherwise the curated list if one exists
  /// (older seeded lifts), otherwise a fallback built from the exercise's
  /// own broad category tags — less precise, but better than showing
  /// nothing.
  static List<Muscle> musclesFor(Exercise exercise) {
    if (exercise.targetMuscles.isNotEmpty) return exercise.targetMuscles;
    final curated = liftMuscles[exercise.name];
    if (curated != null) return curated;
    return exercise.categories
        .expand((c) => broadGroups[c] ?? const <Muscle>[])
        .toSet()
        .toList();
  }
}
