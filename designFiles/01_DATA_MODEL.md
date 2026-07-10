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
| is_seeded | INTEGER (bool) | true for the 5 launch lifts, false for user-added custom movements |
| youtube_url | TEXT, nullable | form-check video link |
| created | TEXT | ISO date |

**Muscle-highlight diagram is NOT a DB column** — it turned out to be a static, curated `Map<String, List<Muscle>>` in code (`MuscleMap.liftMuscles`, keyed by exercise name) for the 5 seeded lifts, since "which muscles does Back Squat hit" is reference data you look up once, not something derived from logged data. Custom exercises without a curated entry fall back to the muscles implied by their broad category tags (less precise, but always shows something). See `00_UX_DESIGN.md`.

Seed data at launch: Front Squat, Back Squat, Bench Press, Deadlift, Overhead Press (all `is_seeded = 1`). Everything else the user adds is `is_seeded = 0` and shows up in "Lifts" alongside them — no artificial distinction in the UI, `is_seeded` is just there so we can later query "what custom movements has she actually used a lot" to decide what graduates to a more built-out lift screen.

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
| weight | REAL | raw logged weight |
| rpe | REAL, nullable | 1-10 scale, nullable (some sets might not get rated, e.g. warmups) |
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
| metric_type | TEXT | `'steps'` \| `'sleep_hours'` \| `'soreness_core'` \| `'soreness_back'` \| `'soreness_arms'` \| `'soreness_legs'` \| `'soreness_chest'` \| ... (extensible) |
| value | REAL | numeric value; soreness is now **0-5**, not 1-10 (see below) |
| logged_at | TEXT, nullable | precise ISO datetime of entry — added so multiple same-day entries (e.g. logging soreness more than once) can be ordered/distinguished. Populated on new inserts; nullable for anything written before this column existed |
| notes | TEXT, nullable | |

**Revised — soreness is now per-body-part, not one generic number.** Originally a single `'soreness'` type on a 1-10 scale; replaced with 5 region-specific types (core/back/arms/legs/chest — the same 5 broad categories used by the Training Composition chart and `ExerciseCategory`) on a coarser **0-5 flame-icon scale**, entered by tapping a body-map diagram rather than typing a number. This was a deliberate dev-stage breaking change (no real user data existed yet to migrate) — see `00_UX_DESIGN.md` "Soreness body map."

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

## `app_settings`
Simple key-value store, implemented (not just planned) as of this round.

| column | type | notes |
|---|---|---|
| key | TEXT PK | e.g. `'weight_unit'` |
| value | TEXT | e.g. `'lb'` / `'kg'` |

Current keys in use: `weight_unit` (`'lb'` or `'kg'` — all weight is stored canonically in lb regardless of this setting; conversion/formatting happens only at display time via `Units`, see `00_UX_DESIGN.md`).

Still just planned, not yet keys in the table: rolling window lengths (default 7d/28d), cycle-tracking visibility toggle, admin/test mode flag.

---

## Migration discipline
Per starter bundle rules: every new column goes in both `_onCreate` and a numbered `_migrate` step; `_kDbVersion` only ever increases. Given how much this schema will grow (custom exercises, new metric types, live-timer fields already anticipated above), expect frequent version bumps early on — that's fine, just keep this doc in sync with each one.
