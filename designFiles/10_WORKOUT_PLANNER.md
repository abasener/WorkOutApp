# Workout Planner (movement-pattern session builder)

**Status: Phases 1 and 2 implemented, plus follow-up polish (Home timer, Workouts-tab day grouping, edit/delete on a completed session).** Sparked by a gym-plan PDF the user built in a separate chat (rotating full-body framework, organized by movement pattern — squat/hinge/horizontal-push/vertical-push/horizontal-pull/vertical-pull, plus accessory buckets). This doc captures the scope and shape agreed on before code, plus what's actually built so far — see designFiles/README.md for how these docs are used.

## Phase 1 — implemented

`MovementPattern` enum (12 values, `data/models/exercise.dart`) as a third exercise-tag dimension; `Exercise.patterns` + `exercises.movement_patterns` column (DB v8, `ALTER TABLE` + backfill migration tagging every existing seeded exercise by name, same pattern as the equipment-tags/pinned backfills). Added the 6 exercises named in the source PDF that weren't seeded yet (Trap Bar Deadlift, Landmine Press, Cable Pull-Through, Pallof Press, Straight-Arm Cable Pulldown, Glute Bridge Machine), tagged along with everything else. Manually editable via a third `FilterChip` `Wrap` in `AddExerciseSheet`.

`ReadinessEngine.computePatternRecency(exercises, allSessions)` — days since any exercise carrying a given pattern was last logged (or `null` if never), one entry per `MovementPattern`. Deliberately recency-only, not the fuller RPE/overload-trend signal `computeCategoryStatus` uses — patterns are movement categories, not muscle groups, so that slump-detection signal doesn't map cleanly onto them; "what's overdue" is genuinely the whole ask for the picker. Covered by `readiness_engine_test.dart`.

`PatternPoolScreen` (`lib/screens/planner/`) — exercises tagged with a given pattern, sorted by `ReadinessEngine.readinessForExercise` (most-ready first). Tapping an exercise pushes to its existing `LiftDetailScreen` — this screen never logs anything itself, matching "guide, not coach." Reused unchanged as the slot-drill-down screen in phase 2.

The original flat pattern-list entry screen (`WorkoutPlannerScreen`) was **retired in phase 2**, superseded by `DaySelectScreen` (day-first, see below) — its lift-count-per-pattern idea lives on as the `X lifts` text on each slot card.

## Phase 2 — implemented (day-first active sessions)

New models/repository: `WorkoutTemplate`, `WorkoutTemplateDay`, `PlannedSession`, `PlannedSessionStatus` (`data/models/workout_plan.dart`), `WorkoutPlanRepository`. DB v9 adds `workout_templates`, `workout_template_days`, `planned_sessions` and seeds one default template (`is_default = 1`, name "Rotating Full-Body") whose 5 days are the source PDF's Example Week table verbatim — so Day-based selection works immediately, no CSV import (phase 3) required first. Day 5 encodes both `squat` and `hinge` patterns (the PDF says "whichever undertrained") — both slots show, filling either or neither is fine.

`WorkoutPlanService` (pure, no DB) — `matchedSessions(date, pattern, allSessions, exercisesById)` derives what's been done for a slot by filtering same-day `lift_sessions` whose exercise carries that pattern, and `progressFraction` for the soft progress bar. Covered by `workout_plan_service_test.dart`. See "Data model" below for why this replaced the originally-planned stored slot-completion table.

Two screens:
- `DaySelectScreen` — the default template's days, most-overdue-first (recency = days since a `planned_sessions` row for that day last existed), each row previewing its patterns. Tapping a day calls `startSession` and opens `ActiveDayScreen`.
- `ActiveDayScreen` (the "movement set" page) — elapsed timer (`Timer.periodic`, display-only, computed from `started_at`), a soft `LinearProgressIndicator` (colored `AppColors.good`, not the accent red, so it doesn't read as a requirement bar), a notes `TextField` persisted to `planned_sessions.notes`, one card per pattern slot (icon flips filled/unfilled, shows `X lifts` when empty or the matched exercise name(s) when not — tapping opens `PatternPoolScreen`), and Abort (confirm dialog, logged lifts untouched, only the session marker changes) / Complete (no confirmation, no minimum slots filled) buttons.

Home card (`_buildPlannerCard` in `home_screen.dart`) now has both states: default `AppCard` styling + "Plan a session" when no active session; `AppColors.accentDim` background / `AppColors.accent` border (red) + the day's label + an elapsed-time subtitle ("`{Xh Ym}` · tap to resume", ticking via a 30s `Timer.periodic` on `HomeScreen` itself, same `started_at`-derived calculation as the Active Day page) when one exists, tapping goes straight to `ActiveDayScreen` rather than back through `DaySelectScreen`. `AppCard` gained optional `backgroundColor`/`borderColor` params to support this (defaults unchanged everywhere else it's used).

