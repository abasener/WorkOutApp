import '../database.dart';
import '../models/workout_plan.dart';

class WorkoutPlanRepository {
  final DatabaseHelper _db;
  WorkoutPlanRepository(this._db);

  Future<WorkoutTemplate?> getDefaultTemplate() async {
    final rows = await (await _db.database)
        .query('workout_templates', where: 'is_default = 1', limit: 1);
    if (rows.isEmpty) return null;
    return WorkoutTemplate.fromMap(rows.first);
  }

  Future<List<WorkoutTemplateDay>> getDaysForTemplate(int templateId) async {
    final rows = await (await _db.database).query(
      'workout_template_days',
      where: 'template_id = ?',
      whereArgs: [templateId],
      orderBy: 'day_order ASC',
    );
    return rows.map(WorkoutTemplateDay.fromMap).toList();
  }

  /// Every day across every template — used by the Workouts tab, which
  /// needs to resolve `planned_sessions.template_day_id` to a label/pattern
  /// list without knowing which template each one belongs to up front.
  Future<Map<int, WorkoutTemplateDay>> getAllDaysById() async {
    final rows = await (await _db.database).query('workout_template_days');
    return {
      for (final row in rows.map(WorkoutTemplateDay.fromMap))
        if (row.id != null) row.id!: row,
    };
  }

  Future<WorkoutTemplateDay?> getDay(int id) async {
    final rows =
        await (await _db.database).query('workout_template_days', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    return WorkoutTemplateDay.fromMap(rows.first);
  }

  /// Most recent **completed** `planned_sessions` row for each day — the
  /// recency cue on Day Select. Deliberately excludes `active`/`aborted`
  /// rows, not just `aborted` — `DaySelectScreen._selectDay` creates an
  /// `active` row the instant a day is tapped, before any workout actually
  /// happens, so a day merely glanced at and then backed out of (phone back
  /// button, not the explicit Abort button) used to read as "done today"
  /// even though nothing was logged. This should reflect "if/when the plan
  /// was actually run," the same completion-based standard the Workouts
  /// tab already uses. One query, grouped client-side since sqflite doesn't
  /// do "latest per group" cleanly without a subquery.
  Future<Map<int, PlannedSession>> latestSessionPerDay() async {
    final rows = await (await _db.database).query(
      'planned_sessions',
      where: 'status = ?',
      whereArgs: [PlannedSessionStatus.completed.key],
      orderBy: 'started_at DESC',
    );
    final sessions = rows.map(PlannedSession.fromMap).toList();
    final result = <int, PlannedSession>{};
    for (final s in sessions) {
      result.putIfAbsent(s.templateDayId, () => s);
    }
    return result;
  }

  /// Every non-aborted `planned_sessions` row — the basis for the Workouts
  /// tab's day-name grouping (`03_SCREEN_lifts.md`). Aborted sessions are
  /// excluded since aborting is meant to discard the session marker
  /// entirely, not leave a visible (if empty) trace.
  Future<List<PlannedSession>> getAllSessions() async {
    final rows = await (await _db.database).query(
      'planned_sessions',
      where: 'status != ?',
      whereArgs: [PlannedSessionStatus.aborted.key],
      orderBy: 'started_at ASC',
    );
    return rows.map(PlannedSession.fromMap).toList();
  }

  /// Removes the session/day association only — the underlying logged
  /// lifts are never touched, they just stop being grouped under a day.
  Future<void> deleteSession(int id) async =>
      (await _db.database).delete('planned_sessions', where: 'id = ?', whereArgs: [id]);

  /// Wipes every `planned_sessions` row — used only by `TestDataService`
  /// when reloading demo data, so old synthetic sessions don't linger
  /// alongside the fresh batch (`wipeEverythingAndReseed` doesn't touch this
  /// table, since a real user's Workout Planner history shouldn't be
  /// silently cleared by loading test data).
  Future<void> deleteAllSessions() async =>
      (await _db.database).delete('planned_sessions');

  Future<PlannedSession?> getActiveSession() async {
    final rows = await (await _db.database).query(
      'planned_sessions',
      where: 'status = ?',
      whereArgs: [PlannedSessionStatus.active.key],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return PlannedSession.fromMap(rows.first);
  }

  /// Low-level insert of a fully-formed [PlannedSession] (any status, any
  /// timestamps) — unlike [startSession], which always stamps "now." Used
  /// by `TestDataService` to backdate synthetic completed sessions across
  /// the demo window; not meant for the real app flow.
  Future<int> insertSession(PlannedSession session) async =>
      (await _db.database).insert('planned_sessions', session.toMap());

  Future<PlannedSession> startSession(int templateDayId) async {
    final now = DateTime.now();
    final session = PlannedSession(
      templateDayId: templateDayId,
      date: now.toIso8601String().substring(0, 10),
      startedAt: now.toIso8601String(),
      status: PlannedSessionStatus.active,
    );
    final id = await (await _db.database).insert('planned_sessions', session.toMap());
    return PlannedSession(
      id: id,
      templateDayId: session.templateDayId,
      date: session.date,
      startedAt: session.startedAt,
      status: session.status,
    );
  }

  Future<void> updateSession(PlannedSession session) async =>
      (await _db.database).update(
        'planned_sessions',
        session.toMap(),
        where: 'id = ?',
        whereArgs: [session.id],
      );

  Future<void> completeSession(int id) async {
    final now = DateTime.now().toIso8601String();
    await (await _db.database).update(
      'planned_sessions',
      {'status': PlannedSessionStatus.completed.key, 'completed_at': now},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> abortSession(int id) async {
    final now = DateTime.now().toIso8601String();
    await (await _db.database).update(
      'planned_sessions',
      {'status': PlannedSessionStatus.aborted.key, 'completed_at': now},
      where: 'id = ?',
      whereArgs: [id],
    );
  }
}
