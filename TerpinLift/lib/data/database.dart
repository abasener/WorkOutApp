import 'package:sqflite/sqflite.dart';

import 'profile_manager.dart';

class DatabaseHelper {
  static const _kDbVersion = 9;

  /// Which data set this instance reads/writes — see `ProfileManager`.
  /// `AppServices.switchProfile` swaps in a new `DatabaseHelper` rather than
  /// repointing this one, so it's fine for this to be set once at
  /// construction.
  final AppProfile profile;
  DatabaseHelper({this.profile = AppProfile.personal});

  /// The default Workout Template — the source PDF's "Example Week"
  /// exactly, seeded so Day-based session selection works out of the box
  /// without needing CSV import first (designFiles/10_WORKOUT_PLANNER.md
  /// phase 3). Day 5 encodes both `squat` and `hinge` since the PDF itself
  /// says "whichever undertrained" — both slots show, filling either (or
  /// neither) is fine, matching "no slot is required."
  static const _defaultTemplateDays = [
    {'label': 'Day 1', 'patterns': 'squat,adductorAbductor'},
    {'label': 'Day 2', 'patterns': 'horizontalPush,verticalPull,core'},
    {'label': 'Day 3', 'patterns': 'hinge,hamstringGlute'},
    {
      'label': 'Day 4',
      'patterns': 'verticalPush,horizontalPull,shoulderPrehab,armsAesthetic',
    },
    {'label': 'Day 5', 'patterns': 'squat,hinge,quadGlute'},
  ];

