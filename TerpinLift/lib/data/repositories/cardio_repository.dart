import 'package:sqflite/sqflite.dart';

import '../database.dart';
import '../models/cardio_entry.dart';
import '../models/cardio_session.dart';

/// A session with its entries attached — the common shape screens need.
/// Mirrors `SessionWithSets` in `lift_repository.dart`. Pace/distance
/// display always goes through `CardioUnits` together with the owning
/// exercise's `DistanceUnit` — this class only sums canonical numbers, it
/// has no unit context of its own.
class CardioSessionWithEntries {
  final CardioSession session;
  final List<CardioEntry> entries;
  const CardioSessionWithEntries(this.session, this.entries);

  double get totalDistanceCanonical =>
      entries.fold(0.0, (sum, e) => sum + (e.distanceCanonical ?? 0));

  int get totalDurationSeconds =>
      entries.fold(0, (sum, e) => sum + (e.durationSeconds ?? 0));

  double? get avgRpe {
    final rated = entries.where((e) => e.rpe != null).toList();
    if (rated.isEmpty) return null;
    return rated.fold<double>(0, (sum, e) => sum + e.rpe!) / rated.length;
  }

  /// Highest single `load` logged this session — used for trend-chart dot
  /// sizing (resistance/incline/ruck weight), same spirit as rep-count dot
  /// sizing on the lift trend chart. `null` if no entry logged one.
  double? get maxLoad {
    final loaded = entries.where((e) => e.load != null).map((e) => e.load!);
    return loaded.isEmpty ? null : loaded.reduce((a, b) => a > b ? a : b);
  }
}

class CardioRepository {
  final DatabaseHelper _db;
  CardioRepository(this._db);

  Future<int> insertSession(CardioSession session) async =>
      (await _db.database).insert('cardio_sessions', session.toMap());

  Future<void> updateSession(CardioSession session) async =>
      (await _db.database).update('cardio_sessions', session.toMap(),
          where: 'id = ?', whereArgs: [session.id]);

  Future<int> insertEntry(CardioEntry entry) async =>
      (await _db.database).insert('cardio_entries', entry.toMap());

  Future<void> deleteSession(int sessionId) async => (await _db.database)
      .delete('cardio_sessions', where: 'id = ?', whereArgs: [sessionId]);

  /// Replaces all entries for a session in one go — used when editing a
  /// logged session, simpler than diffing individual entry changes.
  Future<void> replaceEntries(int sessionId, List<CardioEntry> entries) async {
    final db = await _db.database;
    await db.delete('cardio_entries', where: 'session_id = ?', whereArgs: [sessionId]);
    for (var i = 0; i < entries.length; i++) {
      final e = entries[i];
      await db.insert(
        'cardio_entries',
        CardioEntry(
          sessionId: sessionId,
          entryNumber: i + 1,
          distanceCanonical: e.distanceCanonical,
          durationSeconds: e.durationSeconds,
          load: e.load,
          rpe: e.rpe,
        ).toMap(),
      );
    }
  }

  Future<List<CardioSessionWithEntries>> _querySessions(
    Database db, {
    String? where,
    List<Object?>? whereArgs,
  }) async {
    final sessionRows = await db.query(
      'cardio_sessions',
      where: where,
      whereArgs: whereArgs,
      orderBy: 'date DESC, id DESC',
    );
    final result = <CardioSessionWithEntries>[];
    for (final row in sessionRows) {
      final session = CardioSession.fromMap(row);
      final entryRows = await db.query(
        'cardio_entries',
        where: 'session_id = ?',
        whereArgs: [session.id],
        orderBy: 'entry_number ASC',
      );
      result.add(CardioSessionWithEntries(session, entryRows.map(CardioEntry.fromMap).toList()));
    }
    return result;
  }

  /// All sessions (with entries) for a given exercise, most recent first.
  Future<List<CardioSessionWithEntries>> getSessionsForExercise(int exerciseId) async {
    final db = await _db.database;
    return _querySessions(db, where: 'exercise_id = ?', whereArgs: [exerciseId]);
  }

  /// All cardio sessions across every exercise, most recent first.
  Future<List<CardioSessionWithEntries>> getAllSessions() async =>
      _querySessions(await _db.database);

  /// Convenience: log a full session in one call (session + its entries).
  Future<int> logSession({
    required int exerciseId,
    required String date,
    required List<CardioEntry> entries,
    String? notes,
  }) async {
    final sessionId = await insertSession(
      CardioSession(exerciseId: exerciseId, date: date, notes: notes),
    );
    for (var i = 0; i < entries.length; i++) {
      final e = entries[i];
      await insertEntry(CardioEntry(
        sessionId: sessionId,
        entryNumber: i + 1,
        distanceCanonical: e.distanceCanonical,
        durationSeconds: e.durationSeconds,
        load: e.load,
        rpe: e.rpe,
      ));
    }
    return sessionId;
  }

  /// Distinct dates with any logged cardio session — unioned with lift dates
  /// wherever "was there a workout that day" is asked (e.g. Home's week
  /// rings), so a cardio-only day still counts.
  Future<List<String>> getAllWorkoutDates() async {
    final rows = await (await _db.database)
        .query('cardio_sessions', columns: ['DISTINCT date as date'], orderBy: 'date DESC');
    return rows.map((r) => r['date'] as String).toList();
  }
}
