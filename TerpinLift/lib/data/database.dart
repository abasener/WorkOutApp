import 'package:sqflite/sqflite.dart';

import 'profile_manager.dart';

class DatabaseHelper {
  static const _kDbVersion = 27;

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
    {'label': 'Squat Focus', 'patterns': 'squat,adductorAbductor'},
    {'label': 'Push & Pull', 'patterns': 'horizontalPush,verticalPull,core'},
    {'label': 'Hinge Focus', 'patterns': 'hinge,hamstringGlute'},
    {
      'label': 'Overhead & Rows',
      'patterns': 'verticalPush,horizontalPull,shoulderPrehab,armsAesthetic',
    },
    {'label': 'Legs & Hips', 'patterns': 'squat,hinge,quadGlute'},
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
  /// name, so upgrading doesn't duplicate or touch real logged data).
  ///
  /// **Default pins (redone 2026-07-21):** Back Squat, Bench Press,
  /// Deadlift, Overhead Press, Pull Up, Push Up, Barbell Row, Run — one
  /// compound lift per major movement pattern (squat/hinge/horizontal
  /// push/vertical push/horizontal pull), the two original bodyweight
  /// staples, and one cardio exercise now that cardio/HIIT exist as their
  /// own tracked things — 8 total, so the pinned-only quick-log dropdown
  /// isn't empty by default without being cluttered. Front Squat dropped
  /// (redundant with Back Squat covering the same pattern). Just a
  /// starting point — every exercise's own pin toggle still works exactly
  /// the same, this only changes what a fresh install/demo reset starts
  /// with. Deliberately **not** retrofitted onto an already-existing
  /// install's current pins via a migration — that risks silently undoing
  /// pin changes someone already made on purpose; see the version-6
  /// migration (historical, already applied) for the one-time backfill
  /// that originally seeded the old 7-lift default onto pre-existing
  /// installs.
  static const _seedExercises = [
    // --- Original 7 (redone 2026-07-21 — see below) — pinned by default so
    // the quick-log dropdown (which only lists pinned exercises) isn't
    // empty on a fresh install.
    {
      'name': 'Front Squat',
      'categories': 'legs,push,core',
      'equipment': 'compound',
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
      'pinned': true,
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
    {
      'name': 'Walking Lunge',
      'categories': 'legs,core',
      'equipment': 'compound',
      'patterns': 'squat',
    },
    {
      'name': 'Reverse Lunge',
      'categories': 'legs,core',
      'equipment': 'compound',
      'patterns': 'squat',
    },
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
    {
      'name': 'Barbell Shrug',
      'categories': 'back,arms',
      'equipment': 'isolation',
    },
    {
      'name': 'Dumbbell Shrug',
      'categories': 'back,arms',
      'equipment': 'isolation',
    },
    {
      'name': 'Standing Calf Raise',
      'categories': 'legs',
      'equipment': 'isolation',
    },
    {
      'name': 'Seated Calf Raise',
      'categories': 'legs',
      'equipment': 'isolation',
    },
    {'name': 'Wrist Curl', 'categories': 'arms', 'equipment': 'isolation'},

    // --- Bodyweight ---
    {
      'name': 'Chin Up',
      'categories': 'back,pull,arms',
      'equipment': 'bodyweight',
      'patterns': 'verticalPull',
    },
    {'name': 'Dip', 'categories': 'chest,push,arms', 'equipment': 'bodyweight'},
    {
      'name': 'Sit Up',
      'categories': 'core',
      'equipment': 'bodyweight',
      'patterns': 'core',
    },
    {
      'name': 'Crunch',
      'categories': 'core',
      'equipment': 'bodyweight',
      'patterns': 'core',
    },
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
    {
      'name': 'Leg Press',
      'categories': 'legs',
      'equipment': 'machine',
      'patterns': 'quadGlute',
    },
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
    {
      'name': 'Hack Squat',
      'categories': 'legs,push',
      'equipment': 'machine',
      'patterns': 'squat',
    },
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
    {
      'name': 'Seated Calf Raise Machine',
      'categories': 'legs',
      'equipment': 'machine',
    },
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
    {
      'name': 'Cable Woodchopper',
      'categories': 'core',
      'equipment': 'machine',
      'patterns': 'core',
    },
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

    // --- Cardio ("light handling" — see designFiles/11_SCREEN_cardio.md;
    // these are logged through cardio_sessions/cardio_entries, not
    // lift_sessions/lift_sets, unlike Rowing Machine above them historically
    // was) ---
    {
      'name': 'Rowing Machine',
      'categories': 'back,legs,core,pull',
      'equipment': 'cardio',
      'cardio_unit': 'meters',
    },
    {
      'name': 'Run',
      'categories': 'legs,core',
      'equipment': 'cardio',
      'pinned': true,
      'cardio_unit': 'miles',
    },
    {
      'name': 'Ruck',
      'categories': 'legs,core,back',
      'equipment': 'cardio',
      'cardio_unit': 'miles',
    },
    {
      // Same shape as Ruck as far as the app knows — legs/core/back under
      // load, just carried differently. No separate muscle-map curation
      // needed either (Ruck has none, falls back to the category-based
      // `MuscleMap.broadGroups` mapping like every other uncurated cardio
      // exercise).
      'name': "Farmer's Carry",
      'categories': 'legs,core,back',
      'equipment': 'cardio',
      'cardio_unit': 'miles',
    },
    {
      'name': 'Bike',
      'categories': 'legs',
      'equipment': 'cardio',
      'cardio_unit': 'miles',
    },
    {
      'name': 'Stairs',
      'categories': 'legs',
      'equipment': 'cardio',
      'cardio_unit': 'floors',
    },
    {
      'name': 'General Cardio',
      'categories': '',
      'equipment': 'cardio',
      'cardio_unit': 'miles',
    },
    {
      'name': 'Other Cardio',
      'categories': '',
      'equipment': 'cardio',
      'cardio_unit': 'miles',
    },

    // --- Core, bodyweight (dynamic reps — isometric holds like planks are
    // deliberately excluded, see the v11 migration comment for why) ---
    {
      'name': 'Russian Twist',
      'categories': 'core',
      'equipment': 'bodyweight',
      'patterns': 'core',
    },
    {
      'name': 'Dead Bug',
      'categories': 'core',
      'equipment': 'bodyweight',
      'patterns': 'core',
    },
    {
      'name': 'Bicycle Crunch',
      'categories': 'core',
      'equipment': 'bodyweight',
      'patterns': 'core',
    },
    {
      'name': 'Flutter Kicks',
      'categories': 'core',
      'equipment': 'bodyweight',
      'patterns': 'core',
    },
    {
      'name': 'V-Up',
      'categories': 'core',
      'equipment': 'bodyweight',
      'patterns': 'core',
    },
    {
      'name': 'Leg Raise',
      'categories': 'core',
      'equipment': 'bodyweight',
      'patterns': 'core',
    },
    {
      'name': 'Bird Dog',
      'categories': 'core,back',
      'equipment': 'bodyweight',
      'patterns': 'core',
    },
    {
      'name': 'Superman',
      'categories': 'back,core',
      'equipment': 'bodyweight',
      'patterns': 'hamstringGlute',
    },

    // --- Machines added v11, cross-checked against the Precor Resolute/
    // Discovery selectorized+plate-loaded lineups (the user's gym equipment)
    // for coverage gaps ---
    {
      'name': 'Ab Crunch Machine',
      'categories': 'core',
      'equipment': 'machine',
      'patterns': 'core',
    },
    {
      'name': 'Back Extension Machine',
      'categories': 'back,legs',
      'equipment': 'machine',
      'patterns': 'hamstringGlute',
    },
    {
      'name': 'Rotary Torso Machine',
      'categories': 'core',
      'equipment': 'machine',
      'patterns': 'core',
    },
    {
      'name': 'Glute Extension Machine',
      'categories': 'legs',
      'equipment': 'machine',
      'patterns': 'hamstringGlute',
    },
    {
      'name': 'Bicep Curl Machine',
      'categories': 'arms,pull',
      'equipment': 'machine',
      'patterns': 'armsAesthetic',
    },
    {
      'name': 'Triceps Extension Machine',
      'categories': 'arms,push',
      'equipment': 'machine',
      'patterns': 'armsAesthetic',
    },
    {
      'name': 'Seated Dip Machine',
      'categories': 'chest,push,arms',
      'equipment': 'machine',
      'patterns': 'horizontalPush',
    },
    {
      'name': 'Low Row Machine',
      'categories': 'back,pull,arms',
      'equipment': 'machine',
      'patterns': 'horizontalPull',
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
        pinned            INTEGER NOT NULL DEFAULT 0,
        goal_source       TEXT,
        progress_metric   TEXT,
        notes             TEXT,
        target_muscles    TEXT,
        cardio_unit       TEXT
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
        notes       TEXT,
        time_slot   TEXT
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
        active      INTEGER NOT NULL DEFAULT 1,
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

    // User-set goals, a log per exercise (not one-per-exercise — the user
    // can keep multiple over time, like a lift log entry, each with its own
    // optional label so old goals stay visible/nameable rather than getting
    // overwritten) — the fallback/override for exercises with no published
    // strength standard (most machines/isolation work), and an opt-in
    // override even for exercises that *do* have one (Goal gauge,
    // designFiles/07_SMART_TRENDS.md). The most recent entry (by `created`)
    // is the one that actually drives the gauge; older ones are just
    // history. Exactly one of target_weight/target_reps is set per row,
    // matching whichever axis that exercise's Goal gauge already uses
    // (weight for normal lifts, reps for bodyweight ones) — enforced in
    // code, not a CHECK constraint, same style as the rest of this schema.
    await db.execute('''
      CREATE TABLE custom_goals (
        id             INTEGER PRIMARY KEY AUTOINCREMENT,
        exercise_id    INTEGER NOT NULL,
        label          TEXT,
        target_weight  REAL,
        target_reps    INTEGER,
        target_distance REAL,
        target_pace    REAL,
        created        TEXT    NOT NULL,
        FOREIGN KEY (exercise_id) REFERENCES exercises (id) ON DELETE CASCADE
      )
    ''');

    // Cardio (Ruck/Run/Bike/Rowing/Stairs/general — "light handling," not a
    // full cardio-training feature) gets its own session/entry pair rather
    // than being forced through lift_sessions/lift_sets' reps+weight shape —
    // see designFiles/11_SCREEN_cardio.md. Same session-then-entries shape
    // as lift_sessions/lift_sets; entry_number lets a session log more than
    // one effort (interval-style cardio) even though most days it's just one.
    await db.execute('''
      CREATE TABLE cardio_sessions (
        id          INTEGER PRIMARY KEY AUTOINCREMENT,
        exercise_id INTEGER NOT NULL,
        date        TEXT    NOT NULL,
        notes       TEXT,
        FOREIGN KEY (exercise_id) REFERENCES exercises (id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE cardio_entries (
        id                INTEGER PRIMARY KEY AUTOINCREMENT,
        session_id        INTEGER NOT NULL,
        entry_number      INTEGER NOT NULL,
        distance_canonical REAL,
        duration_seconds  INTEGER,
        load              REAL,
        rpe               REAL,
        entry_started_at  TEXT,
        entry_completed_at TEXT,
        FOREIGN KEY (session_id) REFERENCES cardio_sessions (id) ON DELETE CASCADE
      )
    ''');

    // Progress photos — a simple date-stamped log of image file paths (the
    // files themselves live in app storage, see `ProgressPhotoRepository`);
    // multiple per day is expected (different angles/poses), so no
    // uniqueness constraint on date.
    await db.execute('''
      CREATE TABLE progress_photos (
        id        INTEGER PRIMARY KEY AUTOINCREMENT,
        date      TEXT    NOT NULL,
        file_path TEXT    NOT NULL,
        taken_at  TEXT    NOT NULL
      )
    ''');

    // User-defined metrics (the "metric builder") — unlimited, each with a
    // `kind` deciding how its entries are captured/displayed:
    // - number: a plain value (e.g. temperature), `scale_max`/`scale_icon`/
    //   `class_labels` all null.
    // - scale: a 0-`scale_max` level (same shape as muscle soreness),
    //   `scale_icon` picks which icon set renders it (flame/star/dot).
    // - classes: a named-category value — `class_labels` is a comma-joined
    //   ordered list, and entries store the chosen label's index into it.
    await db.execute('''
      CREATE TABLE custom_metrics (
        id                   INTEGER PRIMARY KEY AUTOINCREMENT,
        name                 TEXT    NOT NULL,
        kind                 TEXT    NOT NULL,
        scale_max            INTEGER,
        scale_icon           TEXT,
        class_labels         TEXT,
        created              TEXT    NOT NULL,
        allow_multiple_per_day INTEGER NOT NULL DEFAULT 0,
        goal                 REAL,
        hide_value           INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.execute('''
      CREATE TABLE custom_metric_entries (
        id                INTEGER PRIMARY KEY AUTOINCREMENT,
        custom_metric_id  INTEGER NOT NULL,
        date              TEXT    NOT NULL,
        value             REAL    NOT NULL,
        logged_at         TEXT    NOT NULL,
        FOREIGN KEY (custom_metric_id) REFERENCES custom_metrics (id) ON DELETE CASCADE
      )
    ''');

    // Home's Checklist widget — a fixed, user-edited list of recurring
    // reminders ("bring water bottle," "log sleep") rather than a one-off
    // task list; `last_checked_date` is the whole daily-reset mechanism —
    // a row reads as "checked" only if that date is today, so there's no
    // background job needed to clear checkmarks overnight, it just falls
    // out of the comparison at render time.
    await db.execute('''
      CREATE TABLE todo_items (
        id                INTEGER PRIMARY KEY AUTOINCREMENT,
        text              TEXT    NOT NULL,
        time_of_day       TEXT,
        sort_order        INTEGER NOT NULL,
        last_checked_date TEXT
      )
    ''');

    // HIIT (designFiles/12_SCREEN_hiit.md) — a routine is a flat, strictly-
    // ordered sequence of `hiit_slots` (sequence_index), grouped into rounds
    // (group_index) purely for the progress bar's round markers and for
    // knowing where a round's rest goes. `hiit_sessions` also carries live
    // resume state (current_sequence_index/current_phase/phase_started_at/
    // phase_remaining_seconds/current_reps_remaining/paused) so leaving the
    // active-session screen (Pause, or just navigating away) and coming back
    // later through the Home widget picks up exactly where it left off.
    await db.execute('''
      CREATE TABLE hiit_sessions (
        id                      INTEGER PRIMARY KEY AUTOINCREMENT,
        date                    TEXT    NOT NULL,
        notes                   TEXT,
        started_at              TEXT    NOT NULL,
        completed_at            TEXT,
        status                  TEXT    NOT NULL,
        automatic               INTEGER NOT NULL DEFAULT 1,
        current_sequence_index  INTEGER NOT NULL DEFAULT 0,
        current_phase           TEXT    NOT NULL DEFAULT 'work',
        phase_started_at        TEXT,
        phase_remaining_seconds REAL,
        current_reps_remaining  INTEGER,
        paused                  INTEGER NOT NULL DEFAULT 0,
        total_paused_seconds    REAL    NOT NULL DEFAULT 0
      )
    ''');

    // No FK on exercise_id/lift_set_id/cardio_entry_id on purpose — a HIIT
    // slot references whatever exercise was picked at setup time, and the
    // set/entry it eventually produces is written well after the slot row
    // already exists (see `HiitService.saveSession`), so a strict FK would
    // just add ordering constraints with no real safety benefit here.
    await db.execute('''
      CREATE TABLE hiit_slots (
        id                  INTEGER PRIMARY KEY AUTOINCREMENT,
        hiit_session_id     INTEGER NOT NULL,
        sequence_index      INTEGER NOT NULL,
        group_index         INTEGER NOT NULL,
        exercise_id         INTEGER NOT NULL,
        exercise_kind       TEXT    NOT NULL,
        target_type         TEXT    NOT NULL,
        target_value        REAL,
        weight              REAL,
        rest_after_seconds  INTEGER,
        actual_reps         INTEGER,
        actual_weight       REAL,
        actual_time_seconds INTEGER,
        actual_distance     REAL,
        actual_load         REAL,
        lift_set_id         INTEGER,
        cardio_entry_id     INTEGER,
        FOREIGN KEY (hiit_session_id) REFERENCES hiit_sessions (id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE hiit_routines (
        id        INTEGER PRIMARY KEY AUTOINCREMENT,
        name      TEXT    NOT NULL,
        automatic INTEGER NOT NULL DEFAULT 0,
        created   TEXT    NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE hiit_routine_slots (
        id                 INTEGER PRIMARY KEY AUTOINCREMENT,
        hiit_routine_id    INTEGER NOT NULL,
        sequence_index     INTEGER NOT NULL,
        group_index        INTEGER NOT NULL,
        exercise_id        INTEGER NOT NULL,
        exercise_kind      TEXT    NOT NULL,
        target_type        TEXT    NOT NULL,
        target_value       REAL,
        weight             REAL,
        rest_after_seconds INTEGER,
        FOREIGN KEY (hiit_routine_id) REFERENCES hiit_routines (id) ON DELETE CASCADE
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
        await db.execute(
          'ALTER TABLE exercises ADD COLUMN equipment_tags TEXT',
        );
      case 5:
        // Backfills the bulk exercise-library round for installs that
        // already have real logged data (so it doesn't require wiping to
        // get the new lifts) — only inserts names not already present,
        // since a fresh install already got the full list via
        // `_seedDefaults` and this migration still runs once on top of that
        // if the DB was created at a version before 5.
        final existing = (await db.query(
          'exercises',
          columns: ['name'],
        )).map((r) => r['name'] as String).toSet();
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
          'ALTER TABLE exercises ADD COLUMN pinned INTEGER NOT NULL DEFAULT 0',
        );
        // Pre-pin the original 7 for existing installs, matching the
        // fresh-install default — otherwise the new pinned-only quick-log
        // dropdown would come up empty for anyone upgrading.
        for (final e in _seedExercises) {
          if (e['pinned'] != true) continue;
          await db.update(
            'exercises',
            {'pinned': 1},
            where: 'name = ?',
            whereArgs: [e['name']],
          );
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
        await db.execute(
          'ALTER TABLE exercises ADD COLUMN movement_patterns TEXT',
        );
        final existingNames = (await db.query(
          'exercises',
          columns: ['name'],
        )).map((r) => r['name'] as String).toSet();
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
      case 10:
        // Renames the seeded default template's "Day 1".."Day 5" labels to
        // pattern-descriptive names (designFiles/10_WORKOUT_PLANNER.md) —
        // "Day 3" reads as ambiguous once there's more than one day list on
        // screen, per on-device feedback. Only touches the one seeded
        // default template's days, matched by day_order, since the
        // template-builder UI (phase 3) that would let a user create their
        // own doesn't exist yet — nothing else to accidentally rename.
        final defaultTemplate = await db.query(
          'workout_templates',
          where: 'is_default = 1',
          limit: 1,
        );
        if (defaultTemplate.isNotEmpty) {
          final templateId = defaultTemplate.first['id'] as int;
          for (var i = 0; i < _defaultTemplateDays.length; i++) {
            await db.update(
              'workout_template_days',
              {'day_label': _defaultTemplateDays[i]['label']},
              where: 'template_id = ? AND day_order = ?',
              whereArgs: [templateId, i],
            );
          }
        }
      case 11:
        // Adds 8 more bodyweight core exercises (Russian Twist, Dead Bug,
        // Bicycle Crunch, Flutter Kicks, V-Up, Leg Raise, Bird Dog,
        // Superman — all dynamic-rep movements; isometric holds like planks
        // are deliberately excluded, since this app's data model is
        // reps/weight/RPE-shaped and doesn't have a good way to track a
        // held position yet) plus 8 machines cross-checked against the
        // user's actual gym equipment (Precor's Resolute/Discovery
        // selectorized+plate-loaded lineups): Ab Crunch Machine, Back
        // Extension Machine, Rotary Torso Machine, Glute Extension Machine,
        // Bicep Curl Machine, Triceps Extension Machine, Seated Dip
        // Machine, Low Row Machine. Insert-only-if-missing, same pattern as
        // the v5/v8 backfills — anyone already on this exercise list from a
        // fresh v11+ install isn't touched.
        final existingNamesV11 = (await db.query(
          'exercises',
          columns: ['name'],
        )).map((r) => r['name'] as String).toSet();
        final todayV11 = DateTime.now().toIso8601String().substring(0, 10);
        const newInV11 = {
          'Russian Twist',
          'Dead Bug',
          'Bicycle Crunch',
          'Flutter Kicks',
          'V-Up',
          'Leg Raise',
          'Bird Dog',
          'Superman',
          'Ab Crunch Machine',
          'Back Extension Machine',
          'Rotary Torso Machine',
          'Glute Extension Machine',
          'Bicep Curl Machine',
          'Triceps Extension Machine',
          'Seated Dip Machine',
          'Low Row Machine',
        };
        for (final e in _seedExercises) {
          if (!newInV11.contains(e['name']) ||
              existingNamesV11.contains(e['name'])) {
            continue;
          }
          await db.insert('exercises', {
            'name': e['name'],
            'category': e['categories'],
            'equipment_tags': e['equipment'],
            'movement_patterns': e['patterns'],
            'is_seeded': 1,
            'youtube_url': null,
            'created': todayV11,
            'pinned': 0,
          });
        }
      case 12:
        // Custom per-exercise goals + a per-exercise Goal-source/progress-
        // metric preference (designFiles/07_SMART_TRENDS.md "Custom goals
        // and per-lift metric preference") — lets a lift use the user's own
        // target instead of (or in addition to) a published strength
        // standard, and lets True Max vs. Predicted 1RM be picked per lift
        // rather than one global rule.
        await db.execute('ALTER TABLE exercises ADD COLUMN goal_source TEXT');
        await db.execute(
          'ALTER TABLE exercises ADD COLUMN progress_metric TEXT',
        );
        await db.execute('''
          CREATE TABLE custom_goals (
            id            INTEGER PRIMARY KEY AUTOINCREMENT,
            exercise_id   INTEGER NOT NULL UNIQUE,
            target_weight REAL,
            target_reps   INTEGER,
            created       TEXT    NOT NULL,
            FOREIGN KEY (exercise_id) REFERENCES exercises (id) ON DELETE CASCADE
          )
        ''');
      case 13:
        // Custom goals become a log (multiple entries per exercise, each
        // optionally labeled) instead of one-per-exercise — the v12 table
        // shipped without any real usage yet (feature was brand new), so
        // this just drops and recreates rather than migrating rows.
        await db.execute('DROP TABLE custom_goals');
        await db.execute('''
          CREATE TABLE custom_goals (
            id            INTEGER PRIMARY KEY AUTOINCREMENT,
            exercise_id   INTEGER NOT NULL,
            label         TEXT,
            target_weight REAL,
            target_reps   INTEGER,
            created       TEXT    NOT NULL,
            FOREIGN KEY (exercise_id) REFERENCES exercises (id) ON DELETE CASCADE
          )
        ''');
      case 14:
        // Curated per-lift "Overview" cues (MuscleMap.liftOverview) are
        // replaced by free-text personal notes the user writes themselves
        // (designFiles/03_SCREEN_lifts.md) — and new custom exercises can
        // now record their own fine-grained target muscles instead of only
        // falling back to a broad category-based guess.
        await db.execute('ALTER TABLE exercises ADD COLUMN notes TEXT');
        await db.execute(
          'ALTER TABLE exercises ADD COLUMN target_muscles TEXT',
        );
      case 15:
        // Progress photos (a date-stamped image log) and the metric builder
        // (unlimited user-defined metrics — number/scale/classes kinds) —
        // see designFiles/05_SCREEN_metrics.md.
        await db.execute('''
          CREATE TABLE progress_photos (
            id        INTEGER PRIMARY KEY AUTOINCREMENT,
            date      TEXT    NOT NULL,
            file_path TEXT    NOT NULL,
            taken_at  TEXT    NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE custom_metrics (
            id                     INTEGER PRIMARY KEY AUTOINCREMENT,
            name                   TEXT    NOT NULL,
            kind                   TEXT    NOT NULL,
            scale_max              INTEGER,
            scale_icon             TEXT,
            class_labels           TEXT,
            created                TEXT    NOT NULL,
            allow_multiple_per_day INTEGER NOT NULL DEFAULT 0
          )
        ''');
        await db.execute('''
          CREATE TABLE custom_metric_entries (
            id                INTEGER PRIMARY KEY AUTOINCREMENT,
            custom_metric_id  INTEGER NOT NULL,
            date              TEXT    NOT NULL,
            value             REAL    NOT NULL,
            logged_at         TEXT    NOT NULL,
            FOREIGN KEY (custom_metric_id) REFERENCES custom_metrics (id) ON DELETE CASCADE
          )
        ''');
      case 16:
        // `allow_multiple_per_day` — a metric built while still on v15
        // (this same round) predates the column the CREATE TABLE above now
        // includes for anyone migrating straight from v14. Guarded by a
        // column-existence check (bug fixed 2026-07-27): `_onUpgrade` runs
        // every intervening case in one pass, so a device upgrading from
        // below v15 hits case 15's CREATE TABLE (which already has this
        // column) and this case in the same transaction — an unconditional
        // ALTER TABLE here would fail with "duplicate column name" and crash
        // the DB open for anyone who hadn't already updated past v15.
        final customMetricsColumns = await db.rawQuery(
          'PRAGMA table_info(custom_metrics)',
        );
        final hasAllowMultiplePerDay = customMetricsColumns.any(
          (c) => c['name'] == 'allow_multiple_per_day',
        );
        if (!hasAllowMultiplePerDay) {
          await db.execute(
            'ALTER TABLE custom_metrics ADD COLUMN allow_multiple_per_day '
            'INTEGER NOT NULL DEFAULT 0',
          );
        }
      case 17:
        // Home's Checklist widget — see designFiles/02_SCREEN_home.md.
        await db.execute('''
          CREATE TABLE todo_items (
            id                INTEGER PRIMARY KEY AUTOINCREMENT,
            text              TEXT    NOT NULL,
            time_of_day       TEXT,
            sort_order        INTEGER NOT NULL,
            last_checked_date TEXT
          )
        ''');
      case 18:
        // Cardio backend — see designFiles/11_SCREEN_cardio.md.
        await db.execute(
          'ALTER TABLE custom_goals ADD COLUMN target_distance REAL',
        );
        await db.execute(
          'ALTER TABLE custom_goals ADD COLUMN target_speed REAL',
        );
        await db.execute('''
          CREATE TABLE cardio_sessions (
            id          INTEGER PRIMARY KEY AUTOINCREMENT,
            exercise_id INTEGER NOT NULL,
            date        TEXT    NOT NULL,
            notes       TEXT,
            FOREIGN KEY (exercise_id) REFERENCES exercises (id) ON DELETE CASCADE
          )
        ''');
        await db.execute('''
          CREATE TABLE cardio_entries (
            id                INTEGER PRIMARY KEY AUTOINCREMENT,
            session_id        INTEGER NOT NULL,
            entry_number      INTEGER NOT NULL,
            distance_miles    REAL,
            duration_seconds  INTEGER,
            load              REAL,
            rpe               REAL,
            entry_started_at  TEXT,
            entry_completed_at TEXT,
            FOREIGN KEY (session_id) REFERENCES cardio_sessions (id) ON DELETE CASCADE
          )
        ''');
        // Backfill the new cardio exercises for existing installs — same
        // "only insert names not already present" pattern as the v5 bulk-
        // library backfill, since a fresh install already got these via
        // `_seedDefaults`.
        final existing = (await db.query(
          'exercises',
          columns: ['name'],
        )).map((r) => r['name'] as String).toSet();
        final today = DateTime.now().toIso8601String().substring(0, 10);
        for (final e in _seedExercises) {
          final name = e['name'] as String;
          if (!{
            'Run',
            'Ruck',
            'Bike',
            'Stairs',
            'General Cardio',
            'Other Cardio',
          }.contains(name)) {
            continue;
          }
          if (existing.contains(name)) continue;
          await db.insert('exercises', {
            'name': name,
            'category': e['categories'],
            'equipment_tags': e['equipment'],
            'is_seeded': 1,
            'youtube_url': null,
            'created': today,
            'pinned': 0,
          });
        }
      case 19:
        // Cardio revisions from on-device feedback the same week: per-
        // exercise distance units (a run tracked in miles, a row in meters)
        // instead of the app-wide lb/kg toggle, and pace (min/mile) instead
        // of speed (mph) for the goal gauge — see
        // designFiles/11_SCREEN_cardio.md. `exercises.cardio_unit` didn't
        // exist when v18 first shipped `cardio_entries`/the speed goal
        // column, so this both adds it and renames the two v18 columns to
        // their final names.
        await db.execute('ALTER TABLE exercises ADD COLUMN cardio_unit TEXT');
        await db.execute(
          'ALTER TABLE cardio_entries RENAME COLUMN distance_miles TO distance_canonical',
        );
        await db.execute(
          'ALTER TABLE custom_goals RENAME COLUMN target_speed TO target_pace',
        );
        const cardioUnitsByName = {
          'Rowing Machine': 'meters',
          'Run': 'miles',
          'Ruck': 'miles',
          'Bike': 'miles',
          'Stairs': 'floors',
          'General Cardio': 'miles',
          'Other Cardio': 'miles',
        };
        for (final entry in cardioUnitsByName.entries) {
          await db.update(
            'exercises',
            {'cardio_unit': entry.value},
            where: 'name = ?',
            whereArgs: [entry.key],
          );
        }
      case 20:
        // HIIT — see designFiles/12_SCREEN_hiit.md.
        await db.execute('''
          CREATE TABLE hiit_sessions (
            id                      INTEGER PRIMARY KEY AUTOINCREMENT,
            date                    TEXT    NOT NULL,
            notes                   TEXT,
            started_at              TEXT    NOT NULL,
            completed_at            TEXT,
            status                  TEXT    NOT NULL,
            automatic               INTEGER NOT NULL DEFAULT 1,
            current_sequence_index  INTEGER NOT NULL DEFAULT 0,
            current_phase           TEXT    NOT NULL DEFAULT 'work',
            phase_started_at        TEXT,
            phase_remaining_seconds REAL,
            current_reps_remaining  INTEGER,
            paused                  INTEGER NOT NULL DEFAULT 0,
            total_paused_seconds    REAL    NOT NULL DEFAULT 0
          )
        ''');
        await db.execute('''
          CREATE TABLE hiit_slots (
            id                  INTEGER PRIMARY KEY AUTOINCREMENT,
            hiit_session_id     INTEGER NOT NULL,
            sequence_index      INTEGER NOT NULL,
            group_index         INTEGER NOT NULL,
            exercise_id         INTEGER NOT NULL,
            exercise_kind       TEXT    NOT NULL,
            target_type         TEXT    NOT NULL,
            target_value        REAL,
            weight              REAL,
            rest_after_seconds  INTEGER,
            actual_reps         INTEGER,
            actual_weight       REAL,
            actual_time_seconds INTEGER,
            actual_distance     REAL,
            actual_load         REAL,
            lift_set_id         INTEGER,
            cardio_entry_id     INTEGER,
            FOREIGN KEY (hiit_session_id) REFERENCES hiit_sessions (id) ON DELETE CASCADE
          )
        ''');
      case 21:
        // Soreness AM/PM logging (designFiles/05_SCREEN_metrics.md "Soreness
        // decay") — lets a soreness entry say explicitly which half of the
        // day it's for, so a past log can be corrected by slot instead of
        // only ever appended to. Nullable: existing rows, and steps/sleep
        // (which never use this), just stay untagged.
        await db.execute('ALTER TABLE metrics_log ADD COLUMN time_slot TEXT');
      case 22:
        // Backfills v21's new `time_slot` onto every pre-existing soreness
        // row (real installs upgrading from before AM/PM logging existed) —
        // without this, a real user's whole logged history would stay
        // permanently unslotted, and `SorenessBodyMapForm`'s per-slot edit
        // (queries by an exact AM or PM) can't reload an unslotted entry
        // under either toggle position, effectively locking old data out of
        // being corrected. Per (date, region): a single entry -> AM (most
        // people only logged once a day); two or more -> earliest logged ->
        // AM, latest logged -> PM, matching what `getLatest` was already
        // treating as "today's real value" before this feature existed.
        // Anything strictly in between (a rare same-day double-correction)
        // is deleted rather than kept unslotted — it was already dead data,
        // since only the latest entry per day was ever actually read.
        final sorenessRows = await db.query(
          'metrics_log',
          where: "metric_type LIKE 'soreness_%' AND time_slot IS NULL",
          orderBy: 'date, metric_type, logged_at, id',
        );
        final groups = <String, List<Map<String, Object?>>>{};
        for (final row in sorenessRows) {
          final key = '${row['date']}|${row['metric_type']}';
          groups.putIfAbsent(key, () => []).add(row);
        }
        for (final rows in groups.values) {
          await db.update(
            'metrics_log',
            {'time_slot': 'AM'},
            where: 'id = ?',
            whereArgs: [rows.first['id']],
          );
          if (rows.length > 1) {
            await db.update(
              'metrics_log',
              {'time_slot': 'PM'},
              where: 'id = ?',
              whereArgs: [rows.last['id']],
            );
          }
          if (rows.length > 2) {
            for (final row in rows.sublist(1, rows.length - 1)) {
              await db.delete(
                'metrics_log',
                where: 'id = ?',
                whereArgs: [row['id']],
              );
            }
          }
        }
      case 23:
        // Optional goal value for a numeric custom metric (designFiles/
        // 05_SCREEN_metrics.md "Goals") — drives that metric's dashed
        // trend-chart goal line and lets it be picked for a "This Week"
        // ring row. Nullable, no backfill: existing metrics simply start
        // with no goal set, same as weight/sleep goals default to unset.
        await db.execute('ALTER TABLE custom_metrics ADD COLUMN goal REAL');
      case 24:
        // Per-metric value masking (designFiles/05_SCREEN_metrics.md
        // "Goals") — same "---" placeholder convention as
        // `Units.hideWeight`, for a metric whose raw number could be
        // sensitive to see plainly (e.g. calories) without needing to stop
        // tracking it. Nullable-free, defaults off: existing metrics keep
        // showing their real values exactly as before.
        await db.execute(
          'ALTER TABLE custom_metrics ADD COLUMN hide_value INTEGER NOT NULL DEFAULT 0',
        );
      case 25:
        // Multi-template switching (designFiles/10_WORKOUT_PLANNER.md) —
        // importing a replacement version of a template must be able to
        // drop a day that no longer exists in the new file without
        // orphaning any `planned_sessions.template_day_id` that already
        // points at it. `active` lets a day be soft-hidden (excluded from
        // `getDaysForTemplate`) instead of ever hard-deleted once history
        // could reference it; `getAllDaysById` (history lookups) stays
        // unfiltered so a soft-hidden day still resolves correctly there.
        await db.execute(
          'ALTER TABLE workout_template_days ADD COLUMN active '
          'INTEGER NOT NULL DEFAULT 1',
        );
      case 26:
        // Saved, reusable HIIT routines (designFiles/12_SCREEN_hiit.md) —
        // distinct from the hardcoded presets (`hiit_presets.dart`) and
        // from a live/completed `hiit_sessions` row: this is a named
        // target-only template a user builds once and reloads later, with
        // no `actual*`/`lift_set_id`/`cardio_entry_id` columns since it has
        // no result yet. No FK from `hiit_sessions`/`hiit_slots` back to
        // this table — a saved routine is a starting point for a fresh
        // session, never a live reference, so deleting or replacing one
        // can never orphan real logged history (unlike workout-plan
        // templates above).
        await db.execute('''
          CREATE TABLE hiit_routines (
            id        INTEGER PRIMARY KEY AUTOINCREMENT,
            name      TEXT    NOT NULL,
            automatic INTEGER NOT NULL DEFAULT 0,
            created   TEXT    NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE hiit_routine_slots (
            id                 INTEGER PRIMARY KEY AUTOINCREMENT,
            hiit_routine_id    INTEGER NOT NULL,
            sequence_index     INTEGER NOT NULL,
            group_index        INTEGER NOT NULL,
            exercise_id        INTEGER NOT NULL,
            exercise_kind      TEXT    NOT NULL,
            target_type        TEXT    NOT NULL,
            target_value       REAL,
            weight             REAL,
            rest_after_seconds INTEGER,
            FOREIGN KEY (hiit_routine_id) REFERENCES hiit_routines (id) ON DELETE CASCADE
          )
        ''');
      case 27:
        // Farmer's Carry — a cardio exercise the app treats identically to
        // Ruck (same body parts, same "just a different way to carry the
        // weight" load); backfilled for any install that predates it, same
        // "only insert if not already present" pattern as the v19 cardio
        // backfill above. Fresh installs get it directly via
        // `_seedExercises`.
        final existingNames = (await db.query(
          'exercises',
          columns: ['name'],
        )).map((r) => r['name'] as String).toSet();
        if (!existingNames.contains("Farmer's Carry")) {
          await db.insert('exercises', {
            'name': "Farmer's Carry",
            'category': 'legs,core,back',
            'equipment_tags': 'cardio',
            'cardio_unit': 'miles',
            'is_seeded': 1,
            'youtube_url': null,
            'created': DateTime.now().toIso8601String().substring(0, 10),
            'pinned': 0,
          });
        }
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
        'cardio_unit': e['cardio_unit'],
      });
    }
  }

  /// Clears all logged entries (lift/cardio/HIIT sets and sessions,
  /// bodyweight, metrics, cycle) but leaves the exercise list (seeded +
  /// custom) and settings untouched — this is "wipe my data," not "reset my
  /// app setup." Deleting `cardio_sessions`/`hiit_sessions` cascades to
  /// `cardio_entries`/`hiit_slots` (`PRAGMA foreign_keys = ON`).
  Future<void> wipeLoggedData() async {
    final db = await database;
    await db.delete('lift_sets');
    await db.delete('lift_sessions');
    await db.delete('bodyweight_log');
    await db.delete('metrics_log');
    await db.delete('cycle_log');
    await db.delete('cardio_sessions');
    await db.delete('hiit_sessions');
  }

  /// Full reset used before loading synthetic test data: clears everything
  /// including exercises, then reseeds the full default exercise library so test-data
  /// generation has a known, deterministic exercise list to work from.
  /// Settings (e.g. unit preference) are left alone. Deleting
  /// `cardio_sessions`/`hiit_sessions` also cascades to `cardio_entries`/
  /// `hiit_slots` (`PRAGMA foreign_keys = ON`, set in `onOpen`) — without
  /// this, repeated demo resets left old cardio/HIIT rows behind pointing at
  /// exercise ids that no longer existed after the reseed, silently
  /// accumulating orphaned rows every time "Reset Demo Data" ran.
  Future<void> wipeEverythingAndReseed() async {
    final db = await database;
    await db.delete('lift_sets');
    await db.delete('lift_sessions');
    await db.delete('bodyweight_log');
    await db.delete('metrics_log');
    await db.delete('cycle_log');
    await db.delete('cardio_sessions');
    await db.delete('hiit_sessions');
    await db.delete('exercises');
    await _seedDefaults(db);
  }

  /// Read-only check used to decide whether a profile that predates the
  /// onboarding flag is a genuinely fresh install (show onboarding) or an
  /// already-in-use profile that just never had the flag written (grandfather
  /// it in as already onboarded, without ever showing the survey
  /// retroactively). Never writes anything itself.
  Future<bool> hasAnyPriorActivity() async {
    final db = await database;
    Future<int> count(String table, {String? where}) async {
      final rows = await db.rawQuery(
        'SELECT COUNT(*) AS c FROM $table${where == null ? '' : ' WHERE $where'}',
      );
      return (rows.first['c'] as int?) ?? 0;
    }

    if (await count('app_settings') > 0) return true;
    if (await count('lift_sessions') > 0) return true;
    if (await count('bodyweight_log') > 0) return true;
    if (await count('metrics_log') > 0) return true;
    if (await count('cycle_log') > 0) return true;
    if (await count('cardio_sessions') > 0) return true;
    if (await count('hiit_sessions') > 0) return true;
    if (await count('exercises', where: 'is_seeded = 0') > 0) return true;
    return false;
  }
}
