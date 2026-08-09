# Workout Planner (movement-pattern session builder)

**Status: Phases 1, 2, and 3 implemented**, plus several rounds of follow-up polish (Home timer, Workouts-tab day grouping + edit/delete; descriptive day names, day readiness indicator, tap-through-to-workout, grouped-section restyle; main/accessory star, multi-template switching, friendly export/import). Sparked by a gym-plan PDF the user built in a separate chat (rotating full-body framework, organized by movement pattern — squat/hinge/horizontal-push/vertical-push/horizontal-pull/vertical-pull, plus accessory buckets). This doc captures the scope and shape agreed on before code, plus what's actually built so far — see designFiles/README.md for how these docs are used.

## Phase 1 — implemented

`MovementPattern` enum (12 values, `data/models/exercise.dart`) as a third exercise-tag dimension; `Exercise.patterns` + `exercises.movement_patterns` column (DB v8, `ALTER TABLE` + backfill migration tagging every existing seeded exercise by name, same pattern as the equipment-tags/pinned backfills). Added the 6 exercises named in the source PDF that weren't seeded yet (Trap Bar Deadlift, Landmine Press, Cable Pull-Through, Pallof Press, Straight-Arm Cable Pulldown, Glute Bridge Machine), tagged along with everything else. Manually editable via a third `FilterChip` `Wrap` in `AddExerciseSheet`.

`ReadinessEngine.computePatternRecency(exercises, allSessions)` — days since any exercise carrying a given pattern was last logged (or `null` if never), one entry per `MovementPattern`. Deliberately recency-only, not the fuller RPE/overload-trend signal `computeCategoryStatus` uses — patterns are movement categories, not muscle groups, so that slump-detection signal doesn't map cleanly onto them; "what's overdue" is genuinely the whole ask for the picker. Covered by `readiness_engine_test.dart`.

`PatternPoolScreen` (`lib/screens/planner/`) — exercises tagged with a given pattern, sorted by `ReadinessEngine.readinessForExercise` (most-ready first). Tapping an exercise pushes to its existing `LiftDetailScreen` — this screen never logs anything itself, matching "guide, not coach." Reused unchanged as the slot-drill-down screen in phase 2.

The original flat pattern-list entry screen (`WorkoutPlannerScreen`) was **retired in phase 2**, superseded by `DaySelectScreen` (day-first, see below) — its lift-count-per-pattern idea lives on as the `X lifts` text on each slot card.

## Phase 2 — implemented (day-first active sessions)

New models/repository: `WorkoutTemplate`, `WorkoutTemplateDay`, `PlannedSession`, `PlannedSessionStatus` (`data/models/workout_plan.dart`), `WorkoutPlanRepository`. DB v9 adds `workout_templates`, `workout_template_days`, `planned_sessions` and seeds one default template (`is_default = 1`, name "Rotating Full-Body") whose 5 days are the source PDF's Example Week table verbatim — so Day-based selection works immediately, no CSV import (phase 3) required first. Day 5 encodes both `squat` and `hinge` patterns (the PDF says "whichever undertrained") — both slots show, filling either or neither is fine.

**Day labels — revised (v10 migration).** Originally seeded as plain "Day 1".."Day 5"; renamed to pattern-descriptive labels (**Squat Focus**, **Push & Pull**, **Hinge Focus**, **Overhead & Rows**, **Legs & Hips**) after on-device use — "Day 3" reads as ambiguous once more than one day list is on screen at once (Day Select vs. a Workouts-tab sub-header). DB v10 migration renames the existing seeded default template's days in place (matched by `template_id` + `day_order`, since the template-builder UI that would let a user create their own template doesn't exist yet — nothing else to touch). Names are just picked, not derived from anything — a future template-builder UI (phase 3) would let a user set their own.

`WorkoutPlanService` (pure, no DB) — `matchedSessions(date, pattern, allSessions, exercisesById)` derives what's been done for a slot by filtering same-day `lift_sessions` whose exercise carries that pattern, and `progressFraction` for the soft progress bar. Covered by `workout_plan_service_test.dart`. See "Data model" below for why this replaced the originally-planned stored slot-completion table.

