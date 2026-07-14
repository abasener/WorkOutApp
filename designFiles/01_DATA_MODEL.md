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
| pinned | INTEGER (bool), default 0 | the "usual suspects" — drives the quick-log dropdown (pinned-only) and a Lifts-list quick filter. Original 7 seed lifts default to pinned; the ~68 bulk-added ones don't. See `03_SCREEN_lifts.md` "Pinned lifts." |
| youtube_url | TEXT, nullable | form-check video link |
| created | TEXT | ISO date |

**Muscle-highlight diagram is NOT a DB column** — it's a static, curated `Map<String, List<Muscle>>` in code (`MuscleMap.liftMuscles`, keyed by exercise name), since "which muscles does Back Squat hit" is reference data you look up once, not something derived from logged data. **Now curated for all 93 seeded exercises** (was the original 7 only, plus a category-tag fallback for the rest) — see `00_UX_DESIGN.md` for why the fallback wasn't accurate enough to leave in place. Policy going forward: any new seeded exercise gets a curated entry in the same round it's added, not left to the fallback. Only genuinely custom (user-added) exercises still fall back to muscles implied by their broad category tags, since there's no way to pre-curate something that doesn't exist yet.

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
| rpe | REAL, nullable | 1-10 scale, nullable (some sets might not get rated, e.g. warmups). **Storage/formula direction unchanged** — 10 = to failure — even though the entry field and history display now show/accept the inverse "reps left" framing (`EffortDisplay`, see `04_SCREEN_quick_log.md`); the conversion happens only at the UI boundary. |
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

## `app_settings`
Simple key-value store, implemented (not just planned) as of this round.

| column | type | notes |
|---|---|---|
| key | TEXT PK | e.g. `'weight_unit'` |
| value | TEXT | e.g. `'lb'` / `'kg'` |

Current keys in use: `weight_unit` (`'lb'`/`'kg'`), `gender`, `birth_year`, `hide_weight` (`'true'`/`'false'`, masks read-only weight displays app-wide via `Units.formatMaskable` — see `06_SCREEN_settings.md`), `home_trend_exercise_ids` (comma-joined exercise IDs — which lifts chart in Home's Strength Trends section; unset means "not customized yet," falls back to pinned lifts), `home_trend_months` (int, default `6` — how far back those charts look; see `02_SCREEN_home.md`). All weight is stored canonically in lb regardless of the unit/hide settings; conversion/formatting/masking happens only at display time via `Units`, see `00_UX_DESIGN.md`.

Still just planned, not yet keys in the table: rolling window lengths (default 7d/28d), cycle-tracking visibility toggle, admin/test mode flag.

---

## Migration discipline
Per starter bundle rules: every new column goes in both `_onCreate` and a numbered `_migrate` step; `_kDbVersion` only ever increases. Given how much this schema will grow (custom exercises, new metric types, live-timer fields already anticipated above), expect frequent version bumps early on — that's fine, just keep this doc in sync with each one. This is also what makes the personal/demo split (below) safe: a schema bump runs `_onCreate`/`_migrate` identically against whichever file is opened, so upgrading the app never wipes real logged data as long as every migration stays additive (`ALTER TABLE`, new tables, backfills) — never a `DROP`/destructive rewrite of existing rows.

Current version: **11** (`exercises.equipment_tags` at v4; v5 backfilled the bulk exercise library onto existing installs; `exercises.pinned` at v6, also backfilled; v7 remaps old 5-category `metrics_log.metric_type` soreness keys to the new 14-sub-region keys; v8 adds `exercises.movement_patterns` — Workout Planner phase 1; v9 adds `workout_templates`/`workout_template_days`/`planned_sessions` and seeds the default template — Workout Planner phase 2; v10 renames the seeded default template's day labels from "Day 1".."Day 5" to pattern-descriptive names — `10_WORKOUT_PLANNER.md`; v11 backfills 16 more seeded exercises — 8 dynamic bodyweight core movements + 8 machines cross-checked against the user's actual Precor gym equipment, see `03_SCREEN_lifts.md` "Bulk exercise library").

## Personal vs. demo data set — implemented

Two entirely separate SQLite files rather than a `profile` column on one shared database — `terpinlift_personal.db` and `terpinlift_demo.db` (`DatabaseHelper(profile: ...)`, `lib/data/profile_manager.dart`), both created via the exact same `_onCreate`/`_migrate` path above. A column-based split was considered and rejected: it would mean every single query app-wide needs a `WHERE profile = ?`, one missed filter silently leaks or corrupts data across sets, and a demo reseed would need to delete-by-filter instead of just dropping/recreating a whole file. Separate files make "can demo ever touch personal" true by construction, not by discipline.

`AppServices.switchProfile(profile)` closes the current `DatabaseHelper`'s connection, opens the other file (running any pending migration on it independently), and reloads all repositories/settings against it. Entering **Demo** always calls `TestDataService.load()` first — a clean synthetic set every time, per the user's ask that toggling demo off and back on should mean "start over," not "resume whatever I broke last time." Entering **Personal** never wipes or reseeds anything, it just reopens the existing file.

Which profile is active is **not** stored in either database's `app_settings` table (that would make the flag itself subject to whichever file happens to be open) — it's a plain marker file (`active_profile.txt`, `ProfileManager.loadActiveProfile`/`saveActiveProfile`) in the app's documents directory, read once at startup and written on every switch. Defaults to `personal` if missing, so a fresh install or an upgrade from before this feature existed never silently lands in demo mode.

**Legacy migration**: installs from before this split have a single `terpinlift.db`. On first launch of this version, `ProfileManager.migrateLegacyDbIfNeeded()` renames that file in place to `terpinlift_personal.db` (only if the new personal file doesn't already exist) — whatever was already logged becomes the starting Personal data set rather than vanishing. Note this also carries over any leftover synthetic test data from earlier "Load Test Data" runs during development, since the old single-file setup didn't distinguish real from synthetic — worth a one-time manual review/wipe on the first device this runs on.

Export/import (`BackupService`) and Wipe Data / Reset Demo Data (Settings) all operate on whichever profile's database is currently open, and export filenames are profile-scoped (`terpinlift_export.json` vs. `terpinlift_export_demo.json`) so one can't overwrite the other.
