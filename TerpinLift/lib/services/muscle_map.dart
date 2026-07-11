import 'package:flutter/material.dart';
import 'package:flutter_body_heatmap/flutter_body_heatmap.dart';

import '../data/models/exercise.dart';

/// What kind of quick reminder a [LiftCue] is — drives which icon it gets.
/// Deliberately just 3 kinds: this is meant to read like what a coach says
/// right before your set on a lift you already know how to do, not a
/// textbook page — setup, the movement's range of motion, and the one
/// safety/injury thing worth remembering. Not exhaustive coaching.
enum CueKind { setup, motion, safety }

extension CueKindIcon on CueKind {
  IconData get icon {
    switch (this) {
      case CueKind.setup:
        return Icons.play_circle_outline;
      case CueKind.motion:
        return Icons.compare_arrows;
      case CueKind.safety:
        return Icons.warning_amber_rounded;
    }
  }
}

class LiftCue {
  final CueKind kind;
  final String text;
  const LiftCue(this.kind, this.text);
}

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

  /// Quick pre-set reminders per seeded lift — 3 short lines (setup, range
  /// of motion, safety), not exhaustive coaching. Meant to be scannable in a
  /// few seconds by someone who already knows the lift, not a form tutorial
  /// (that's what the YouTube link is for). Placeholder-quality content on
  /// purpose for now — this round was about proving the layout, not final
  /// copy. Custom exercises get no cues (nothing curated to show).
  static const Map<String, List<LiftCue>> liftOverview = {
    'Front Squat': [
      LiftCue(CueKind.setup, 'Bar on front delts, elbows high'),
      LiftCue(CueKind.motion, 'Sit down between your hips, torso stays upright'),
      LiftCue(CueKind.safety, "Don't let your elbows drop — that dumps the bar forward"),
    ],
    'Back Squat': [
      LiftCue(CueKind.setup, 'Bar on traps, feet shoulder-width, brace before unracking'),
      LiftCue(CueKind.motion, 'Hips to parallel or below, knees track your toes'),
      LiftCue(CueKind.safety, "Keep your back neutral — don't round out at the bottom"),
    ],
    'Bench Press': [
      LiftCue(CueKind.setup, 'Shoulder blades pinned back, feet flat, slight arch'),
      LiftCue(CueKind.motion, 'Bar to chest under control, elbows ~45°, press back up'),
      LiftCue(CueKind.safety, "Use a spotter or safeties near your max — don't bounce off your chest"),
    ],
    'Deadlift': [
      LiftCue(CueKind.setup, 'Grip shoulder-width, bar over midfoot'),
      LiftCue(CueKind.motion, 'Hips down, chest up — drive through your legs, bar stays close'),
      LiftCue(CueKind.safety, "Don't round your back — brace core, no jerking it off the floor"),
    ],
    'Overhead Press': [
      LiftCue(CueKind.setup, 'Bar at collarbone, brace core and glutes'),
      LiftCue(CueKind.motion, 'Press straight up, head moves back then through at lockout'),
      LiftCue(CueKind.safety, "Don't overarch your lower back — work on shoulder mobility instead"),
    ],
  };
}
