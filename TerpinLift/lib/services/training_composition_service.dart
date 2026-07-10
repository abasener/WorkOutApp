import '../data/models/exercise.dart';
import 'app_services.dart';

/// One workout day's training composition, normalized so the 5 body-part
/// proportions sum to 1.0.
class CategoryComposition {
  final DateTime date;
  final Map<ExerciseCategory, double> proportions;
  const CategoryComposition(this.date, this.proportions);
}

/// Aggregates lift sessions into a per-workout-day breakdown of which body
/// parts got trained, weighted by effort (sum of RPE), not time — see
/// designFiles/00_UX_DESIGN.md "Training composition chart" for why RPE-sum
/// was chosen over the live timer.
class TrainingCompositionService {
  /// Push/pull are movement patterns, not body parts — excluded from this
  /// specific view per the user's request.
  static const bodyPartCategories = [
    ExerciseCategory.legs,
    ExerciseCategory.core,
    ExerciseCategory.chest,
    ExerciseCategory.arms,
    ExerciseCategory.back,
  ];

  static Future<List<CategoryComposition>> compute() async {
    final exercises = await AppServices.exercises.getAll();

    // date string -> category -> accumulated RPE-sum weight
    final weightByDate = <String, Map<ExerciseCategory, double>>{};

    for (final exercise in exercises) {
      if (exercise.id == null) continue;
      final tags =
          exercise.categories.where(bodyPartCategories.contains).toList();
      if (tags.isEmpty) continue; // e.g. a push/pull-only tagged exercise

      final sessions = await AppServices.lifts.getSessionsForExercise(exercise.id!);
      for (final session in sessions) {
        final rpeSum = session.sets
            .fold<double>(0, (sum, set) => sum + (set.rpe ?? 0));
        if (rpeSum <= 0) continue; // no RPE logged -> can't attribute weight

        // Even split across however many body-part tags this exercise
        // carries (e.g. Bench = chest+arms -> half the weight each). A
        // simplifying assumption, not anatomically precise — revisit if it
        // reads oddly in practice (the un-normalized alternative is to give
        // the full rpeSum to each tag instead of splitting it).
        final share = rpeSum / tags.length;
        final dayMap = weightByDate.putIfAbsent(
          session.session.date,
          () => {for (final c in bodyPartCategories) c: 0.0},
        );
        for (final tag in tags) {
          dayMap[tag] = (dayMap[tag] ?? 0) + share;
        }
      }
    }

    final sortedDates = weightByDate.keys.toList()..sort();
    final result = <CategoryComposition>[];
    for (final dateStr in sortedDates) {
      final dayMap = weightByDate[dateStr]!;
      final total = dayMap.values.fold<double>(0, (a, b) => a + b);
      if (total <= 0) continue;
      result.add(CategoryComposition(
        DateTime.parse(dateStr),
        {for (final c in bodyPartCategories) c: dayMap[c]! / total},
      ));
    }
    return result;
  }
}
