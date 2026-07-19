import 'package:flutter/material.dart';

import '../data/models/exercise.dart';
import 'lifts/cardio_detail_screen.dart';
import 'lifts/lift_detail_screen.dart';

/// Routes to the right detail screen for an exercise — `CardioDetailScreen`
/// for anything tagged `ExerciseType.cardio`, `LiftDetailScreen` for
/// everything else. The one place this branch lives, so a new nav call site
/// can't accidentally send a cardio exercise through the lift reps/weight
/// screen (or vice versa). See designFiles/11_SCREEN_cardio.md.
Widget exerciseDetailScreen(Exercise exercise) =>
    exercise.equipmentTags.contains(ExerciseType.cardio)
        ? CardioDetailScreen(exercise: exercise)
        : LiftDetailScreen(exercise: exercise);