Two screens:
- `DaySelectScreen` — the default template's days, most-overdue-first (recency = days since a `planned_sessions` row for that day last existed), each row previewing its patterns. Tapping a day calls `startSession` and opens `ActiveDayScreen`.
  - **Recency bug — fixed.** `latestSessionPerDay` used to consider a `planned_sessions` row of **any** status, including `active`. But `_selectDay` creates that row the instant a day is tapped — before any workout activity happens — so a day that was merely glanced at (tapped into, then backed out of via the phone's hardware back rather than the explicit Abort button) left behind a dangling `active` row that read as "Done today" forever after. This is exactly why two unrelated days (e.g. "Squat Focus" and "Legs & Hips") could both show "Done today" despite only one actually being trained — whichever day got tapped second, even accidentally, picked up a same-day active row with zero real content. `latestSessionPerDay` now filters to `status = 'completed'` only, matching the same completion-based standard the Workouts tab already uses (a bare active session with no logged lifts doesn't show anything there either) — "when/if the plan was actually run," not "was this day's screen ever opened."
  - **Day readiness indicator — added.** Each row now also shows a `ReadinessBars` (the same 0-5 signal-strength widget used on the Lifts tab) next to the chevron, from `WorkoutPlanService.dayReadinessBars(day.patterns, exercises, muscleReadiness)` — the average of `ReadinessEngine.readinessForExercise` across every exercise carrying any of that day's patterns. Added because plain "N days ago" recency doesn't catch **muscle overlap between days**: just having squatted, a hinge day can still be the wrong call even though deadlift specifically has a longer recency gap, since legs/hips overlap between the two. Reuses the exact same per-muscle readiness signal already shown per-exercise elsewhere rather than inventing a second readiness model — see `07_SMART_TRENDS.md`. Covered by `workout_plan_service_test.dart`. The plain recency label stays alongside it, unchanged — this is an addition, not a replacement.
- `ActiveDayScreen` (the "movement set" page) — elapsed timer (`Timer.periodic`, display-only, computed from `started_at`), a soft `LinearProgressIndicator` (colored `AppColors.good`, not the accent red, so it doesn't read as a requirement bar), a notes `TextField` persisted to `planned_sessions.notes`, one card per pattern slot (icon flips filled/unfilled, shows `X lifts` when empty or the matched exercise name(s) when not — tapping opens `PatternPoolScreen`), and Abort (confirm dialog, logged lifts untouched, only the session marker changes) / Complete (no confirmation, no minimum slots filled) buttons.

Home card (`_buildPlannerCard` in `home_screen.dart`) now has both states: default `AppCard` styling + "Plan a session" when no active session; `AppColors.accentDim` background / `AppColors.accent` border (red) + the day's label + an elapsed-time subtitle ("`{Xh Ym}` · tap to resume", ticking via a 30s `Timer.periodic` on `HomeScreen` itself, same `started_at`-derived calculation as the Active Day page) when one exists, tapping goes straight to `ActiveDayScreen` rather than back through `DaySelectScreen`. `AppCard` gained optional `backgroundColor`/`borderColor` params to support this (defaults unchanged everywhere else it's used).

