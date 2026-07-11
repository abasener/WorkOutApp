import 'package:flutter_test/flutter_test.dart';
import 'package:terpinlift/data/models/lift_session.dart';
import 'package:terpinlift/data/models/lift_set.dart';
import 'package:terpinlift/data/repositories/lift_repository.dart';

LiftSet _set({required double weight, int reps = 5}) =>
    LiftSet(sessionId: 1, setNumber: 0, reps: reps, weight: weight);

void main() {
  group('LiftSet.e1rm', () {
    test('Epley formula for a normal multi-rep set', () {
      // 100 * (1 + 5/30) = 116.666...
      expect(_set(weight: 100, reps: 5).e1rm, closeTo(116.67, 0.01));
    });

    test('a single-rep set returns the raw weight, not the Epley multiplier', () {
      expect(_set(weight: 225, reps: 1).e1rm, 225);
    });
  });

  group('SessionWithSets.bestE1rm', () {
    test('is 0 for a session with no sets', () {
      final s = SessionWithSets(const LiftSession(exerciseId: 1, date: '2026-07-01'), []);
      expect(s.bestE1rm, 0);
    });

    test('picks the highest e1RM among multiple sets', () {
      final s = SessionWithSets(
        const LiftSession(exerciseId: 1, date: '2026-07-01'),
        [_set(weight: 100, reps: 5), _set(weight: 120, reps: 3)],
      );
      expect(s.bestE1rm, s.sets.map((x) => x.e1rm).reduce((a, b) => a > b ? a : b));
    });
  });

  group('SessionWithSets.bodyweightAdjustedBestE1rm', () {
    test('plain-bodyweight set (weight 0) still produces a positive e1RM', () {
      // Plain LiftSet.e1rm would be exactly 0 here (0 * anything = 0) — the
      // whole reason this method exists for bodyweight-tagged lifts.
      final s = SessionWithSets(
        const LiftSession(exerciseId: 1, date: '2026-07-01'),
        [_set(weight: 0, reps: 10)],
      );
      expect(s.bodyweightAdjustedBestE1rm(160), greaterThan(0));
    });

    test('assisted (negative added load) still produces a positive e1RM, lower than unassisted',
        () {
      final assisted = SessionWithSets(
        const LiftSession(exerciseId: 1, date: '2026-07-01'),
        [_set(weight: -40, reps: 10)],
      );
      final unassisted = SessionWithSets(
        const LiftSession(exerciseId: 1, date: '2026-07-01'),
        [_set(weight: 0, reps: 10)],
      );
      const bodyweightLb = 160.0;
      final assistedE1rm = assisted.bodyweightAdjustedBestE1rm(bodyweightLb);
      final unassistedE1rm = unassisted.bodyweightAdjustedBestE1rm(bodyweightLb);
      expect(assistedE1rm, greaterThan(0));
      expect(assistedE1rm, lessThan(unassistedE1rm));
    });

    test('weighted (positive added load) beats plain bodyweight at the same reps', () {
      const bodyweightLb = 160.0;
      final weighted = SessionWithSets(
        const LiftSession(exerciseId: 1, date: '2026-07-01'),
        [_set(weight: 25, reps: 8)],
      ).bodyweightAdjustedBestE1rm(bodyweightLb);
      final plain = SessionWithSets(
        const LiftSession(exerciseId: 1, date: '2026-07-01'),
        [_set(weight: 0, reps: 8)],
      ).bodyweightAdjustedBestE1rm(bodyweightLb);
      expect(weighted, greaterThan(plain));
    });
  });
}
