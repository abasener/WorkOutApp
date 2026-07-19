# Data Model (draft — pre-code)

SQLite via sqflite, per the starter bundle pattern (one repository per table, dates as `'YYYY-MM-DD'` strings, `DatabaseHelper` with versioned migrations). This doc is the source of truth for schema before any Dart is written; update it whenever the schema changes.

Nothing here is final — flag anything that looks wrong before we start coding it.

---

## `exercises`
Master list of trackable movements — both the seeded "big lifts" and user-added custom ones.

| column | type | notes |
|---|---|---|
| id | INTEGER PK | |
| name | TEXT | e.g. "Back Squat" |
| category | TEXT | **multi-valued**, comma-separated tags from: legs / core / arms / back / chest / push / pull (e.g. `"chest,push,arms"`). An exercise can carry more than one — shown as pills in the Lifts list. Still a single TEXT column (no join table) since sqflite already stores it loosely typed; the Dart model (`Exercise.categories`) handles the split/join. |
| equipment_tags | TEXT, nullable | a separate multi-valued tag dimension from `category`: comma-separated values from `ExerciseType` (cardio/machine/compound/bodyweight), e.g. `"compound"`. Drives Lifts-list filtering/sorting (`03_SCREEN_lifts.md`) and, for `bodyweight`, a different e1RM/goal calculation path (`07_SMART_TRENDS.md`). The 5 barbell seed lifts are tagged `compound`; Pull Up/Push Up are tagged `bodyweight`. |
| movement_patterns | TEXT, nullable | a third multi-valued tag dimension: comma-separated `MovementPattern` values (squat/hinge/horizontalPush/verticalPush/horizontalPull/verticalPull + 6 accessory patterns). Powers the Workout Planner's pattern-pool browsing (`10_WORKOUT_PLANNER.md`) — not used anywhere else. |
| is_seeded | INTEGER (bool) | true for the seeded library, false for user-added custom movements |
| pinned | INTEGER (bool), default 0 | the "usual suspects" — drives the quick-log dropdown (pinned-only) and a Lifts-list quick filter. 8 curated seed lifts default to pinned (redone 2026-07-21, see `03_SCREEN_lifts.md` "Pinned lifts"); everything else doesn't. |
| youtube_url | TEXT, nullable | form-check video link |
| created | TEXT | ISO date |
| goal_source | TEXT, nullable | `'standard'` \| `'custom'` \| `null` (auto). `null` picks a published standard if one exists, else the latest `custom_goals` entry if one exists, else no goal shown — see `custom_goals` below. Added v12. |
| progress_metric | TEXT, nullable | `ProgressMetric` — modeled but **not wired to any UI toggle** (`07_SMART_TRENDS.md` "e1RM confusion" — once Lift detail's 3 sections were redesigned, each ended up with one unambiguous behavior, so there was no live decision left for this to control). Added v12, effectively unused since. |
| notes | TEXT, nullable | free-text personal notes the user writes themselves — replaced the old curated per-lift "Overview" cues entirely. Added v14. |
| target_muscles | TEXT, nullable | comma-joined `Muscle` names — user-set fine-grained target muscles (`MuscleSelectorSheet`), takes priority over the curated `MuscleMap.liftMuscles` fallback below when non-empty. Added v14. |

**Muscle-highlight diagram: two layers now, not one.** `Exercise.targetMuscles` (above) is checked first if the user has set it; otherwise falls back to a static, curated `Map<String, List<Muscle>>` in code (`MuscleMap.liftMuscles`, keyed by exercise name — reference data you look up once, not derived from logged data), curated for all 93 seeded exercises; otherwise falls back further to muscles implied by the exercise's broad category tags. Policy for new seeded exercises is still to add a curated `liftMuscles` entry in the same round they're added, but a user (for a custom exercise, or to override/refine a seeded one) can now set their own via `targetMuscles` without waiting on a code change.

**Seed data — bulk-expanded this round.** `DatabaseHelper._seedExercises` now has ~75 entries (`is_seeded = 1`), covering most of what a typical gym-goer encounters: the original 7 (5 barbell staples + Pull Up/Push Up), more compound barbell/dumbbell lifts (including Olympic-style Clean and Jerk/Snatch/Split Jerk/Push Jerk, kept as reference data even though the user's current gym doesn't allow them), single-joint free-weight accessories (curls, raises, extensions — tagged `ExerciseType.isolation`, a 5th value added specifically to distinguish these from `compound`), more bodyweight movements (Chin Up, Dip, Sit Up, Crunch, Hanging Leg Raise — Plank explicitly excluded since it's a static hold, not sets/reps), ~25 named machines/cables (Lat Pulldown, Leg Press, Smith Machine Squat, etc.), and one cardio entry (Rowing Machine — tracked the same sets/reps/RPE way, reps being meters rowed). Deliberately **not** exhaustive down to modified variants (heel-elevated squat vs. squat, etc.) — one entry per commonly-named lift, per the user's explicit scope call. Everything else the user adds is `is_seeded = 0` and shows up in "Lifts" alongside them — no artificial distinction in the UI, `is_seeded` is just there so we can later query "what custom movements has she actually used a lot" to decide what graduates to a more built-out lift screen.

**Backfilled via migration, not just `_seedDefaults`** — a version-5 migration inserts any `_seedExercises` entry not already present by name, so an existing install with real logged data gets the new library without wiping (checked this was actually missing: Pull Up/Push Up had only ever been added to `_seedDefaults`, so an existing install genuinely never got them until this fix).

## `lift_sessions`
One row per workout session for a given exercise (supports the future live-timer flow now, even though the timer UI itself is a later build).

| column | type | notes |
|---|---|---|
| id | INTEGER PK | |
| exercise_id | INTEGER FK → exercises | |
| date | TEXT | 'YYYY-MM-DD' |
| started_at | TEXT, nullable | ISO datetime — set when live timer starts (later phase) |
| completed_at | TEXT, nullable | ISO datetime — set when "Complete" hit (later phase) |
| notes | TEXT, nullable | free text |

## `lift_sets`
Individual sets within a session — this is the core logging unit.

| column | type | notes |
|---|---|---|
| id | INTEGER PK | |
| session_id | INTEGER FK → lift_sessions | |
| set_number | INTEGER | order within session |
| reps | INTEGER | |
| weight | REAL | raw logged weight — for `ExerciseType.bodyweight` lifts this is the **signed added/assisted load** relative to bodyweight instead (negative = assisted, 0 = plain bodyweight, positive = weighted), not a total; see `07_SMART_TRENDS.md` "Bodyweight movements" for how e1RM/goal calculations account for that |
| rpe | REAL, nullable | **stored** 1-10 scale, nullable (some sets might not get rated, e.g. warmups), 10 = to failure — unchanged direction/range at rest. The **entry/display** field is a separate 0-10 "reps left" domain (0 = "tried one more, failed"; 9 and 10 both collapse to the stored floor of 1, since past ~8 reps left the distinction carries no real information) — `EffortDisplay` converts at the UI boundary only, see `08_GLOSSARY_AND_SCIENCE.md` RPE entry. Revised from an earlier 1-10↔1-10 version after real use surfaced the mismatch between the user's own "0 = failure" convention and the old floor of 1. |
| set_started_at | TEXT, nullable | ISO datetime, for future rest-interval computation |
| set_completed_at | TEXT, nullable | |

**Derived, not stored:** estimated 1RM per set (Epley/Brzycki formula off reps+weight), and an RPE-adjusted confidence weight. Computed at query/analysis time so the formula can be revised later without a migration. See `05_GLOSSARY_AND_SCIENCE.md`.

## `bodyweight_log`
| column | type | notes |
|---|---|---|
| id | INTEGER PK | |
| date | TEXT | |
| weight | REAL | never rendered directly in UI; used only for %-bodyweight lift ratios and recomposition flags |

## `metrics_log`
Generic table for the simple daily non-lift numbers (steps, sleep hours, per-region soreness) rather than a table per metric — keeps it easy to add new metric types later (drinks, weather, timezone-travel flag) without a migration each time.

| column | type | notes |
|---|---|---|
| id | INTEGER PK | |
| date | TEXT | day granularity, `'YYYY-MM-DD'` |
| metric_type | TEXT | `'steps'` \| `'sleep_hours'` \| 14 `'soreness_*'` sub-region keys (`SorenessRegion`, see below) \| ... (extensible) |
| value | REAL | numeric value; soreness is **0-5**, not 1-10 (see below) |
| logged_at | TEXT, nullable | precise ISO datetime of entry — added so multiple same-day entries (e.g. logging soreness more than once) can be ordered/distinguished, and used as the tiebreaker in `MetricsRepository.getByType`'s `ORDER BY` (a real bug: without it, same-day entries fell back to insertion order, so a later same-day correction could lose to an earlier one — fixed this round). Populated on new inserts; nullable for anything written before this column existed |
| notes | TEXT, nullable | |

**Revised — soreness is now per-sub-region, not one generic number.** Originally a single `'soreness'` type on a 1-10 scale, then 5 broad region types (core/back/arms/legs/chest), now **14 finer sub-regions** grouped by common lift-pattern (chest; core → abs/obliques; back → upper/lower; arms → biceps/triceps/shoulders/forearms; legs → quads/hamstrings/glutes/calves/inner-thigh) on a **0-5 flame-icon scale**, entered by tapping a body-map diagram rather than typing a number. The 5→14 split was a genuine schema change with real user data already logged under it — handled with a version-7 migration remapping old keys to a representative new sub-region, not a breaking dev-stage reset like the original 1-10→0-5 change was. See `00_UX_DESIGN.md` "Soreness body map" and `05_SCREEN_metrics.md` "Soreness sub-splitting."

Open question: sleep might eventually want more than one number (hours + quality?) — flagged for later, `metrics_log` can hold multiple rows per date/type if so (e.g. `sleep_hours` and `sleep_quality` as separate `metric_type`s), no schema change needed.

## `cycle_log`
Kept as its own table (not folded into `metrics_log`) since it has different fields and different display rules (nondescript card, never shown on Home).

**Revised:** there is no separate period-start/period-end record. A period is simply a run of consecutive dates with `flow_value > 0` — derived at query time (`CycleAnalysis.compute`), not stored. This came from wanting the simplest possible entry UX: tap a calendar day, pick a flow score 0-4.

| column | type | notes |
|---|---|---|
| id | INTEGER PK | |
| date | TEXT | |
| entry_type | TEXT | `'flow'` (daily flow score, one row per date) or `'symptom'` (free note) |
| flow_value | INTEGER, nullable | 0-4, only meaningful when `entry_type = 'flow'`. 0 means "logged, no bleeding" — distinct from no entry at all |
| symptom_tag | TEXT, nullable | free-ish tag: low_energy, cramps, etc. |
| notes | TEXT, nullable | |

Period length = count of consecutive flow>0 days in one run. Cycle length = days between the start of one run and the start of the next. Both computed live from `getFlowEntries()`, nothing pre-aggregated/stored.

## Workout Planner tables (`10_WORKOUT_PLANNER.md`, phase 2)
Three new tables, no changes to any existing ones.

**`workout_templates`**: id, name, is_default (INTEGER bool — exactly one row is `1` at a time; the seeded default is "Rotating Full-Body," matching the source PDF's Example Week), created.

**`workout_template_days`**: id, template_id (FK, `ON DELETE CASCADE`), day_order, day_label, patterns (comma-joined `MovementPattern` names for that day's slots — same storage shape as `exercises.movement_patterns`).

**`planned_sessions`**: id, template_day_id (FK, `ON DELETE CASCADE`), date, started_at (ISO datetime), completed_at (nullable), status (`'active'` \| `'completed'` \| `'aborted'`), notes (nullable). At most one `active` row at a time (enforced in app logic, not a DB constraint).

**Deliberately no `planned_session_slots` table.** A slot's "what's been done" is derived live by `WorkoutPlanService.matchedSessions` — filtering `lift_sessions` logged on `planned_sessions.date` whose exercise's `movement_patterns` contains the slot's pattern — rather than written at log time. This was a design change mid-build: the original plan stored an explicit per-slot completion FK, but the requirement that "more than one lift can satisfy a slot" (and one lift can satisfy more than one slot) made a stored one-slot-one-completion row the wrong shape; deriving live handles both for free and needs no write-time hook into the logging path at all.

## `custom_goals`
A **log**, not one-per-exercise — the exercise's `goal_source`/gauge reads the most recent row by `created`; older rows are just browsable/deletable history (`CustomGoalHistorySheet`). Reworked into this shape the same day it first shipped as a single overwritable value, once the user clarified she wanted "something more like the lift log as an entry."

| column | type | notes |
|---|---|---|
| id | INTEGER PK | |
| exercise_id | INTEGER FK → exercises | no uniqueness constraint — an exercise can have many rows |
| label | TEXT, nullable | user-typed name for this goal entry (a date, "August target," whatever) — falls back to displaying `created`'s date if unset |
| target_weight | REAL, nullable | lb, canonical — set when the exercise's goal axis is weight |
| target_reps | INTEGER, nullable | set when the exercise's goal axis is reps (bodyweight-tagged exercises) |
| target_distance | REAL, nullable | meters canonical (or a raw floor count for a floors-unit exercise) — cardio exercises, added v18, see `11_SCREEN_cardio.md` |
| target_pace | REAL, nullable | seconds per canonical meter (or per floor) — cardio exercises, added v18 as `target_speed`, renamed+changed basis v19 (pace, not speed — see `11_SCREEN_cardio.md` "Per-exercise distance units") |
| created | TEXT | ISO datetime |

Exactly one of `target_weight`/`target_reps` (lift exercises) or `target_distance`/`target_pace` (cardio exercises) is set per row — enforced in code, not a CHECK constraint.

## `cardio_sessions` / `cardio_entries` (added v18, see `11_SCREEN_cardio.md`)
Cardio's counterpart to `lift_sessions`/`lift_sets` — same session-then-entries shape, kept as a fully separate table pair rather than reusing the lift tables, since reps/weight never meant anything for "how far did you run."

**`cardio_sessions`**: id, exercise_id (FK → exercises, `ON DELETE CASCADE`), date, notes (nullable).

**`cardio_entries`**:

| column | type | notes |
|---|---|---|
| id | INTEGER PK | |
| session_id | INTEGER FK → cardio_sessions | `ON DELETE CASCADE` |
| entry_number | INTEGER | order within the session — usually just one entry, but interval-style cardio can log several |
| distance_canonical | REAL, nullable | meters, or a raw floor count for a floors-unit exercise — added v18 as `distance_miles`, renamed+changed basis v19 once distance units became per-exercise (`Exercise.cardioUnit`) instead of the app-wide lb/kg toggle |
| duration_seconds | INTEGER, nullable | |
| load | REAL, nullable | generic, **unitless** resistance/incline/added-load number — never run through a unit conversion, since it doesn't consistently mean "weight" (a rower's resistance level and a treadmill's incline % aren't the same unit). Labeled "Resistance (optional)" in the entry forms |
| rpe | REAL, nullable | 1-10, entered directly (not the lift form's "reps left" inversion) — labeled "Effort (1-10)," 10 = hardest |
| entry_started_at / entry_completed_at | TEXT, nullable | present for parity with `lift_sets`' same (also currently unused) columns — a possible future timer-auto-fill write target, not wired up yet |

Pace (`CardioUnits.paceSecondsPerUnit`), like `LiftSet.e1rm`, is always derived from distance+duration, never stored on the entry itself — only a *goal's* pace (`custom_goals.target_pace`) is a real stored number, for comparison purposes.

## `exercises.cardio_unit` (added v19, see `11_SCREEN_cardio.md`)
`DistanceUnit?` (`'miles'` \| `'km'` \| `'meters'` \| `'floors'`), only meaningful for `ExerciseType.cardio`-tagged rows — the exercise's own designated distance unit (a run in miles, a row in meters, stairs in floors), set via `AddExerciseSheet`. Every logged entry/goal for that exercise displays and converts through this one unit regardless of which unit an individual entry was typed in. `null` = not a cardio exercise, or a cardio exercise that predates this column (falls back to `CardioUnits.defaultUnit`, miles).

## `hiit_sessions` / `hiit_slots` (added v20, see `12_SCREEN_hiit.md`)
A HIIT workout builds and runs entirely in these two tables, but **saves into the normal `lift_sessions`/`lift_sets` and `cardio_sessions`/`cardio_entries` tables** — a completed HIIT session is indistinguishable from manually-logged sets at the data level, these tables just remember the routine's shape and (for an in-progress session) exactly where playback is.

**`hiit_sessions`**: id, date, notes (nullable), started_at, completed_at (nullable), status (`'active'` \| `'completed'` \| `'aborted'`, same convention as `PlannedSession`), automatic (INTEGER bool — the automatic/manual toggle chosen at setup), plus live-resume state: current_sequence_index, current_phase (`'work'` \| `'rest'`), phase_started_at (nullable), phase_remaining_seconds (nullable REAL), current_reps_remaining (nullable INTEGER), paused (INTEGER bool). The resume-state columns are what let leaving the active-session screen (paused or not) and coming back later reconstruct exactly where playback was — see `12_SCREEN_hiit.md` "Pausing and resuming."

**`hiit_slots`** — one row per exercise occurrence, in strict play order:

| column | type | notes |
|---|---|---|
| id | INTEGER PK | |
| hiit_session_id | INTEGER | `ON DELETE CASCADE`, no FK constraint declared (see below) |
| sequence_index | INTEGER | global play order across the whole routine |
| group_index | INTEGER | which round — for the progress bar's round markers and to know which slot's rest is "between rounds" |
| exercise_id | INTEGER | no FK constraint — set at setup time, well before any `lift_set`/`cardio_entry` referencing it exists |
| exercise_kind | TEXT | `'lift'` \| `'cardio'` — stored redundantly rather than re-derived from the exercise's tags every time |
| target_type | TEXT | `'reps'` \| `'amrap'` \| `'time'` \| `'distance'` |
| target_value / weight | REAL, nullable | set once at setup, never edited live |
| rest_after_seconds | INTEGER, nullable | `null`/`0` = "Direct" (no rest before the next slot) |
| actual_reps / actual_weight / actual_time_seconds / actual_distance / actual_load | nullable | filled in live during the session (or assumed-equal-to-target for cardio) and correctable on the report screen before saving |
| lift_set_id / cardio_entry_id | INTEGER, nullable | **not populated in v1** — `LiftRepository.logSession`/`CardioRepository.logSession` don't return per-row ids today, so the Workouts tab instead groups a day's HIIT-produced sets by (date, exercise_id) rather than a direct FK. Reserved for a future precision pass. |
A date-stamped image log — multiple rows can share a `date` (different angles/poses the same day).

| column | type | notes |
|---|---|---|
| id | INTEGER PK | |
| date | TEXT | `'YYYY-MM-DD'` |
| file_path | TEXT | absolute path into this app's own document storage (`progress_photos/` subfolder) — images are always copied here from wherever the picker/camera/generator produced them, never referenced in place, so the app doesn't depend on a transient cache path staying valid |
| taken_at | TEXT | ISO datetime — the secondary sort key within a date (multiple same-day photos) |

Deleting a row also deletes its backing file (`ProgressPhotoRepository.delete`) — an orphaned file isn't reachable anywhere else in the app. **Not yet included in `BackupService`'s export/import** — earmarked, not fixed, see `06_SCREEN_settings.md`.

## `custom_metrics` / `custom_metric_entries`
The "metric builder" — unlimited user-defined metrics, each deciding how its own entries are captured via `kind`.

**`custom_metrics`**:

| column | type | notes |
|---|---|---|
| id | INTEGER PK | |
| name | TEXT | user-chosen |
| kind | TEXT | `'number'` \| `'scale'` \| `'classes'` — decides which of the next 3 columns apply |
| scale_max | INTEGER, nullable | top of a 0-`scale_max` level, `kind = 'scale'` only (always 5 today, no UI to change it, but stored per-row rather than hardcoded) |
| scale_icon | TEXT, nullable | `ScaleIcon` (`'flame'`\|`'star'`\|`'dot'`\|`'heart'`\|`'bolt'`\|`'moon'`\|`'drop'`), `kind = 'scale'` only |
| class_labels | TEXT, nullable | comma-joined ordered labels (worst→best), `kind = 'classes'` only — entries store a label's *index* into this list, not the string, so relabeling later doesn't touch old entries |
| created | TEXT | ISO datetime |
| allow_multiple_per_day | INTEGER (bool), default 0 | added v16. `0` (default): logging again on an already-logged date **replaces** that entry (`CustomMetricRepository.upsertEntry`). `1`: adds a second row instead, same "append" behavior soreness has always had. Chosen once per metric, at build time. |

**`custom_metric_entries`**:

| column | type | notes |
|---|---|---|
| id | INTEGER PK | |
| custom_metric_id | INTEGER FK → custom_metrics, `ON DELETE CASCADE` | deleting a metric definition deletes all its logged values too, no confirmation-heavy dialog — a mis-built metric carries none of the weight a real exercise's logged sessions do |
| date | TEXT | `'YYYY-MM-DD'` |
| value | REAL | meaning depends on the parent metric's `kind`: a plain number, a 0-`scale_max` level, or a class-label index |
| logged_at | TEXT | ISO datetime |

**Not yet included in `BackupService`'s export/import**, along with `custom_goals` above — see `06_SCREEN_settings.md` known-gap note.

## `todo_items`
Home's Checklist widget — a fixed, user-edited list of recurring reminders, not a one-off task list.

| column | type | notes |
|---|---|---|
| id | INTEGER PK | also used as the local-notification id for that item's reminder, 1:1 |
| text | TEXT | |
| time_of_day | TEXT, nullable | `'HH:mm'`, 24-hour, local time — `null` means no reminder |
| sort_order | INTEGER | |
| last_checked_date | TEXT, nullable | `'YYYY-MM-DD'` — the entire daily-reset mechanism: a row reads as checked only if this equals today, so nothing needs to run overnight to clear it |

**Not yet included in `BackupService`'s export/import**, alongside the other gaps noted in `06_SCREEN_settings.md`.

## `app_settings`
Simple key-value store, implemented (not just planned) as of this round.

| column | type | notes |
|---|---|---|
| key | TEXT PK | e.g. `'weight_unit'` |
| value | TEXT | e.g. `'lb'` / `'kg'` |

Current keys in use: `weight_unit` (`'lb'`/`'kg'`), `gender`, `birth_year`, `hide_weight` (`'true'`/`'false'`, masks read-only weight displays app-wide via `Units.formatMaskable` — see `06_SCREEN_settings.md`), `home_trend_months` (int, default `6` — how far back every Strength Trend *and* Metric Trend card looks, shared across all of them; see `02_SCREEN_home.md`), `home_widget_order` (comma-joined `HomeLayoutItem` tokens — each is a bare `HomeWidgetId` key, `<HomeWidgetId>:<exerciseId>` for a Strength Trend card, or `<HomeWidgetId>:<metricRef>` for a Metric Trend card, added 2026-07-18, token format revised 2026-07-19 first for repeatable per-lift Strength Trend cards and again the same day to add Metric Trend's string ref; unset falls back to every section in its default order, see `02_SCREEN_home.md` "Layout editing" / "Strength Trend widgets" / "Metric Trend widgets"). All weight is stored canonically in lb regardless of the unit/hide settings; conversion/formatting/masking happens only at display time via `Units`, see `00_UX_DESIGN.md`.

Still just planned, not yet keys in the table: rolling window lengths (default 7d/28d), cycle-tracking visibility toggle, admin/test mode flag.

---

## Migration discipline
Per starter bundle rules: every new column goes in both `_onCreate` and a numbered `_migrate` step; `_kDbVersion` only ever increases. Given how much this schema will grow (custom exercises, new metric types, live-timer fields already anticipated above), expect frequent version bumps early on — that's fine, just keep this doc in sync with each one. This is also what makes the personal/demo split (below) safe: a schema bump runs `_onCreate`/`_migrate` identically against whichever file is opened, so upgrading the app never wipes real logged data as long as every migration stays additive (`ALTER TABLE`, new tables, backfills) — never a `DROP`/destructive rewrite of existing rows.

Current version: **20** (`exercises.equipment_tags` at v4; v5 backfilled the bulk exercise library onto existing installs; `exercises.pinned` at v6, also backfilled; v7 remaps old 5-category `metrics_log.metric_type` soreness keys to the new 14-sub-region keys; v8 adds `exercises.movement_patterns` — Workout Planner phase 1; v9 adds `workout_templates`/`workout_template_days`/`planned_sessions` and seeds the default template — Workout Planner phase 2; v10 renames the seeded default template's day labels from "Day 1".."Day 5" to pattern-descriptive names — `10_WORKOUT_PLANNER.md`; v11 backfills 16 more seeded exercises — 8 dynamic bodyweight core movements + 8 machines cross-checked against the user's actual Precor gym equipment, see `03_SCREEN_lifts.md` "Bulk exercise library"; v12 adds `exercises.goal_source`/`progress_metric` and the original one-row-per-exercise `custom_goals` table; v13 reshapes `custom_goals` into a log — DROPs and recreates the v12 table rather than migrating rows, since it had shipped without any real usage yet; v14 adds `exercises.notes`/`target_muscles`; v15 adds `progress_photos`, `custom_metrics`, `custom_metric_entries`; v16 adds `custom_metrics.allow_multiple_per_day`; v17 adds `todo_items` — Home's Checklist widget, see `02_SCREEN_home.md`; v18 adds `cardio_sessions`/`cardio_entries` and `custom_goals.target_distance`/`target_speed`, backfills 6 new seeded cardio exercises; v19 adds `exercises.cardio_unit` and renames v18's `cardio_entries.distance_miles`→`distance_canonical` and `custom_goals.target_speed`→`target_pace` (per-exercise distance units + pace-not-speed goals, both revisions from same-week on-device feedback) — see `11_SCREEN_cardio.md`; v20 adds `hiit_sessions`/`hiit_slots` — see `12_SCREEN_hiit.md`).

## Personal vs. demo data set — implemented

Two entirely separate SQLite files rather than a `profile` column on one shared database — `terpinlift_personal.db` and `terpinlift_demo.db` (`DatabaseHelper(profile: ...)`, `lib/data/profile_manager.dart`), both created via the exact same `_onCreate`/`_migrate` path above. A column-based split was considered and rejected: it would mean every single query app-wide needs a `WHERE profile = ?`, one missed filter silently leaks or corrupts data across sets, and a demo reseed would need to delete-by-filter instead of just dropping/recreating a whole file. Separate files make "can demo ever touch personal" true by construction, not by discipline.

`AppServices.switchProfile(profile)` closes the current `DatabaseHelper`'s connection, opens the other file (running any pending migration on it independently), and reloads all repositories/settings against it. Entering **Demo** always calls `TestDataService.load()` first — a clean synthetic set every time, per the user's ask that toggling demo off and back on should mean "start over," not "resume whatever I broke last time." Entering **Personal** never wipes or reseeds anything, it just reopens the existing file.

Which profile is active is **not** stored in either database's `app_settings` table (that would make the flag itself subject to whichever file happens to be open) — it's a plain marker file (`active_profile.txt`, `ProfileManager.loadActiveProfile`/`saveActiveProfile`) in the app's documents directory, read once at startup and written on every switch. Defaults to `personal` if missing, so a fresh install or an upgrade from before this feature existed never silently lands in demo mode.

**Legacy migration**: installs from before this split have a single `terpinlift.db`. On first launch of this version, `ProfileManager.migrateLegacyDbIfNeeded()` renames that file in place to `terpinlift_personal.db` (only if the new personal file doesn't already exist) — whatever was already logged becomes the starting Personal data set rather than vanishing. Note this also carries over any leftover synthetic test data from earlier "Load Test Data" runs during development, since the old single-file setup didn't distinguish real from synthetic — worth a one-time manual review/wipe on the first device this runs on.

Export/import (`BackupService`) and Wipe Data / Reset Demo Data (Settings) all operate on whichever profile's database is currently open, and export filenames are profile-scoped (`terpinlift_export.json` vs. `terpinlift_export_demo.json`) so one can't overwrite the other.