**Edit/view mode on `ActiveDayScreen`** — the same screen doubles as a view/edit page for a non-active (`completed`) session, opened from the Workouts tab (below). Branches internally on `session.status == active`: a genuinely active session keeps the ticking timer and Abort/Complete; a completed one opened for editing shows no timer (just the static "% covered" line), and the two bottom buttons become **Save changes** (persists the notes field, pops back — slots are still derived live off the same-date logged lifts, not stored, so they're never editable here) and **Delete workout** (confirm dialog, calls `WorkoutPlanRepository.deleteSession` which removes only the `planned_sessions` row — the underlying `lift_sessions` rows are untouched and simply become ungrouped, reappearing as plain rows in the Workouts tab).

**Start/End Time editing on a completed session (2026-07-17)** — the one other field a completed session's edit mode now exposes, added after a real workout's recorded duration read far shorter than it actually happened. Two time pickers (`showTimePicker`, time-of-day only — the date itself isn't editable here) seeded from the session's own `startedAt`/`completedAt`, with a live-recomputed "Duration: Xh Ym" label so adjusting either field immediately shows the effect — the point being to make "which side cut it short" obvious while fixing it, not just a blind edit. "Save changes" persists both alongside the notes field. This directly feeds `TrendEngine.workoutDurationMinutesByDate` (`05_SCREEN_metrics.md`), which now prefers a completed `PlannedSession`'s own span over summing individual lift-log Track Time windows for any date it covers.

**Not built yet:** a manual template-builder UI (a template still only comes from the one seeded default or importing a file — see "Friendly export/import" below, which supersedes the originally-planned CSV pools/rotation format with a single richer `.xlsx` shape). Multi-template switching and import/export themselves are implemented — see below.

## Phase 3 — implemented (2026-08-04): main/accessory star, multi-template switching, friendly export/import

**Main/accessory star** on each `ActiveDayScreen` slot card (`_slotCard`) — filled `Icons.star` for a "main" pattern (squat/hinge/horizontal-push/vertical-push/horizontal-pull/vertical-pull), outline `Icons.star_outline` for an accessory one (quad-glute/hamstring-glute/adductor-abductor/core/shoulder-prehab/arms-aesthetic) — so effort naturally goes to the right lift first without a new numeric score (`00_UX_DESIGN.md`'s no-gamified-score rule). No new data: `MovementPatternLabel.isMain` (`exercise.dart`) already drew exactly this line.

**Multi-template switching.** More than one `WorkoutTemplate` can now be saved (only reachable via import today, no manual builder yet) and switched between — exactly one is "active" at a time (`AppServices.activeTemplateId`, a plain `app_settings` key, same pattern as `home_widget_order`; unset falls back to `getDefaultTemplate()`, matching pre-switching behavior). `DaySelectScreen` gained a "Switch plan" AppBar action (`Icons.list_alt_outlined`) opening a picker of every saved template; only the active one's days show there and on Home's planner card. **History stays template-agnostic, unchanged** — `WorkoutPlanRepository.getAllDaysById()` already existed specifically so the Workouts tab can resolve any past session's day regardless of which template is currently active, so switching plans can never make old logged history look wrong or disappear (the motivating case: two coaches' plans loaded for the same person, switched between session to session, without one plan's history bleeding into the other).

A new `workout_template_days.active` column (default 1, migration v25) makes **importing a replacement version of a template safe for history** — the one real design wrinkle multi-template switching surfaced. A plain delete-and-recreate of a template's days on import would silently orphan any `planned_sessions.template_day_id` already pointing at an old day. Instead, `WorkoutPlanRepository.replaceTemplateDays` matches the imported file's days to the existing ones **by position**, updates each matched day **in place** (same id, new label/patterns), inserts any extra new days, and **soft-hides** (`active = 0`, never deletes) any existing day beyond what the import now defines — `getDaysForTemplate` filters to `active = 1`, `getAllDaysById` (history) stays unfiltered. Covered by `test/data/repositories/workout_plan_repository_test.dart`.

**Friendly export/import** (`lib/services/plan_export_service.dart`) — shared with HIIT's saved-routine export/import, see `12_SCREEN_hiit.md` for the full shape (name-based, one sheet per template, bold/italic formatting, native file picker, review-before-commit with a per-sheet Skip toggle — whether a sheet resolves to Add or Replace isn't a user choice, just a fact about whether that name already exists). Workout Plan's sheet layout: one row per day (bold day label), one column per pattern slot that day (`Pattern 1`, `Pattern 2`, ...), pattern text matched case-insensitively against `MovementPattern.label`; an unmatched pattern name is skipped and reported on the review sheet rather than failing the whole import. This is how a second template gets created today, pending a real manual builder UI.

## Does this fit the app's rules?

The app's standing rule is "never picks exercises for you" (`07_SMART_TRENDS.md`). This feature stays on the right side of that line **only if kept as a sorter, not a scheduler**: it surfaces structure (which movement patterns exist, which lifts satisfy each one, which patterns haven't been trained recently) and the user makes every actual choice — which pattern to train today, which specific lift from the pool, when to log it. It never auto-assigns a lift, never nags to finish, never auto-completes on its own judgment. Language throughout should match the primed-lifts row: "here's what fits and hasn't been hit," never "you should."

## New tagging dimension: `MovementPattern`

A third exercise-tag dimension, parallel to `ExerciseCategory` (body part) and `ExerciseType` (equipment) — multi-valued per exercise, same storage pattern (comma-joined column, e.g. `movement_patterns`).

**Main patterns:** Squat, Hinge, Horizontal Push, Vertical Push, Horizontal Pull, Vertical Pull.
**Accessory patterns:** Quad/Glute, Hamstring/Glute, Adductor/Abductor, Core, Shoulder Prehab, Arms/Aesthetic.

Most of the ~75-exercise seeded library already maps cleanly onto these (Back Squat/Front Squat/Hack Squat/Smith Machine Squat → Squat; Barbell Row/Seated Cable Row/T-Bar Row/Dumbbell Row → Horizontal Pull; etc.) — this is mostly tagging existing rows, not adding new ones. A few named in the source PDF aren't seeded yet and should be added: Trap Bar Deadlift, Landmine Press, Cable Pull-Through, Pallof Press, Straight-Arm Cable Pulldown, Glute Bridge Machine.

Editable the same way categories/equipment tags already are (a third `Wrap` of `FilterChip`s in `AddExerciseSheet`), **plus** bulk-editable via CSV import (below) — CSV is the primary path for setting this up wholesale; manual per-exercise editing is for one-off fixes.

## CSV import — original plan, superseded 2026-08-04

**Superseded by the friendly `.xlsx` export/import in "Phase 3" above** — same underlying goals (plain, hand-editable, name-based, match/review step before anything commits) but a single richer spreadsheet format shared with HIIT's saved routines rather than two separate fixed CSV shapes. Left below for historical context on the format's original design reasoning.

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
3. **Saved templates + export/import — implemented (2026-08-04).** See "Phase 3" above. Multi-template switching and `.xlsx` export/import (superseding the originally-planned CSV pools/rotation format) both landed; a manual template-builder UI did not — import is the only way to create a second template today.

## Terminology — internal vs. user-facing

To keep our own wording unambiguous while coding: internally, code/docs use `PlannedSession` / `WorkoutTemplate` / `WorkoutTemplateDay`. **User-facing copy just says "Session"** (e.g. "Session in progress," "tap to resume") — no need for the user to think in our data-model terms.

## Multiple templates — resolved

Yes, support more than one saved `WorkoutTemplate` (e.g. a "bulk" rotation and a separate "cut/deload" one) — phase 3 work (switching UI not built yet, but the data model already supports multiple rows via `workout_templates`, only one of which is `is_default` at a time). The requirement is **clear separation**, not namespacing patterns: since `MovementPattern` is a property of the exercise, not of a template, two templates referencing "Vertical Push" both mean the same underlying pool — no collision risk there. What does need to stay unambiguous is which *template* a given day came from, which `workout_template_days.template_id` already guarantees structurally.

## Workouts-tab annotation — implemented (nested grouping, not a plain suffix)

Superseded the earlier "just a `— {name}` suffix" plan once the user saw it in practice and asked for something more structured. Within each date group in the Lifts screen's Workouts tab (`_buildWorkoutsTab` in `lifts_screen.dart`), lift sessions on that date are split via `WorkoutPlanService.assignToSessions` into:

- **Ungrouped rows** (not tied to any `PlannedSession` that day, or no session exists) — rendered first, unchanged `_WorkoutRow` styling (intensity-colored left bar, see `03_SCREEN_lifts.md`).
- **Grouped-by-day sections**, one per `PlannedSession` on that date with ≥1 assigned lift (handles the same-day-multiple-sessions edge case) — a sub-header row showing the day's label (e.g. "Push & Pull") plus an edit icon that opens `ActiveDayScreen` in edit/view mode (above), followed by that session's matched `_WorkoutRow`s.

**Grouped-section styling — revised.** The first pass used a plain `AppColors.surfaceRaised` left border, which was barely distinguishable from the surrounding background — didn't read as a group at all. Now the whole section (sub-header + its rows) sits inside one rounded `Container` with an `AppColors.accent`-tinted background (`accent.withValues(alpha: 0.08)`) and a solid 3px `AppColors.accent` left border spanning the header and every row, while each individual `_WorkoutRow` keeps its own intensity bar untouched inside that container — the two colors read as "this row's effort" (thin, per-row) vs. "this group's membership" (thick, spans the whole block), not competing signals.

**Tap-through — revised.** First pass made tapping a grouped lift row open the workout page, which the user immediately flagged as backwards — tapping a *lift* should go to that lift's own page, tapping the *workout* (the header) should go to the workout page. Now: every `_WorkoutRow` (grouped or ungrouped, `_WorkoutRow.onTap`) opens that exercise's `LiftDetailScreen`, matching how every other lift row in the app behaves. The sub-header — day label **and** its edit icon, both now inside one `GestureDetector` covering the full row rather than just the small icon — is what opens that `PlannedSession` in `ActiveDayScreen` edit/view mode. The pencil icon on each `_WorkoutRow` is unchanged (still opens that one session's plain edit sheet).

Lifts logged that date outside any plan still show in the same date group as normal (just in the ungrouped section, not hidden) — consistent with the original call that off-plan lifts shouldn't be separated out or suppressed.

## Demo data now includes real Workout Planner sessions (2026-07-17)
`TestDataService` used to only ever write raw `lift_sessions` rows — the entire Workout Planner surface (Workouts-tab grouping above, `ActiveDayScreen`'s view/edit mode, the Workout Duration chart's planned-session-priority path in `05_SCREEN_metrics.md`) looked unused on a fresh demo load. Roughly half of synthetic gym days now also get a completed `PlannedSession` (`WorkoutPlanRepository.insertSession`, a new low-level insert that — unlike `startSession` — accepts any timestamps/status rather than always stamping "now"), rotating through the seeded default template's days in order, started ~7pm with a plausible 40-80 minute span. Reloading test data clears every prior `planned_sessions` row first (`WorkoutPlanRepository.deleteAllSessions`, new — `wipeEverythingAndReseed` deliberately doesn't touch this table, since a real user's own Workout Planner history shouldn't be silently cleared by loading test data) so old synthetic sessions don't linger alongside the fresh batch.

## Open questions (not yet resolved, revisit before/during phase 2-3)

- **Retroactive completion** (editing a past logged session to satisfy a slot after the fact) — user was unsure what this meant in practice and asked to defer until it's an actual implementation decision, then ask again. Do not resolve preemptively; surface it as a concrete choice once phase 2's edit flow is being built.
- Exact copy for the "no active session" teaser and the active-card's quick-complete affordance — deliberately left to iterate on-device rather than lock in from a text description.
