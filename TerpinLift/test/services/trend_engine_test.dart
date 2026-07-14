import 'package:flutter_test/flutter_test.dart';
import 'package:terpinlift/data/models/lift_session.dart';
import 'package:terpinlift/data/models/lift_set.dart';
import 'package:terpinlift/data/repositories/lift_repository.dart';
import 'package:terpinlift/services/trend_engine.dart';

SessionWithSets _session(String date, List<LiftSet> sets) =>
    SessionWithSets(LiftSession(exerciseId: 1, date: date), sets);

SessionWithSets _timedSession(String date, {String? startedAt, String? completedAt}) =>
    SessionWithSets(
      LiftSession(
        exerciseId: 1,
        date: date,
        startedAt: startedAt,
        completedAt: completedAt,
      ),
      [],
    );

LiftSet _set({required double weight, int reps = 5, double? rpe}) => LiftSet(
      sessionId: 1,
      setNumber: 0,
      reps: reps,
      weight: weight,
      rpe: rpe,
    );

void main() {
  group('TrendEngine.predictNextE1rm', () {
    test('returns null with no sessions', () {
      expect(TrendEngine.predictNextE1rm([]), isNull);
    });

    test('returns null when every session has zero sets', () {
      final sessions = [_session('2026-07-01', [])];
      expect(TrendEngine.predictNextE1rm(sessions), isNull);
    });

    test('goal sits between last session and rolling average, within the fixed band', () {
      final sessions = [
        _session('2026-07-05', [_set(weight: 205, rpe: 8)]),
        _session('2026-07-03', [_set(weight: 200, rpe: 8)]),
        _session('2026-07-01', [_set(weight: 195, rpe: 8)]),
      ];
      final prediction = TrendEngine.predictNextE1rm(sessions);
      expect(prediction, isNotNull);
      final (low, goal, high) = prediction!;
      expect(high - low, closeTo(100.0, 0.001)); // default +/-50lb band
      // A clear upward trend (205 > prior average) earns the bigger +3%
      // overload step, so the goal lands a bit above the raw e1RMs, not
      // just an average of them.
      expect(goal, greaterThan(230));
      expect(goal, lessThan(260));
    });

    test('a slump (last session well below recent average) does not add an overload step', () {
      final slumping = [
        _session('2026-07-05', [_set(weight: 150, rpe: 7)]), // clear drop
        _session('2026-07-03', [_set(weight: 200, rpe: 8)]),
        _session('2026-07-01', [_set(weight: 200, rpe: 8)]),
      ];
      final climbing = [
        _session('2026-07-05', [_set(weight: 210, rpe: 8)]), // clear rise
        _session('2026-07-03', [_set(weight: 200, rpe: 8)]),
        _session('2026-07-01', [_set(weight: 200, rpe: 8)]),
      ];
      final slumpGoal = TrendEngine.predictNextE1rm(slumping)!.$2;
      final climbGoal = TrendEngine.predictNextE1rm(climbing)!.$2;
      // The climbing case should apply a bigger overload step than the
      // slumping case relative to each one's own blended e1RM — checked
      // indirectly by confirming the slump doesn't chase a new high.
      expect(slumpGoal, lessThan(200));
      expect(climbGoal, greaterThan(200));
    });

    test('low-RPE (recovery) sessions lean on the rolling average, not the last session alone',
        () {
      final sessions = [
        _session('2026-07-05', [_set(weight: 100, rpe: 3)]), // light/recovery day
        _session('2026-07-03', [_set(weight: 200, rpe: 8)]),
        _session('2026-07-01', [_set(weight: 200, rpe: 8)]),
      ];
      final goal = TrendEngine.predictNextE1rm(sessions)!.$2;
      // A 100lb recovery-day e1RM shouldn't drag the goal anywhere near 100
      // once low RPE correctly discounts it in favor of the 200 average.
      expect(goal, greaterThan(150));
    });

    test('custom valueOf selector and band are honored (bodyweight-lift path)', () {
      final sessions = [
        _session('2026-07-05', [_set(weight: 5, reps: 8, rpe: 8)]),
        _session('2026-07-03', [_set(weight: 0, reps: 6, rpe: 8)]),
      ];
      const bodyweightLb = 150.0;
      double valueOf(SessionWithSets s) => s.bodyweightAdjustedBestE1rm(bodyweightLb);
      final prediction = TrendEngine.predictNextE1rm(sessions, valueOf: valueOf, band: 10);
      expect(prediction, isNotNull);
      final (low, _, high) = prediction!;
      expect(high - low, closeTo(20.0, 0.001));
      // Should be in the neighborhood of bodyweight-plus-a-little, not the
      // near-zero/negative range plain (unweighted) e1RM would produce.
      expect(low, greaterThan(100));
    });
  });

  group('TrendEngine.workoutDurationMinutesByDate', () {
    test('a session missing either timestamp does not contribute', () {
      final sessions = [
        _timedSession('2026-07-10', startedAt: '2026-07-10T10:00:00'),
        _timedSession('2026-07-11', completedAt: '2026-07-11T10:30:00'),
      ];
      expect(TrendEngine.workoutDurationMinutesByDate(sessions), isEmpty);
    });

    test('computes minutes between started and completed', () {
      final sessions = [
        _timedSession(
          '2026-07-10',
          startedAt: '2026-07-10T10:00:00',
          completedAt: '2026-07-10T10:45:00',
        ),
      ];
      expect(TrendEngine.workoutDurationMinutesByDate(sessions)['2026-07-10'], 45);
    });

    test('multiple sessions on the same date sum together', () {
      final sessions = [
        _timedSession(
          '2026-07-10',
          startedAt: '2026-07-10T10:00:00',
          completedAt: '2026-07-10T10:20:00',
        ),
        _timedSession(
          '2026-07-10',
          startedAt: '2026-07-10T11:00:00',
          completedAt: '2026-07-10T11:15:00',
        ),
      ];
      expect(TrendEngine.workoutDurationMinutesByDate(sessions)['2026-07-10'], 35);
    });

    test('a non-positive duration (bad data/clock skew) is dropped, not treated as 0', () {
      final sessions = [
        _timedSession(
          '2026-07-10',
          startedAt: '2026-07-10T10:30:00',
          completedAt: '2026-07-10T10:00:00',
        ),
      ];
      expect(TrendEngine.workoutDurationMinutesByDate(sessions), isEmpty);
    });
  });
}