**Edit/view mode on `ActiveDayScreen`** — the same screen doubles as a view/edit page for a non-active (`completed`) session, opened from the Workouts tab (below). Branches internally on `session.status == active`: a genuinely active session keeps the ticking timer and Abort/Complete; a completed one opened for editing shows no timer (just the static "% covered" line), and the two bottom buttons become **Save changes** (persists the notes field, pops back — no other fields are editable, since slots are still derived live off the same-date logged lifts, not stored) and **Delete workout** (confirm dialog, calls `WorkoutPlanRepository.deleteSession` which removes only the `planned_sessions` row — the underlying `lift_sessions` rows are untouched and simply become ungrouped, reappearing as plain rows in the Workouts tab).

**Not built yet (phase 3):** multi-template switching UI (Settings), saved-template builder beyond the one seeded default, CSV import/export.

## Does this fit the app's rules?

The app's standing rule is "never picks exercises for you" (`07_SMART_TRENDS.md`). This feature stays on the right side of that line **only if kept as a sorter, not a scheduler**: it surfaces structure (which movement patterns exist, which lifts satisfy each one, which patterns haven't been trained recently) and the user makes every actual choice — which pattern to train today, which specific lift from the pool, when to log it. It never auto-assigns a lift, never nags to finish, never auto-completes on its own judgment. Language throughout should match the primed-lifts row: "here's what fits and hasn't been hit," never "you should."

## New tagging dimension: `MovementPattern`

A third exercise-tag dimension, parallel to `ExerciseCategory` (body part) and `ExerciseType` (equipment) — multi-valued per exercise, same storage pattern (comma-joined column, e.g. `movement_patterns`).

**Main patterns:** Squat, Hinge, Horizontal Push, Vertical Push, Horizontal Pull, Vertical Pull.
**Accessory patterns:** Quad/Glute, Hamstring/Glute, Adductor/Abductor, Core, Shoulder Prehab, Arms/Aesthetic.

Most of the ~75-exercise seeded library already maps cleanly onto these (Back Squat/Front Squat/Hack Squat/Smith Machine Squat → Squat; Barbell Row/Seated Cable Row/T-Bar Row/Dumbbell Row → Horizontal Pull; etc.) — this is mostly tagging existing rows, not adding new ones. A few named in the source PDF aren't seeded yet and should be added: Trap Bar Deadlift, Landmine Press, Cable Pull-Through, Pallof Press, Straight-Arm Cable Pulldown, Glute Bridge Machine.

Editable the same way categories/equipment tags already are (a third `Wrap` of `FilterChip`s in `AddExerciseSheet`), **plus** bulk-editable via CSV import (below) — CSV is the primary path for setting this up wholesale; manual per-exercise editing is for one-off fixes.

## CSV import — two simple fixed formats, not table auto-detection

Explicitly **not** attempting to detect arbitrary table shapes in an uploaded file — that's a real parsing-robustness problem (ambiguous edges, merged cells, inconsistent spreadsheet exports) for very little benefit over just defining two small, documented, plain-CSV formats. Deterministic, testable, and still trivially shareable/editable in any spreadsheet tool.

**1. Pools CSV** — one column per pattern, cells below list the exercises that belong to it:
```
Squat Pattern,Hinge Pattern,Horizontal Push,Vertical Push,Horizontal Pull,Vertical Pull
Back Squat,Conventional Deadlift,Barbell Bench Press,Overhead Press,Barbell Row,Lat Pulldown
Front Squat,Trap Bar Deadlift,Dumbbell Bench Press,Machine Shoulder Press,Seated Cable Row,Assisted Pull-Up Machine
Hack Squat Machine,Romanian Deadlift,Machine Chest Press,Landmine Press,Chest-Supported Row,Straight-Arm Pulldown
Smith Machine Squat,,Incline Bench,,Single-Arm DB Row,
```
Header row = pattern names (must match `MovementPattern` labels); columns are ragged (ply with blank cells), each non-blank cell below the header = one exercise name to tag with that column's pattern.

