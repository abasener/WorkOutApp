import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

class DatabaseHelper {
  static const _kDbVersion = 3;

  Database? _db;
  Future<Database> get database async => _db ??= await _open();

  Future<Database> _open() async {
    final dir = await getApplicationDocumentsDirectory();
    final path = join(dir.path, 'terpinlift.db');
    return openDatabase(
      path,
      version: _kDbVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
      onOpen: (db) => db.execute('PRAGMA foreign_keys = ON'),
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE exercises (
        id          INTEGER PRIMARY KEY AUTOINCREMENT,
        name        TEXT    NOT NULL,
        category    TEXT    NOT NULL,
        is_seeded   INTEGER NOT NULL DEFAULT 0,
        youtube_url TEXT,
        created     TEXT    NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE lift_sessions (
        id           INTEGER PRIMARY KEY AUTOINCREMENT,
        exercise_id  INTEGER NOT NULL,
        date         TEXT    NOT NULL,
        started_at   TEXT,
        completed_at TEXT,
        notes        TEXT,
        FOREIGN KEY (exercise_id) REFERENCES exercises (id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE lift_sets (
        id                INTEGER PRIMARY KEY AUTOINCREMENT,
        session_id        INTEGER NOT NULL,
        set_number        INTEGER NOT NULL,
        reps              INTEGER NOT NULL,
        weight            REAL    NOT NULL,
        rpe               REAL,
        set_started_at    TEXT,
        set_completed_at  TEXT,
        FOREIGN KEY (session_id) REFERENCES lift_sessions (id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE bodyweight_log (
        id     INTEGER PRIMARY KEY AUTOINCREMENT,
        date   TEXT NOT NULL,
        weight REAL NOT NULL
      )
    ''');

    // logged_at: precise ISO datetime of entry, alongside the day-granularity
    // `date` — lets multiple same-day entries (e.g. soreness logged more than
    // once) be distinguished/ordered.
    await db.execute('''
      CREATE TABLE metrics_log (
        id          INTEGER PRIMARY KEY AUTOINCREMENT,
        date        TEXT    NOT NULL,
        metric_type TEXT    NOT NULL,
        value       REAL    NOT NULL,
        logged_at   TEXT,
        notes       TEXT
      )
    ''');

    // entry_type: 'flow' (daily period-flow score 0-4, one row per date) or
    // 'symptom' (free note, not tied to a flow score).
    await db.execute('''
      CREATE TABLE cycle_log (
        id          INTEGER PRIMARY KEY AUTOINCREMENT,
        date        TEXT    NOT NULL,
        entry_type  TEXT    NOT NULL,
        flow_value  INTEGER,
        symptom_tag TEXT,
        notes       TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE app_settings (
        key   TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');

    await _seedDefaults(db);
  }

  Future<void> _onUpgrade(Database db, int oldV, int newV) async {
    for (var v = oldV + 1; v <= newV; v++) {
      await _migrate(db, v);
    }
  }

  Future<void> _migrate(Database db, int toVersion) async {
    switch (toVersion) {
      case 2:
        await db.execute('ALTER TABLE cycle_log ADD COLUMN flow_value INTEGER');
        await db.execute('''
          CREATE TABLE app_settings (
            key   TEXT PRIMARY KEY,
            value TEXT NOT NULL
          )
        ''');
      case 3:
        await db.execute('ALTER TABLE metrics_log ADD COLUMN logged_at TEXT');
    }
  }

  Future<void> _seedDefaults(Database db) async {
    final today = DateTime.now().toIso8601String().substring(0, 10);
    const seeded = [
      {'name': 'Front Squat', 'categories': 'legs,push,core'},
      {'name': 'Back Squat', 'categories': 'legs,push'},
      {'name': 'Bench Press', 'categories': 'chest,push,arms'},
      {'name': 'Deadlift', 'categories': 'back,legs,pull'},
      {'name': 'Overhead Press', 'categories': 'push,arms,core'},
    ];
    for (final e in seeded) {
      await db.insert('exercises', {
        'name': e['name'],
        'category': e['categories'],
        'is_seeded': 1,
        'youtube_url': null,
        'created': today,
      });
    }
  }

  /// Clears all logged entries (sets, sessions, bodyweight, metrics, cycle)
  /// but leaves the exercise list (seeded + custom) and settings untouched —
  /// this is "wipe my data," not "reset my app setup."
  Future<void> wipeLoggedData() async {
    final db = await database;
    await db.delete('lift_sets');
    await db.delete('lift_sessions');
    await db.delete('bodyweight_log');
    await db.delete('metrics_log');
    await db.delete('cycle_log');
  }

  /// Full reset used before loading synthetic test data: clears everything
  /// including exercises, then reseeds just the 5 default lifts so test-data
  /// generation has a known, deterministic exercise list to work from.
  /// Settings (e.g. unit preference) are left alone.
  Future<void> wipeEverythingAndReseed() async {
    final db = await database;
    await db.delete('lift_sets');
    await db.delete('lift_sessions');
    await db.delete('bodyweight_log');
    await db.delete('metrics_log');
    await db.delete('cycle_log');
    await db.delete('exercises');
    await _seedDefaults(db);
  }
}