  /// The full seeded exercise list — the 7 original launch lifts plus a
  /// bulk round covering most of what a typical gym-goer encounters:
  /// compound barbell/dumbbell lifts (including jerks/snatch, even though
  /// the user's current gym doesn't allow them — reference data isn't
  /// gym-specific), single-joint free-weight accessories (tagged
  /// `isolation`, a separate `ExerciseType` from `compound`), bodyweight
  /// movements, common named machines/cables, and one cardio entry (rowing,
  /// tracked the same sets/reps/RPE way — reps = meters rowed). Deliberately
  /// NOT exhaustive down to modified variants (heel-elevated squat vs.
  /// squat, etc.) — one entry per commonly-named lift, per the user's call.
  /// Used by both `_seedDefaults` (fresh installs) and the version-5
  /// migration (existing installs, inserted only if not already present by
  /// name, so upgrading doesn't duplicate or touch real logged data). The
  /// original 7 carry `'pinned': true` so the pinned-only quick-log dropdown
  /// isn't empty by default — see the version-6 migration for how that's
  /// backfilled onto existing installs too.
  static const _seedExercises = [
    // --- Original 7 — pinned by default so the quick-log dropdown (which
    // now only lists pinned exercises) isn't empty on a fresh install.
    {
      'name': 'Front Squat',
      'categories': 'legs,push,core',
      'equipment': 'compound',
      'pinned': true,
      'patterns': 'squat',
    },
    {
      'name': 'Back Squat',
      'categories': 'legs,push',
      'equipment': 'compound',
      'pinned': true,
      'patterns': 'squat',
    },
    {
      'name': 'Bench Press',
      'categories': 'chest,push,arms',
      'equipment': 'compound',
      'pinned': true,
      'patterns': 'horizontalPush',
    },
    {
      'name': 'Deadlift',
      'categories': 'back,legs,pull',
      'equipment': 'compound',
      'pinned': true,
      'patterns': 'hinge',
    },
    {
      'name': 'Overhead Press',
      'categories': 'push,arms,core',
      'equipment': 'compound',
      'pinned': true,
      'patterns': 'verticalPush',
    },
    {
      'name': 'Pull Up',
      'categories': 'back,pull,arms',
      'equipment': 'bodyweight',
      'pinned': true,
      'patterns': 'verticalPull',
    },
    {
      'name': 'Push Up',
      'categories': 'chest,push,arms',
      'equipment': 'bodyweight',
      'pinned': true,
      'patterns': 'horizontalPush',
    },

    // --- Compound: barbell/dumbbell multi-joint ---
    {
      'name': 'Incline Bench Press',
      'categories': 'chest,push,arms',
      'equipment': 'compound',
      'patterns': 'horizontalPush',
    },
    {
      'name': 'Decline Bench Press',
      'categories': 'chest,push,arms',
      'equipment': 'compound',
      'patterns': 'horizontalPush',
    },
    {
      'name': 'Close-Grip Bench Press',
      'categories': 'chest,push,arms',
      'equipment': 'compound',
      'patterns': 'horizontalPush',
    },
    {
      'name': 'Dumbbell Bench Press',
      'categories': 'chest,push,arms',
      'equipment': 'compound',
      'patterns': 'horizontalPush',
    },
    {
      'name': 'Push Press',
      'categories': 'push,arms,legs,core',
      'equipment': 'compound',
      'patterns': 'verticalPush',
    },
    {
      'name': 'Dumbbell Shoulder Press',
      'categories': 'push,arms,core',
      'equipment': 'compound',
      'patterns': 'verticalPush',
    },
    {
      'name': 'Arnold Press',
      'categories': 'push,arms,core',
      'equipment': 'compound',
      'patterns': 'verticalPush',
    },
    {
      'name': 'Sumo Deadlift',
      'categories': 'back,legs,pull',
      'equipment': 'compound',
      'patterns': 'hinge',
    },
    {
      'name': 'Romanian Deadlift',
      'categories': 'back,legs,pull',
      'equipment': 'compound',
      'patterns': 'hinge,hamstringGlute',
    },
    {
      'name': 'Barbell Row',
      'categories': 'back,pull,arms',
      'equipment': 'compound',
      'patterns': 'horizontalPull',
    },
    {
      'name': 'Pendlay Row',
      'categories': 'back,pull,arms',
      'equipment': 'compound',
      'patterns': 'horizontalPull',
    },
    {
      'name': 'Dumbbell Row',
      'categories': 'back,pull,arms',
      'equipment': 'compound',
      'patterns': 'horizontalPull',
    },
    {
      'name': 'Power Clean',
      'categories': 'back,legs,pull,core',
      'equipment': 'compound',
      'patterns': 'hinge',
    },
    {
      'name': 'Clean and Jerk',
      'categories': 'back,legs,push,pull,core',
      'equipment': 'compound',
      'patterns': 'hinge,verticalPush',
    },
    {
      'name': 'Snatch',
      'categories': 'back,legs,pull,core',
      'equipment': 'compound',
      'patterns': 'hinge',
    },
    {
      'name': 'Split Jerk',
      'categories': 'push,legs,core',
      'equipment': 'compound',
      'patterns': 'verticalPush',
    },
    {
      'name': 'Push Jerk',
      'categories': 'push,legs,core',
      'equipment': 'compound',
      'patterns': 'verticalPush',
    },
    {
      'name': 'Hip Thrust',
      'categories': 'legs,core',
      'equipment': 'compound',
      'patterns': 'quadGlute',
    },
    {
      'name': 'Good Morning',
      'categories': 'back,legs,core',
      'equipment': 'compound',
      'patterns': 'hinge,hamstringGlute',
    },
    {
      'name': 'Bulgarian Split Squat',
      'categories': 'legs,core',
      'equipment': 'compound',
      'patterns': 'squat',
    },
    {'name': 'Walking Lunge', 'categories': 'legs,core', 'equipment': 'compound', 'patterns': 'squat'},
    {'name': 'Reverse Lunge', 'categories': 'legs,core', 'equipment': 'compound', 'patterns': 'squat'},
    {
      'name': 'Trap Bar Deadlift',
      'categories': 'back,legs,pull',
      'equipment': 'compound',
      'patterns': 'hinge',
    },
    {
      'name': 'Landmine Press',
      'categories': 'push,arms,core',
      'equipment': 'compound',
      'patterns': 'verticalPush',
    },

    // --- Isolation: single-joint free-weight accessories ---
    {
      'name': 'Barbell Curl',
      'categories': 'arms,pull',
      'equipment': 'isolation',
      'patterns': 'armsAesthetic',
    },
    {
      'name': 'Dumbbell Curl',
      'categories': 'arms,pull',
      'equipment': 'isolation',
      'patterns': 'armsAesthetic',
    },
    {
      'name': 'Hammer Curl',
      'categories': 'arms,pull',
      'equipment': 'isolation',
      'patterns': 'armsAesthetic',
    },
    {
      'name': 'Preacher Curl',
      'categories': 'arms,pull',
      'equipment': 'isolation',
      'patterns': 'armsAesthetic',
    },
    {
      'name': 'Skull Crushers',
      'categories': 'arms,push',
      'equipment': 'isolation',
      'patterns': 'armsAesthetic',
    },
    {
      'name': 'Overhead Triceps Extension',
      'categories': 'arms,push',
      'equipment': 'isolation',
      'patterns': 'armsAesthetic',
    },
    {
      'name': 'Lateral Raise',
      'categories': 'arms,push',
      'equipment': 'isolation',
      'patterns': 'armsAesthetic',
    },
    {
      'name': 'Front Raise',
      'categories': 'arms,push',
      'equipment': 'isolation',
      'patterns': 'armsAesthetic',
    },
    {
      'name': 'Rear Delt Fly',
      'categories': 'arms,back,pull',
      'equipment': 'isolation',
      'patterns': 'armsAesthetic',
    },
    {'name': 'Barbell Shrug', 'categories': 'back,arms', 'equipment': 'isolation'},
    {'name': 'Dumbbell Shrug', 'categories': 'back,arms', 'equipment': 'isolation'},
    {'name': 'Standing Calf Raise', 'categories': 'legs', 'equipment': 'isolation'},
    {'name': 'Seated Calf Raise', 'categories': 'legs', 'equipment': 'isolation'},
    {'name': 'Wrist Curl', 'categories': 'arms', 'equipment': 'isolation'},

    // --- Bodyweight ---
    {
      'name': 'Chin Up',
      'categories': 'back,pull,arms',
      'equipment': 'bodyweight',
      'patterns': 'verticalPull',
    },
    {'name': 'Dip', 'categories': 'chest,push,arms', 'equipment': 'bodyweight'},
    {'name': 'Sit Up', 'categories': 'core', 'equipment': 'bodyweight', 'patterns': 'core'},
    {'name': 'Crunch', 'categories': 'core', 'equipment': 'bodyweight', 'patterns': 'core'},
    {
      'name': 'Hanging Leg Raise',
      'categories': 'core',
      'equipment': 'bodyweight',
      'patterns': 'core',
    },

    // --- Machines / cables ---
    {
      'name': 'Lat Pulldown',
      'categories': 'back,pull,arms',
      'equipment': 'machine',
      'patterns': 'verticalPull',
    },
    {
      'name': 'Seated Cable Row',
      'categories': 'back,pull,arms',
      'equipment': 'machine',
      'patterns': 'horizontalPull',
    },
    {
      'name': 'T-Bar Row',
      'categories': 'back,pull,arms',
      'equipment': 'machine',
      'patterns': 'horizontalPull',
    },
    {
      'name': 'Face Pull',
      'categories': 'back,pull,arms',
      'equipment': 'machine',
      'patterns': 'shoulderPrehab',
    },
    {'name': 'Leg Press', 'categories': 'legs', 'equipment': 'machine', 'patterns': 'quadGlute'},
    {
      'name': 'Leg Extension',
      'categories': 'legs',
      'equipment': 'machine',
      'patterns': 'quadGlute',
    },
    {
      'name': 'Leg Curl',
      'categories': 'legs',
      'equipment': 'machine',
      'patterns': 'hamstringGlute',
    },
    {'name': 'Hack Squat', 'categories': 'legs,push', 'equipment': 'machine', 'patterns': 'squat'},
    {
      'name': 'Smith Machine Squat',
      'categories': 'legs,push',
      'equipment': 'machine',
      'patterns': 'squat',
    },
    {
      'name': 'Glute Ham Raise',
      'categories': 'legs,back',
      'equipment': 'machine',
      'patterns': 'hamstringGlute',
    },
    {
      'name': 'Hip Thrust Machine',
      'categories': 'legs,core',
      'equipment': 'machine',
      'patterns': 'quadGlute',
    },
    {
      'name': 'Hip Adduction Machine',
      'categories': 'legs',
      'equipment': 'machine',
      'patterns': 'adductorAbductor',
    },
    {
      'name': 'Hip Abduction Machine',
      'categories': 'legs',
      'equipment': 'machine',
      'patterns': 'adductorAbductor',
    },
    {'name': 'Seated Calf Raise Machine', 'categories': 'legs', 'equipment': 'machine'},
    {
      'name': 'Chest Press Machine',
      'categories': 'chest,push,arms',
      'equipment': 'machine',
      'patterns': 'horizontalPush',
    },
    {
      'name': 'Smith Machine Bench Press',
      'categories': 'chest,push,arms',
      'equipment': 'machine',
      'patterns': 'horizontalPush',
    },
    {
      'name': 'Pec Deck',
      'categories': 'chest,push',
      'equipment': 'machine',
      'patterns': 'horizontalPush',
    },
    {
      'name': 'Cable Fly',
      'categories': 'chest,push',
      'equipment': 'machine',
      'patterns': 'horizontalPush',
    },
    {
      'name': 'Shoulder Press Machine',
      'categories': 'push,arms',
      'equipment': 'machine',
      'patterns': 'verticalPush',
    },
    {
      'name': 'Cable Triceps Pushdown',
      'categories': 'arms,push',
      'equipment': 'machine',
      'patterns': 'armsAesthetic',
    },
    {
      'name': 'Cable Bicep Curl',
      'categories': 'arms,pull',
      'equipment': 'machine',
      'patterns': 'armsAesthetic',
    },
    {'name': 'Cable Woodchopper', 'categories': 'core', 'equipment': 'machine', 'patterns': 'core'},
    {
      'name': 'Cable Pull-Through',
      'categories': 'legs,core,pull',
      'equipment': 'machine',
      'patterns': 'hamstringGlute',
    },
    {
      'name': 'Pallof Press',
      'categories': 'core',
      'equipment': 'machine',
      'patterns': 'core',
    },
    {
      'name': 'Straight-Arm Cable Pulldown',
      'categories': 'back,pull,arms',
      'equipment': 'machine',
      'patterns': 'verticalPull',
    },
    {
      'name': 'Glute Bridge Machine',
      'categories': 'legs',
      'equipment': 'machine',
      'patterns': 'hamstringGlute',
    },

    // --- Cardio ---
    {
      'name': 'Rowing Machine',
      'categories': 'back,legs,core,pull',
      'equipment': 'cardio',
    },
  ];

