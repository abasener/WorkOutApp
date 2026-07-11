import 'package:flutter_body_heatmap/flutter_body_heatmap.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:terpinlift/data/models/exercise.dart';
import 'package:terpinlift/data/models/lift_session.dart';
import 'package:terpinlift/data/repositories/lift_repository.dart';
import 'package:terpinlift/services/readiness_engine.dart';

Exercise _exercise(
  String name, {
  List<ExerciseCategory> categories = const [],
  List<MovementPattern> patterns = const [],
}) =>
    Exercise(
      id: name.hashCode,
      name: name,
      categories: categories,
      patterns: patterns,
      isSeeded: true,
      created: '2026-01-01',
    );

SessionWithSets _session(int exerciseId, String date) =>
    SessionWithSets(LiftSession(exerciseId: exerciseId, date: date), []);

void main() {
  group('ReadinessEngine.toBars', () {
    test('maps the 0-1 range onto 0-5, rounding to the nearest bar', () {
      expect(ReadinessEngine.toBars(0.0), 0);
      expect(ReadinessEngine.toBars(1.0), 5);
      expect(ReadinessEngine.toBars(0.5), 3); // 2.5 rounds up
      expect(ReadinessEngine.toBars(0.39), 2); // 1.95 rounds down
    });

    test('clamps out-of-range input rather than under/overflowing the bar scale', () {
      expect(ReadinessEngine.toBars(-1.0), 0);
      expect(ReadinessEngine.toBars(2.0), 5);
    });
  });

  group('ReadinessEngine.readinessForExercise', () {
    test('averages readiness across whatever muscles the exercise hits (Bench Press)', () {
      final bench = _exercise('Bench Press');
      final readiness = {
        Muscle.chest: 1.0,
        Muscle.triceps: 0.5,
        Muscle.deltoids: 0.0,
      };
      // Bench Press's curated muscles are exactly chest/triceps/deltoids.
      expect(ReadinessEngine.readinessForExercise(bench, readiness), closeTo(0.5, 0.001));
    });

    test('an exercise with no mapped muscles reads as fully ready, not zero', () {
      final custom = _exercise('Some Untagged Movement');
      expect(ReadinessEngine.readinessForExercise(custom, {}), 1.0);
    });

    test('a missing muscle in the readiness map defaults to fully recovered (1.0)', () {
      final bench = _exercise('Bench Press');
      // Only chest supplied; triceps/deltoids fall back to 1.0 each.
      final readiness = {Muscle.chest: 0.0};
      expect(ReadinessEngine.readinessForExercise(bench, readiness), closeTo(2 / 3, 0.001));
    });
  });

  group('ReadinessEngine.suggestPrimedLifts', () {
    test('returns nothing when no muscle clears the primed threshold', () {
      final exercises = [_exercise('Bench Press')];
      final readiness = {Muscle.chest: 0.3, Muscle.triceps: 0.3, Muscle.deltoids: 0.3};
      expect(ReadinessEngine.suggestPrimedLifts(exercises, readiness), isEmpty);
    });

    test('does not suggest two lifts that cover the same primed muscles redundantly', () {
      // Front Squat and Back Squat both hit quads/adductors/glutes; only
      // Back Squat additionally covers lowerBack, Front Squat additionally
      // covers abs. Both should still get picked since each adds unique
      // coverage, but a lift with zero unique primed muscles left should not.
      final exercises = [
        _exercise('Front Squat'),
        _exercise('Back Squat'),
        _exercise('Bench Press'), // shares nothing with the leg-day muscles below
      ];
      final readiness = {
        Muscle.quadriceps: 0.9,
        Muscle.adductors: 0.9,
        Muscle.gluteal: 0.9,
        Muscle.lowerBack: 0.9,
        Muscle.abs: 0.9,
        // chest/triceps/deltoids intentionally omitted -> not primed.
      };
      final picks = ReadinessEngine.suggestPrimedLifts(exercises, readiness);
      expect(picks.map((e) => e.name), isNot(contains('Bench Press')));
      expect(picks.length, lessThanOrEqualTo(2));
    });

    test('prefers a lift that is solidly primed over one that is only marginally primed '
        'across more muscles', () {
      // Bench Press: 2 muscles just barely over threshold (avg ~0.61).
      // Overhead Press: fewer new muscles but each much more strongly primed.
      final exercises = [_exercise('Bench Press'), _exercise('Overhead Press')];
      final readiness = {
        Muscle.chest: 0.61,
        Muscle.triceps: 0.62,
        Muscle.deltoids: 0.95, // shared by both lifts
        Muscle.trapezius: 0.95,
      };
      final picks = ReadinessEngine.suggestPrimedLifts(exercises, readiness, maxLifts: 1);
      expect(picks, hasLength(1));
      expect(picks.first.name, 'Overhead Press');
    });

    test('respects the maxLifts cap', () {
      final exercises = [
        _exercise('Front Squat'),
        _exercise('Back Squat'),
        _exercise('Deadlift'),
        _exercise('Bench Press'),
        _exercise('Overhead Press'),
        _exercise('Pull Up'),
      ];
      final readiness = {for (final m in Muscle.values) m: 0.9};
      final picks = ReadinessEngine.suggestPrimedLifts(exercises, readiness, maxLifts: 2);
      expect(picks.length, lessThanOrEqualTo(2));
    });
  });

  group('ReadinessEngine.computePatternRecency', () {
    test('a pattern with no logged sessions reads as never trained (null)', () {
      final squat = _exercise('Back Squat', patterns: [MovementPattern.squat]);
      final recency = ReadinessEngine.computePatternRecency(
        [squat],
        [_session(squat.id!, '2026-07-01')], // this session is a squat, not a hinge
      );
      expect(recency[MovementPattern.hinge], isNull);
      expect(recency[MovementPattern.squat], isNotNull);
    });

    test('picks the most recent session date among exercises sharing a pattern', () {
      final backSquat = _exercise('Back Squat', patterns: [MovementPattern.squat]);
      final frontSquat = _exercise('Front Squat', patterns: [MovementPattern.squat]);
      final now = DateTime.now();
      final fiveDaysAgo = now.subtract(const Duration(days: 5));
      final twoDaysAgo = now.subtract(const Duration(days: 2));
      final sessions = [
        // date-descending, matching how AppServices.lifts.getAllSessions
        // orders real data.
        _session(frontSquat.id!, twoDaysAgo.toIso8601String().substring(0, 10)),
        _session(backSquat.id!, fiveDaysAgo.toIso8601String().substring(0, 10)),
      ];
      final recency =
          ReadinessEngine.computePatternRecency([backSquat, frontSquat], sessions);
      expect(recency[MovementPattern.squat], 2);
    });

    test('every MovementPattern value gets an entry, even with zero sessions', () {
      final recency = ReadinessEngine.computePatternRecency([], []);
      expect(recency.keys.toSet(), MovementPattern.values.toSet());
      expect(recency.values.every((v) => v == null), isTrue);
    });
  });
}