**2. Rotation CSV** — one row per day, one column per pattern-slot that day:
```
Day,Slot 1,Slot 2,Slot 3
1,Squat Pattern,Adductor / Abductor,
2,Horizontal Push,Vertical Pull,Core
3,Hinge Pattern,Hamstring / Glute,
```
Becomes one saved `WorkoutTemplate` (see data model below). **Template name comes from the filename** (minus extension), editable after import — avoids needing a name field in the CSV itself.

**Matching + review step (import safety net):** on import, match each named exercise case-insensitively against the existing library first. Before committing anything, show a review screen: matched exercises (tag will be added), unmatched names (will be created as new custom exercises unless the user re-points them at an existing one — catches typos/naming variants like "Conventional deadlift" vs. the seeded "Deadlift" without silently creating a duplicate). Nothing writes to the DB until the user confirms the review screen.

**Export**, mirroring the same two formats, so a template/pool set can be pulled into a spreadsheet, edited, and re-imported — and shared with someone else as a plain file, per the user's own point ("this would also mean people can share things, sounds nice").

## Data model — revised (day-first, no stored slot-completion table)

- `Exercise.patterns: List<MovementPattern>` — implemented in phase 1.
- `workout_templates` (id, name, is_default, created). Exactly one template is seeded by default (matching the source PDF's Example Week), marked `is_default = 1`. Multi-template switching UI is phase 3/Settings; the data model already supports more than one row.
- `workout_template_days` (id, template_id, day_order, day_label, patterns — comma-joined `MovementPattern` list for that day's slots, e.g. Day 2 = `horizontalPush,verticalPull,core`).
- `planned_sessions` (id, template_day_id, date, started_at, completed_at nullable, status: `active` \| `completed` \| `aborted`, notes nullable). **One active row at a time.**

**No `planned_session_slots` table.** A day's slots are read directly off `workout_template_days.patterns` — nothing separate to store. What's "been done" for a slot is **derived live**, not written at log time: any `lift_sessions` row logged on the same calendar date as the `planned_sessions.date`, whose exercise carries that slot's pattern, counts — regardless of which entry point logged it (FAB, or a lift's own `+`) and regardless of exact time (session start/complete timestamps are optional, only set if "Track time" is on, so date-level matching is what's actually reliable). This is what naturally allows **more than one lift to satisfy a slot** (Front Squat *and* Back Squat both show under Squat) and **one lift to satisfy more than one slot** (Clean and Jerk hitting both Hinge and Vertical Push) — both fall out of the same derivation with no special-casing, and there's no completion-hook to wire into the logging path at all. Logging a matching lift from anywhere just shows up the next time the Active Day page reloads (same `reloadSignal` pattern used everywhere else).

## Interaction model — confirmed shape (day-first)

Superseded the earlier pattern-multi-select framing — the primary path is **choosing a day from the loaded template**, not selecting patterns directly:

1. **Home card, no active session**: tap → **Day Select** screen. Lists the active template's days, each showing its label, a quick preview of its patterns (e.g. "Day 2 · Horizontal Push, Vertical Pull, Core"), and a recency cue ("5 days ago" / "Never done" — days since a `planned_sessions` row for that specific day last existed). A priority/ranking score beyond plain recency is a deliberate TBD, not blocking phase 2 — plain recency-sort is enough to start.
2. **Selecting a day** creates an `active` `planned_sessions` row (`template_day_id` = that day, `started_at` = now) and opens the **Active Day page** — the "movement set" page, the meat of this feature.
3. **Active Day page**: day label/title, an optional elapsed-time timer (display-only, computed from `started_at`, nothing gated on it), a soft progress bar (fraction of slots with ≥1 matching lift done, not a hard requirement), a free-text notes field, and one card per pattern slot showing the pattern label + `X lifts` (pool size, same wording as phase 1) + whichever lifts already match today, if any. Tapping an unfilled or partially-filled slot opens `PatternPoolScreen` (phase 1, reused as-is) → pick a lift → existing `LiftDetailScreen` → log normally. **Slots fill in whatever order, whenever, across however many trips back to the screen** — walk in, find the squat rack taken, do a machine alternative instead; the board just reflects current state on next load.
4. **Home card, active session**: turns red (`AppColors.accent`), tap jumps **straight to the Active Day page** (not back to Day Select). Shows the day name and the same soft progress bar.
5. **Leaving and resuming**: the session stays `active` regardless of navigation — log bodyweight, check a metric, whatever, then tap the (now red) Home card to resume exactly where it left off.
6. **Logging normally still works everywhere, active session or not** — a lift logged from the FAB or a lift's own `+` page is unaffected whether or not it happens to match an open slot; it only *additionally* shows up on the Active Day page if it does.
7. **Abort/Complete live on the Active Day page**, not the Home card. Abort asks for confirmation (easy to fat-finger, discards only the `planned_sessions` marker — logged lifts themselves are never touched) and returns to Day Select. Complete needs no confirmation and requires **no minimum number of filled slots** — skipping accessories because you're out of time is fine, guide not coach. Only one `active` session at a time; starting a new day while one is active isn't reachable from the UI (the Home card routes you back into the existing one instead).

## Phasing (recommended build order)

Splitting into three passes rather than one large round — this is the biggest single feature discussed so far:

1. **Pattern tags + ad-hoc pool browsing — implemented.** See "Phase 1" above.
2. **Day-first active sessions — implemented.** See "Phase 2" above.
3. **Saved templates + CSV import/export — not started.** Manual template builder as a baseline, multi-template switching (Settings), CSV import/export (pools + rotation formats, match/review step) on top, the Workouts-tab day annotation. Nice-to-have layer over phase 2, not required for it to work standalone.

## Terminology — internal vs. user-facing

To keep our own wording unambiguous while coding: internally, code/docs use `PlannedSession` / `WorkoutTemplate` / `WorkoutTemplateDay`. **User-facing copy just says "Session"** (e.g. "Session in progress," "tap to resume") — no need for the user to think in our data-model terms.

## Multiple templates — resolved

Yes, support more than one saved `WorkoutTemplate` (e.g. a "bulk" rotation and a separate "cut/deload" one) — phase 3 work (switching UI not built yet, but the data model already supports multiple rows via `workout_templates`, only one of which is `is_default` at a time). The requirement is **clear separation**, not namespacing patterns: since `MovementPattern` is a property of the exercise, not of a template, two templates referencing "Vertical Push" both mean the same underlying pool — no collision risk there. What does need to stay unambiguous is which *template* a given day came from, which `workout_template_days.template_id` already guarantees structurally.

## Workouts-tab annotation — implemented (nested grouping, not a plain suffix)

Superseded the earlier "just a `— {name}` suffix" plan once the user saw it in practice and asked for something more structured. Within each date group in the Lifts screen's Workouts tab (`_buildWorkoutsTab` in `lifts_screen.dart`), lift sessions on that date are split via `WorkoutPlanService.assignToSessions` into:

- **Ungrouped rows** (not tied to any `PlannedSession` that day, or no session exists) — rendered first, unchanged `_WorkoutRow` styling (red intensity-colored left bar).
- **Grouped-by-day sections**, one per `PlannedSession` on that date with ≥1 assigned lift (handles the same-day-multiple-sessions edge case) — a sub-header row showing the day's label (e.g. "Day 2") plus an edit icon that opens `ActiveDayScreen` in edit/view mode (above), followed by that session's matched `_WorkoutRow`s nested inside a `Container` with a left border accent (`AppColors.surfaceRaised`, distinct from each row's own red bar) to read as a visual group.

Lifts logged that date outside any plan still show in the same date group as normal (just in the ungrouped section, not hidden) — consistent with the original call that off-plan lifts shouldn't be separated out or suppressed.

## Open questions (not yet resolved, revisit before/during phase 2-3)

- **Retroactive completion** (editing a past logged session to satisfy a slot after the fact) — user was unsure what this meant in practice and asked to defer until it's an actual implementation decision, then ask again. Do not resolve preemptively; surface it as a concrete choice once phase 2's edit flow is being built.
- Exact copy for the "no active session" teaser and the active-card's quick-complete affordance — deliberately left to iterate on-device rather than lock in from a text description.