  Database? _db;
  Future<Database> get database async => _db ??= await _open();

  /// Releases the underlying connection — called before switching profiles
  /// so the previous file isn't left open while a different one is in use.
  Future<void> close() async {
    final db = _db;
    _db = null;
    await db?.close();
  }

  Future<Database> _open() async {
    final path = await ProfileManager.dbPath(profile);
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
        id                INTEGER PRIMARY KEY AUTOINCREMENT,
        name              TEXT    NOT NULL,
        category          TEXT    NOT NULL,
        equipment_tags    TEXT,
        movement_patterns TEXT,
        is_seeded         INTEGER NOT NULL DEFAULT 0,
        youtube_url       TEXT,
        created           TEXT    NOT NULL,
        pinned            INTEGER NOT NULL DEFAULT 0
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

    // Workout Planner (designFiles/10_WORKOUT_PLANNER.md). No stored
    // per-slot completion table — a day's slots are read from
    // workout_template_days.patterns, and what's "done" for a slot is
    // derived live from lift_sessions on the same date, not written here.
    await db.execute('''
      CREATE TABLE workout_templates (
        id         INTEGER PRIMARY KEY AUTOINCREMENT,
        name       TEXT    NOT NULL,
        is_default INTEGER NOT NULL DEFAULT 0,
        created    TEXT    NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE workout_template_days (
        id          INTEGER PRIMARY KEY AUTOINCREMENT,
        template_id INTEGER NOT NULL,
        day_order   INTEGER NOT NULL,
        day_label   TEXT    NOT NULL,
        patterns    TEXT    NOT NULL,
        FOREIGN KEY (template_id) REFERENCES workout_templates (id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE planned_sessions (
        id             INTEGER PRIMARY KEY AUTOINCREMENT,
        template_day_id INTEGER NOT NULL,
        date           TEXT    NOT NULL,
        started_at     TEXT    NOT NULL,
        completed_at   TEXT,
        status         TEXT    NOT NULL,
        notes          TEXT,
        FOREIGN KEY (template_day_id) REFERENCES workout_template_days (id) ON DELETE CASCADE
      )
    ''');

    await _seedDefaults(db);
    await _seedDefaultWorkoutTemplate(db);
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
      case 4:
        await db.execute('ALTER TABLE exercises ADD COLUMN equipment_tags TEXT');
      case 5:
        // Backfills the bulk exercise-library round for installs that
        // already have real logged data (so it doesn't require wiping to
        // get the new lifts) — only inserts names not already present,
        // since a fresh install already got the full list via
        // `_seedDefaults` and this migration still runs once on top of that
        // if the DB was created at a version before 5.
        final existing = (await db.query('exercises', columns: ['name']))
            .map((r) => r['name'] as String)
            .toSet();
        final today = DateTime.now().toIso8601String().substring(0, 10);
        for (final e in _seedExercises) {
          if (existing.contains(e['name'])) continue;
          await db.insert('exercises', {
            'name': e['name'],
            'category': e['categories'],
            'equipment_tags': e['equipment'],
            'is_seeded': 1,
            'youtube_url': null,
            'created': today,
            'pinned': (e['pinned'] as bool? ?? false) ? 1 : 0,
          });
        }
      case 6:
        await db.execute(
            'ALTER TABLE exercises ADD COLUMN pinned INTEGER NOT NULL DEFAULT 0');
        // Pre-pin the original 7 for existing installs, matching the
        // fresh-install default — otherwise the new pinned-only quick-log
        // dropdown would come up empty for anyone upgrading.
        for (final e in _seedExercises) {
          if (e['pinned'] != true) continue;
          await db.update('exercises', {'pinned': 1}, where: 'name = ?', whereArgs: [e['name']]);
        }
      case 7:
        // Soreness sub-splitting (designFiles/05_SCREEN_metrics.md): the 5
        // broad soreness `MetricType`s were replaced with 14 finer
        // sub-regions. `MetricType.fromKey` has no fallback for an unknown
        // key, so any already-logged row under an old key would crash the
        // Days tab (and anything else that reads `metrics_log` broadly) the
        // next time it loaded — remap old rows to one representative
        // sub-region per old category (same mapping `TestDataService` uses
        // for synthetic data) rather than losing or crashing on real
        // history. Not anatomically precise for old entries (we don't know
        // which exact sub-region the user meant back then), but far better
        // than the alternative.
        const oldToNewSorenessKey = {
          'soreness_core': 'soreness_core_center',
          'soreness_back': 'soreness_upper_back',
          'soreness_arms': 'soreness_biceps',
          'soreness_legs': 'soreness_quads',
          // 'soreness_chest' is unchanged, no remap needed.
        };
        for (final entry in oldToNewSorenessKey.entries) {
          await db.update(
            'metrics_log',
            {'metric_type': entry.value},
            where: 'metric_type = ?',
            whereArgs: [entry.key],
          );
        }
      case 8:
        // Workout Planner phase 1 (designFiles/10_WORKOUT_PLANNER.md): adds
        // the movement_patterns tag column, backfills it onto existing
        // seeded exercises by name (same pattern as the v5/v6 backfills),
        // and inserts the handful of exercises newly added alongside this
        // round (Trap Bar Deadlift, Landmine Press, Cable Pull-Through,
        // Pallof Press, Straight-Arm Cable Pulldown, Glute Bridge Machine)
        // for anyone upgrading rather than starting fresh.
        await db.execute('ALTER TABLE exercises ADD COLUMN movement_patterns TEXT');
        final existingNames = (await db.query('exercises', columns: ['name']))
            .map((r) => r['name'] as String)
            .toSet();
        final todayV8 = DateTime.now().toIso8601String().substring(0, 10);
        for (final e in _seedExercises) {
          if (existingNames.contains(e['name'])) {
            final patterns = e['patterns'] as String?;
            if (patterns == null) continue;
            await db.update(
              'exercises',
              {'movement_patterns': patterns},
              where: 'name = ?',
              whereArgs: [e['name']],
            );
          } else {
            await db.insert('exercises', {
              'name': e['name'],
              'category': e['categories'],
              'equipment_tags': e['equipment'],
              'movement_patterns': e['patterns'],
              'is_seeded': 1,
              'youtube_url': null,
              'created': todayV8,
              'pinned': (e['pinned'] as bool? ?? false) ? 1 : 0,
            });
          }
        }
      case 9:
        // Workout Planner phase 2 (designFiles/10_WORKOUT_PLANNER.md): new
        // tables for templates/days/sessions, plus seeding the same default
        // template fresh installs get via _onCreate.
        await db.execute('''
          CREATE TABLE workout_templates (
            id         INTEGER PRIMARY KEY AUTOINCREMENT,
            name       TEXT    NOT NULL,
            is_default INTEGER NOT NULL DEFAULT 0,
            created    TEXT    NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE workout_template_days (
            id          INTEGER PRIMARY KEY AUTOINCREMENT,
            template_id INTEGER NOT NULL,
            day_order   INTEGER NOT NULL,
            day_label   TEXT    NOT NULL,
            patterns    TEXT    NOT NULL,
            FOREIGN KEY (template_id) REFERENCES workout_templates (id) ON DELETE CASCADE
          )
        ''');
        await db.execute('''
          CREATE TABLE planned_sessions (
            id             INTEGER PRIMARY KEY AUTOINCREMENT,
            template_day_id INTEGER NOT NULL,
            date           TEXT    NOT NULL,
            started_at     TEXT    NOT NULL,
            completed_at   TEXT,
            status         TEXT    NOT NULL,
            notes          TEXT,
            FOREIGN KEY (template_day_id) REFERENCES workout_template_days (id) ON DELETE CASCADE
          )
        ''');
        await _seedDefaultWorkoutTemplate(db);
    }
  }

  Future<void> _seedDefaultWorkoutTemplate(Database db) async {
    final today = DateTime.now().toIso8601String().substring(0, 10);
    final templateId = await db.insert('workout_templates', {
      'name': 'Rotating Full-Body',
      'is_default': 1,
      'created': today,
    });
    for (var i = 0; i < _defaultTemplateDays.length; i++) {
      final day = _defaultTemplateDays[i];
      await db.insert('workout_template_days', {
        'template_id': templateId,
        'day_order': i,
        'day_label': day['label'],
        'patterns': day['patterns'],
      });
    }
  }

  Future<void> _seedDefaults(Database db) async {
    final today = DateTime.now().toIso8601String().substring(0, 10);
    for (final e in _seedExercises) {
      await db.insert('exercises', {
        'name': e['name'],
        'category': e['categories'],
        'equipment_tags': e['equipment'],
        'movement_patterns': e['patterns'],
        'is_seeded': 1,
        'youtube_url': null,
        'created': today,
        'pinned': (e['pinned'] as bool? ?? false) ? 1 : 0,
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
  /// including exercises, then reseeds the full default exercise library so test-data
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
