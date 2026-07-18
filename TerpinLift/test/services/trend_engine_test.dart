import 'package:flutter_test/flutter_test.dart';
import 'package:terpinlift/data/models/lift_session.dart';
import 'package:terpinlift/data/models/lift_set.dart';
import 'package:terpinlift/data/models/workout_plan.dart';
import 'package:terpinlift/data/repositories/lift_repository.dart';
import 'package:terpinlift/services/trend_engine.dart';
import 'package:terpinlift/services/user_profile.dart';

PlannedSession _plannedSession(
  String date, {
  required String startedAt,
  String? completedAt,
  PlannedSessionStatus status = PlannedSessionStatus.completed,
}) =>
    PlannedSession(
      templateDayId: 1,
      date: date,
      startedAt: startedAt,
      completedAt: completedAt,
      status: status,
    );

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
  group('TrendEngine.predictedOneRepMax', () {
    test('returns null with no sessions', () {
      expect(TrendEngine.predictedOneRepMax([]), isNull);
    });

    test('returns null when every session has zero sets', () {
      final sessions = [_session('2026-07-01', [])];
      expect(TrendEngine.predictedOneRepMax(sessions), isNull);
    });

    test('a multi-rep set projects lower for female than male (flatter divisor)', () {
      final sessions = [_session('2026-07-05', [_set(weight: 100, reps: 4)])];
      final female = TrendEngine.predictedOneRepMax(sessions, gender: Gender.female);
      final male = TrendEngine.predictedOneRepMax(sessions, gender: Gender.male);
      expect(female, lessThan(male!));
    });

    test('a true 1-rep set is unaffected by gender — no rep-conversion to scale', () {
      final sessions = [_session('2026-07-05', [_set(weight: 100, reps: 1)])];
      final female = TrendEngine.predictedOneRepMax(sessions, gender: Gender.female);
      final male = TrendEngine.predictedOneRepMax(sessions, gender: Gender.male);
      expect(female, closeTo(male!, 0.001));
    });

    test('no time decay — an old single session is used at full value, not tapered', () {
      final sessions = [_session('2020-01-01', [_set(weight: 200, reps: 1)])];
      expect(TrendEngine.predictedOneRepMax(sessions), 200);
    });

    test('takes the best of the last 3 sessions, not just the single most recent', () {
      final sessions = [
        _session('2026-07-05', [_set(weight: 100, reps: 1)]), // light/off day, most recent
        _session('2026-07-03', [_set(weight: 205, reps: 1)]), // the real recent best
        _session('2026-07-01', [_set(weight: 200, reps: 1)]),
      ];
      expect(TrendEngine.predictedOneRepMax(sessions), 205);
    });
  });

  group('TrendEngine.predictNextAtCharacteristicReps', () {
    test('returns null with no sessions', () {
      expect(TrendEngine.predictNextAtCharacteristicReps([]), isNull);
    });

    test('returns null when every session has zero sets', () {
      final sessions = [_session('2026-07-01', [])];
      expect(TrendEngine.predictNextAtCharacteristicReps(sessions), isNull);
    });

    test('a single data point: goal equals that weight, at the widest confidence band', () {
      final sessions = [_session('2026-07-05', [_set(weight: 100, reps: 4)])];
      final result = TrendEngine.predictNextAtCharacteristicReps(sessions)!;
      expect(result.reps, 4);
      expect(result.goal, 100);
      expect(result.high - result.low, closeTo(80.0, 0.001)); // +/-40 ceiling at n=1
      expect(result.sampleSize, 1);
    });

    test('projects the next weight as last + average recent delta at the same rep count', () {
      final sessions = [
        _session('2026-07-05', [_set(weight: 100, reps: 4)]),
        _session('2026-07-03', [_set(weight: 95, reps: 4)]),
        _session('2026-07-01', [_set(weight: 90, reps: 4)]),
      ];
      final result = TrendEngine.predictNextAtCharacteristicReps(sessions)!;
      expect(result.reps, 4);
      expect(result.goal, closeTo(105.0, 0.001)); // 100 + avg(5, 5)
      expect(result.sampleSize, 3);
    });

    test('characteristic reps is the mode of each session\'s heaviest-set rep count, and only '
        'matching sets feed the projection', () {
      final sessions = [
        // Most recent session's heaviest set is 8 reps — doesn't match the
        // mode (4), so it's skipped for the same-rep history entirely.
        _session('2026-07-05', [_set(weight: 60, reps: 8)]),
        _session('2026-07-03', [_set(weight: 100, reps: 4)]),
        _session('2026-07-01', [_set(weight: 95, reps: 4)]),
      ];
      final result = TrendEngine.predictNextAtCharacteristicReps(sessions)!;
      expect(result.reps, 4);
      expect(result.goal, closeTo(105.0, 0.001)); // 100 (most recent 4-rep entry) + 5
      expect(result.sampleSize, 2);
    });

    test('confidence band narrows as same-rep history accumulates', () {
      final sparse = [_session('2026-07-05', [_set(weight: 100, reps: 4)])];
      final rich = [
        for (var i = 0; i < 16; i++)
          _session('2026-0${1 + i ~/ 28}-${1 + i % 28}', [_set(weight: 100, reps: 4)]),
      ];
      final sparseBand = TrendEngine.predictNextAtCharacteristicReps(sparse)!;
      final richBand = TrendEngine.predictNextAtCharacteristicReps(rich)!;
      expect(sparseBand.high - sparseBand.low, greaterThan(richBand.high - richBand.low));
      expect(richBand.high - richBand.low, closeTo(20.0, 0.001)); // 2 * (40/sqrt(16))
    });

    test('a bodyweight-adjusted loadOf selector is honored', () {
      final sessions = [
        _session('2026-07-05', [_set(weight: 5, reps: 8)]),
        _session('2026-07-03', [_set(weight: 0, reps: 8)]),
      ];
      const bodyweightLb = 150.0;
      double loadOf(LiftSet s) => bodyweightLb + s.weight;
      final result = TrendEngine.predictNextAtCharacteristicReps(sessions, loadOf: loadOf)!;
      expect(result.reps, 8);
      expect(result.goal, greaterThan(100)); // in the bodyweight-plus-a-little range, not ~5
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

    test(
        'a completed planned session overrides the lift-session sum for its date, '
        'not adds to it', () {
      final sessions = [
        _timedSession(
          '2026-07-10',
          startedAt: '2026-07-10T18:00:00',
          completedAt: '2026-07-10T18:15:00', // a quick data-entry window, not the real length
        ),
      ];
      final plannedSessions = [
        _plannedSession(
          '2026-07-10',
          startedAt: '2026-07-10T19:00:00',
          completedAt: '2026-07-10T20:30:00', // the real 90-minute workout
        ),
      ];
      final result = TrendEngine.workoutDurationMinutesByDate(
        sessions,
        plannedSessions: plannedSessions,
      );
      expect(result['2026-07-10'], 90);
    });

    test('an active (not yet completed) planned session is ignored', () {
      final plannedSessions = [
        _plannedSession(
          '2026-07-10',
          startedAt: '2026-07-10T19:00:00',
          status: PlannedSessionStatus.active,
        ),
      ];
      final result = TrendEngine.workoutDurationMinutesByDate(
        [],
        plannedSessions: plannedSessions,
      );
      expect(result, isEmpty);
    });

    test('a date with no planned session still falls back to the lift-session sum', () {
      final sessions = [
        _timedSession(
          '2026-07-11',
          startedAt: '2026-07-11T10:00:00',
          completedAt: '2026-07-11T10:20:00',
        ),
      ];
      final plannedSessions = [
        _plannedSession(
          '2026-07-10',
          startedAt: '2026-07-10T19:00:00',
          completedAt: '2026-07-10T20:30:00',
        ),
      ];
      final result = TrendEngine.workoutDurationMinutesByDate(
        sessions,
        plannedSessions: plannedSessions,
      );
      expect(result['2026-07-11'], 20);
      expect(result['2026-07-10'], 90);
    });
  });
}
