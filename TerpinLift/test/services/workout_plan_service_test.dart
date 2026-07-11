import 'package:flutter_test/flutter_test.dart';
import 'package:terpinlift/data/models/exercise.dart';
import 'package:terpinlift/data/models/lift_session.dart';
import 'package:terpinlift/data/models/workout_plan.dart';
import 'package:terpinlift/data/repositories/lift_repository.dart';
import 'package:terpinlift/services/workout_plan_service.dart';

Exercise _exercise(int id, String name, List<MovementPattern> patterns) => Exercise(
      id: id,
      name: name,
      categories: const [],
      patterns: patterns,
      isSeeded: true,
      created: '2026-01-01',
    );

int _nextSessionId = 1;
SessionWithSets _session(int exerciseId, String date) => SessionWithSets(
      LiftSession(id: _nextSessionId++, exerciseId: exerciseId, date: date),
      [],
    );

WorkoutTemplateDay _day(int id, List<MovementPattern> patterns) => WorkoutTemplateDay(
      id: id,
      templateId: 1,
      dayOrder: 0,
      dayLabel: 'Day',
      patterns: patterns,
    );

PlannedSession _planned(int templateDayId, String date, String startedAt) => PlannedSession(
      id: templateDayId * 100,
      templateDayId: templateDayId,
      date: date,
      startedAt: startedAt,
      status: PlannedSessionStatus.completed,
    );

void main() {
  group('WorkoutPlanService.matchedSessions', () {
    test('matches a session logged the same day whose exercise carries the pattern', () {
      final squat = _exercise(1, 'Back Squat', [MovementPattern.squat]);
      final sessions = [_session(1, '2026-07-10')];
      final matches = WorkoutPlanService.matchedSessions(
          '2026-07-10', MovementPattern.squat, sessions, {1: squat});
      expect(matches, hasLength(1));
    });

    test('ignores a session on a different date', () {
      final squat = _exercise(1, 'Back Squat', [MovementPattern.squat]);
      final sessions = [_session(1, '2026-07-09')];
      final matches = WorkoutPlanService.matchedSessions(
          '2026-07-10', MovementPattern.squat, sessions, {1: squat});
      expect(matches, isEmpty);
    });

    test('ignores a same-day session whose exercise does not carry the pattern', () {
      final bench = _exercise(2, 'Bench Press', [MovementPattern.horizontalPush]);
      final sessions = [_session(2, '2026-07-10')];
      final matches = WorkoutPlanService.matchedSessions(
          '2026-07-10', MovementPattern.squat, sessions, {2: bench});
      expect(matches, isEmpty);
    });

    test('one exercise with two patterns satisfies both pattern queries', () {
      final cleanAndJerk =
          _exercise(3, 'Clean and Jerk', [MovementPattern.hinge, MovementPattern.verticalPush]);
      final sessions = [_session(3, '2026-07-10')];
      final byId = {3: cleanAndJerk};
      expect(
          WorkoutPlanService.matchedSessions('2026-07-10', MovementPattern.hinge, sessions, byId),
          hasLength(1));
      expect(
          WorkoutPlanService.matchedSessions(
              '2026-07-10', MovementPattern.verticalPush, sessions, byId),
          hasLength(1));
    });

    test('two exercises can both satisfy the same slot', () {
      final backSquat = _exercise(1, 'Back Squat', [MovementPattern.squat]);
      final frontSquat = _exercise(4, 'Front Squat', [MovementPattern.squat]);
      final sessions = [_session(1, '2026-07-10'), _session(4, '2026-07-10')];
      final matches = WorkoutPlanService.matchedSessions(
          '2026-07-10', MovementPattern.squat, sessions, {1: backSquat, 4: frontSquat});
      expect(matches, hasLength(2));
    });
  });

  group('WorkoutPlanService.progressFraction', () {
    test('0 patterns is defined as 0, not a division error', () {
      expect(WorkoutPlanService.progressFraction('2026-07-10', [], [], {}), 0);
    });

    test('counts a pattern as done if it has at least one match, regardless of how many', () {
      final squat = _exercise(1, 'Back Squat', [MovementPattern.squat]);
      final sessions = [_session(1, '2026-07-10'), _session(1, '2026-07-10')];
      final fraction = WorkoutPlanService.progressFraction(
        '2026-07-10',
        [MovementPattern.squat, MovementPattern.hinge],
        sessions,
        {1: squat},
      );
      expect(fraction, 0.5); // squat done, hinge not
    });
  });

  group('WorkoutPlanService.assignToSessions', () {
    test('a lift matching no planned day stays unassigned', () {
      final bench = _exercise(2, 'Bench Press', [MovementPattern.horizontalPush]);
      final squatDay = _day(10, [MovementPattern.squat]);
      final planned = _planned(10, '2026-07-10', '2026-07-10T08:00:00');
      final liftSession = _session(2, '2026-07-10');
      final result = WorkoutPlanService.assignToSessions(
        [liftSession],
        [planned],
        {10: squatDay},
        {2: bench},
      );
      expect(result, isEmpty);
    });

    test('a matching lift is assigned to the planned session for its date', () {
      final squat = _exercise(1, 'Back Squat', [MovementPattern.squat]);
      final squatDay = _day(10, [MovementPattern.squat]);
      final planned = _planned(10, '2026-07-10', '2026-07-10T08:00:00');
      final liftSession = _session(1, '2026-07-10');
      final result = WorkoutPlanService.assignToSessions(
        [liftSession],
        [planned],
        {10: squatDay},
        {1: squat},
      );
      expect(result[liftSession.session.id], planned);
    });

    test('with two same-day planned sessions, a lift assigns to the earlier-started one',
        () {
      final squat = _exercise(1, 'Back Squat', [MovementPattern.squat]);
      final squatDay = _day(10, [MovementPattern.squat]);
      final alsoSquatDay = _day(11, [MovementPattern.squat]);
      final earlier = _planned(10, '2026-07-10', '2026-07-10T07:00:00');
      final later = _planned(11, '2026-07-10', '2026-07-10T18:00:00');
      final liftSession = _session(1, '2026-07-10');
      final result = WorkoutPlanService.assignToSessions(
        [liftSession],
        [later, earlier], // deliberately out of order
        {10: squatDay, 11: alsoSquatDay},
        {1: squat},
      );
      expect(result[liftSession.session.id], earlier);
    });
  });
}
