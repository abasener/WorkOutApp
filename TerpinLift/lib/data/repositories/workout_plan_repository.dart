import '../database.dart';
import '../models/workout_plan.dart';

class WorkoutPlanRepository {
  final DatabaseHelper _db;
  WorkoutPlanRepository(this._db);

  Future<WorkoutTemplate?> getDefaultTemplate() async {
    final rows = await (await _db.database).query(
      'workout_templates',
      where: 'is_default = 1',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return WorkoutTemplate.fromMap(rows.first);
  }

  Future<WorkoutTemplate?> getTemplate(int id) async {
    final rows = await (await _db.database).query(
      'workout_templates',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return WorkoutTemplate.fromMap(rows.first);
  }

  /// Every saved template — the list a "Switch plan" picker shows.
  Future<List<WorkoutTemplate>> getAllTemplates() async {
    final rows = await (await _db.database).query(
      'workout_templates',
      orderBy: 'name ASC',
    );
    return rows.map(WorkoutTemplate.fromMap).toList();
  }

  Future<int> insertTemplate(WorkoutTemplate template) async =>
      (await _db.database).insert('workout_templates', template.toMap());

  Future<WorkoutTemplate?> getTemplateByName(String name) async {
    final rows = await (await _db.database).query(
      'workout_templates',
      where: 'name = ?',
      whereArgs: [name],
      limit: 1,
    );
    return rows.isEmpty ? null : WorkoutTemplate.fromMap(rows.first);
  }

  Future<List<WorkoutTemplateDay>> getDaysForTemplate(int templateId) async {
    final rows = await (await _db.database).query(
      'workout_template_days',
      where: 'template_id = ? AND active = 1',
      whereArgs: [templateId],
      orderBy: 'day_order ASC',
    );
    return rows.map(WorkoutTemplateDay.fromMap).toList();
  }

  Future<int> insertDay(WorkoutTemplateDay day) async =>
      (await _db.database).insert('workout_template_days', day.toMap());

  /// Applies an imported set of days to an existing template's days
  /// **without ever deleting a row `planned_sessions.template_day_id` might
  /// already reference** — see designFiles/10_WORKOUT_PLANNER.md "Replace
  /// on import must never delete a day history references." [newDays] is
  /// the imported file's day list, in order (its own `dayOrder`/`id` are
  /// ignored — only its position, label, and patterns matter).
  ///
  /// Matched by position: the Nth existing active day (ordered by
  /// `day_order`) is updated **in place** (same id, new label/patterns) to
  /// become the Nth imported day, so any history pointing at that id keeps
  /// resolving to the right slot list. If the import has more days than
  /// currently exist, the extra ones are inserted fresh. If the import has
  /// fewer, the existing days beyond that point are soft-hidden
  /// (`active = 0`, never deleted) rather than removed.
  Future<void> replaceTemplateDays(
    int templateId,
    List<WorkoutTemplateDay> newDays,
  ) async {
    final db = await _db.database;
    final existing = await getDaysForTemplate(templateId);
    await db.transaction((txn) async {
      for (var i = 0; i < newDays.length; i++) {
        final day = newDays[i];
        if (i < existing.length) {
          await txn.update(
            'workout_template_days',
            {
              'day_order': i,
              'day_label': day.dayLabel,
              'patterns': day.patterns.map((p) => p.name).join(','),
              'active': 1,
            },
            where: 'id = ?',
            whereArgs: [existing[i].id],
          );
        } else {
          await txn.insert('workout_template_days', {
            'template_id': templateId,
            'day_order': i,
            'day_label': day.dayLabel,
            'patterns': day.patterns.map((p) => p.name).join(','),
            'active': 1,
          });
        }
      }
      for (var i = newDays.length; i < existing.length; i++) {
        await txn.update(
          'workout_template_days',
          {'active': 0},
          where: 'id = ?',
          whereArgs: [existing[i].id],
        );
      }
    });
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
    final rows = await (await _db.database).query(
      'workout_template_days',
      where: 'id = ?',
      whereArgs: [id],
    );
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
  Future<void> deleteSession(int id) async => (await _db.database).delete(
    'planned_sessions',
    where: 'id = ?',
    whereArgs: [id],
  );

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
    final id = await (await _db.database).insert(
      'planned_sessions',
      session.toMap(),
    );
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
