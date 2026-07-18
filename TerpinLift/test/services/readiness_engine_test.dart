import 'package:flutter_body_heatmap/flutter_body_heatmap.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:terpinlift/data/models/exercise.dart';
import 'package:terpinlift/data/models/lift_session.dart';
import 'package:terpinlift/data/models/lift_set.dart';
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

/// Newest-first, matching `AppServices.lifts.getAllSessions()`'s ordering —
/// [rpe]/[weight] describe a single representative set for that session.
SessionWithSets _ratedSession(String date, {required double weight, double? rpe}) =>
    SessionWithSets(
      LiftSession(exerciseId: 1, date: date),
      [LiftSet(sessionId: 0, setNumber: 1, reps: 5, weight: weight, rpe: rpe)],
    );

/// Same shape as [_ratedSession] but with an explicit exercise id and reps,
/// for `volumeSpikeDetected`'s same-exercise-only scoping.
SessionWithSets _volumeSession(int exerciseId, String date,
        {required int reps, required double weight}) =>
    SessionWithSets(
      LiftSession(exerciseId: exerciseId, date: date),
      [LiftSet(sessionId: 0, setNumber: 1, reps: reps, weight: weight)],
    );

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

    test('excludes a lift that would also hit a muscle needing rest', () {
      final legPress = Exercise(
        name: 'Leg Press',
        categories: const [],
        isSeeded: true,
        created: '2026-01-01',
        targetMuscles: const [Muscle.quadriceps, Muscle.hamstring],
      );
      final legExtension = Exercise(
        name: 'Leg Extension',
        categories: const [],
        isSeeded: true,
        created: '2026-01-01',
        targetMuscles: const [Muscle.quadriceps],
      );
      final readiness = {
        Muscle.quadriceps: 0.9,
        Muscle.hamstring: 0.1, // below the rest threshold
      };
      final picks = ReadinessEngine.suggestPrimedLifts([legPress, legExtension], readiness);
      expect(picks.map((e) => e.name), isNot(contains('Leg Press')));
      expect(picks.map((e) => e.name), contains('Leg Extension'));
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

  group('ReadinessEngine.trendFatigueDetected', () {
    test('a big RPE jump on only the 2nd-ever session is not flagged — too little history', () {
      // Newest-first, matching getAllSessions()'s ordering.
      final sessions = [
        _ratedSession('2026-07-10', weight: 100, rpe: 9),
        _ratedSession('2026-07-08', weight: 100, rpe: 6),
      ];
      expect(ReadinessEngine.trendFatigueDetected(sessions), isFalse);
    });

    test('the same RPE jump is flagged once there is a stable multi-session baseline', () {
      final sessions = [
        _ratedSession('2026-07-10', weight: 100, rpe: 9),
        _ratedSession('2026-07-08', weight: 100, rpe: 6),
        _ratedSession('2026-07-06', weight: 100, rpe: 6),
        _ratedSession('2026-07-04', weight: 100, rpe: 6),
      ];
      expect(ReadinessEngine.trendFatigueDetected(sessions), isTrue);
    });

    test('an e1RM dip against the recent-average baseline is flagged at the threshold', () {
      final sessions = [
        _ratedSession('2026-07-10', weight: 80, rpe: 7), // well under prior ~100
        _ratedSession('2026-07-08', weight: 100, rpe: 7),
        _ratedSession('2026-07-06', weight: 100, rpe: 7),
        _ratedSession('2026-07-04', weight: 100, rpe: 7),
      ];
      expect(ReadinessEngine.trendFatigueDetected(sessions), isTrue);
    });

    test('ordinary session-to-session variance is not flagged', () {
      final sessions = [
        _ratedSession('2026-07-10', weight: 102, rpe: 7),
        _ratedSession('2026-07-08', weight: 100, rpe: 7),
        _ratedSession('2026-07-06', weight: 100, rpe: 6.5),
        _ratedSession('2026-07-04', weight: 98, rpe: 7),
      ];
      expect(ReadinessEngine.trendFatigueDetected(sessions), isFalse);
    });
  });

  group('ReadinessEngine.volumeSpikeDetected', () {
    test('below the grace-period session count, never flags a spike', () {
      final sessions = [
        _volumeSession(1, '2026-07-10', reps: 10, weight: 200),
        _volumeSession(1, '2026-07-08', reps: 5, weight: 100),
      ];
      expect(ReadinessEngine.volumeSpikeDetected(sessions), isFalse);
    });

    test('notably higher tonnage than the same exercise\'s recent average is flagged', () {
      final sessions = [
        _volumeSession(1, '2026-07-10', reps: 10, weight: 200), // 2000
        _volumeSession(1, '2026-07-08', reps: 5, weight: 100), // 500
        _volumeSession(1, '2026-07-06', reps: 5, weight: 100),
        _volumeSession(1, '2026-07-04', reps: 5, weight: 100),
      ];
      expect(ReadinessEngine.volumeSpikeDetected(sessions), isTrue);
    });

    test('a different exercise\'s higher tonnage in the pooled list is not compared against',
        () {
      // Same muscle, different exercise (e.g. Squat vs. Hip Adduction
      // Machine) — the whole point of scoping to the same exercise.
      final sessions = [
        _volumeSession(1, '2026-07-10', reps: 5, weight: 105), // exercise 1, modest
        _volumeSession(2, '2026-07-09', reps: 10, weight: 300), // exercise 2, huge
        _volumeSession(1, '2026-07-06', reps: 5, weight: 100), // exercise 1, prior
        _volumeSession(1, '2026-07-04', reps: 5, weight: 100), // exercise 1, prior
      ];
      expect(ReadinessEngine.volumeSpikeDetected(sessions), isFalse);
    });

    test('ordinary tonnage variance is not flagged', () {
      final sessions = [
        _volumeSession(1, '2026-07-10', reps: 5, weight: 105),
        _volumeSession(1, '2026-07-08', reps: 5, weight: 100),
        _volumeSession(1, '2026-07-06', reps: 5, weight: 100),
        _volumeSession(1, '2026-07-04', reps: 5, weight: 100),
      ];
      expect(ReadinessEngine.volumeSpikeDetected(sessions), isFalse);
    });
  });
}
