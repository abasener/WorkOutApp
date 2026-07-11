# Screen: Lifts

List + detail for every tracked exercise (seeded big lifts + graduated custom movements), plus a Workouts tab for browsing what was logged by day.

## Tabs
Two tabs at the top of this screen: **Lifts** (default) and **Workouts**.

### Lifts tab — implemented
- One card per exercise: name, **category pills** (multi-tag — an exercise can carry more than one of legs/core/arms/back/chest/push/pull, rendered as small rounded pill chips; e.g. Bench = chest+push+arms, Back Squat = legs+push, Deadlift = back+legs+pull), and a **5-bar signal-style readiness indicator** on the right side near the chevron.
  - **Revised:** this readiness score now reads from the same compass as Home's "Primed for Growth" map — `ReadinessEngine.readinessForExercise` averages the per-muscle readiness across whatever muscles this exercise hits (`MuscleMap.musclesFor`), then `ReadinessEngine.toBars` maps that 0-1 score onto the existing 0-5 bar scale. No second readiness formula anymore; this was previously pure recency (`TrendEngine.readinessScore`), now fully superseded. See `07_SMART_TRENDS.md`.
- "+ Add custom movement" opens a sheet with a name field, multi-select category pills (`FilterChip`s), and an optional YouTube URL — defining the exercise here; actual set-logging still happens via the FAB.
- **Delete Exercise** (edit mode only, in the same Add/Edit sheet): confirm dialog states how many logged sessions will also be deleted (the `exercises` → `lift_sessions` foreign key cascades), since this is genuinely destructive. If deleted from within Lift detail's edit button, that screen pops itself afterward since the exercise it was showing no longer exists. Plain confirm dialog for now — the user wants a friskier randomized-math confirmation for this and other destructive actions (wipe/load test data in Settings too) as a deliberate follow-up, not built yet.
- **Explicitly deferred (user's call):** letting the user define a custom exercise's specific fine-grained muscles by tapping a body map (same interaction as soreness logging) — for now the 5 seeded lifts are "test data" for the muscle-mapping concept, and the user will just ask for help defining muscles for any real new lift they add rather than needing in-app tooling for it yet.
- **Considered and shelved for now:** category filter/sort chips on this list — makes sense once the custom-exercise list actually grows, not needed at 5 lifts.

### Workouts tab — implemented
Added so the user can find a specific logged lift without knowing which exercise it was under — groups every logged session (across all exercises) by date, most recent day first. Each row: a left-edge vertical color bar whose intensity is that session's RPE-sum relative to the single hardest session in the whole list (full accent = the hardest thing logged, fading toward the border color for easier sessions), the exercise name, a brief summary (set count + top weight, unit-aware), and a pencil icon opening the same edit sheet as the Lift detail history (see below) — session lookups resolve the exercise name via the already-loaded exercise list, no extra query per row.

## Lift detail — reorganized this round
Reordered specifically to fix "front-loaded clutter" — features had been added incrementally with no deliberate layout pass. Current order, top to bottom:

1. **Edit button** (AppBar, pencil icon) — same Add/Edit/Delete sheet as the Lifts list, updates in place.
2. **Compact stat row** (3 equal-width cards, tightened padding — `AppCard` now takes an optional `padding` override since these are mostly 1-2 lines of text and don't need the standard card padding): **Last trained**, **Last intensity** (label shortened to a single word — "Light" instead of "Recovery / light" — after the two-word version wrapped awkwardly at this width), **Readiness** with an "i" info icon (same `readiness` glossary entry as Home's muscle map) shown via `ReadinessSegmentedBar` — a new horizontal 5-segment bar, not the Lifts list's vertical `ReadinessBars`, since a compact card has no vertical room to spare and the vertical dimension of the wifi-style bars didn't carry any information here. Same compass-derived score either way (`ReadinessEngine`), just two different visual treatments for two different amounts of space.
3. **Predicted-next-e1RM card** (also tightened padding): the redesigned `RangeIndicator` (see below) — always visible, no tap-to-expand, per `00_UX_DESIGN.md` Confidence indicators.
4. **Muscles Worked (left half) + Overview (right half)**, side by side in one row (`IntrinsicHeight` so both sides match height): the front+back muscle heatmap shrunk to half its old width to make room for a plain-text overview blurb (form/safety cues — curated per seeded lift in `MuscleMap.liftOverview`, placeholder-quality copy for now, not exhaustive coaching) plus the "Watch form video" YouTube button, moved here from its old standalone spot. No embedded video player yet — deliberately deferred, see below.
5. **e1RM Trend**: `CenteredTrendChart`, full history (no 6-month cap, unlike the dashboards), prediction extension on.
6. **Goal** (implemented) — the long-arc bodyweight-ratio strength-standard target, see below. Only shown when both a bodyweight entry exists and the exercise has a standard (the 4 lifts with real published-style figures, plus Front Squat derived from Back Squat — custom exercises show nothing here).
7. **(Open slot)** for additional charts — the user floated a box-plot-style "range of weights per workout, warm-up to heaviest" idea, not committed to yet.
8. **History**: full session/set log, each showing a pencil icon to edit or delete that specific session, reps, weight (unit-aware), RPE, and session notes when present.

### Goal: bodyweight-ratio strength-standard gauge (implemented)
Deliberately a **separate, longer-arc target** from the "Predicted Next e1RM Range" box above — that one is "try for this next" (near-term, blends recent sessions); this one is "here's what a realistic long-term target looks like for this lift, given your bodyweight." Not shown in the same box on purpose so the two different time horizons don't get conflated.

- **`StrengthGoalGauge`**: a horizontal progress bar from 0 up to your best e1RM for this lift, with 5 tick marks at the Beginner/Novice/Intermediate/Advanced/Elite thresholds (`StrengthStandards`, `07_SMART_TRENDS.md`) — each tick now labeled with its target weight above and the tier abbreviation below — and a "Next: [tier] at [weight]" line below naming the very next tier to aim for (not the far ceiling) — matches the user's "guide, don't overwhelm" framing. The "your best e1RM" position isn't a raw all-time max: it applies a slow, forgiving decay (`StrengthStandards.effectiveBestE1rm`, ~10 weeks full credit then a taper toward an 85%-of-peak floor over ~9 months) so a real long layoff can show up without punishing normal life or requiring constant re-testing — see `07_SMART_TRENDS.md` for the detraining research behind it.
- **Data needed**: latest logged bodyweight (used internally only — still never shown as a raw number, per `00_UX_DESIGN.md`), gender and birth-year-derived age bucket (both new Settings fields, see `06_SCREEN_settings.md`), and the exercise's mapped standard table.
- **Explicitly out of scope this round**: personalized short-term sub-goals (a "safe next PR to aim for" tailored to the user's own recent growth rate, sitting between their current PR and this main goal) — the user wants the main-goal system proven out first; sub-goals are a deliberate follow-up, not forgotten.
- **"i" info tooltip** (`strength_goal` glossary entry) states plainly that these are commonly-cited-style approximate figures, gender/age adjusted, not a personally measured standard — same directional-generalization caveat pattern used for recovery windows and lean-mass-gain ranges elsewhere in this app.

**Category pills removed** from this screen — redundant with the Lifts list, per the user's call once they saw the page next to that list.

### Predicted-next-e1RM: `RangeIndicator` redesign
Previous version used a plain `Row(mainAxisAlignment: spaceBetween)` for the three labels, which only reads correctly when the values happen to be evenly spaced — not guaranteed once the confidence band stops being symmetric (see `07_SMART_TRENDS.md` for why today's fixed ±50lb band is a placeholder). Redesigned:
- The low↔high whisker span is inset from the card's full width by a fixed breathing-room padding (20% of the span on each side) rather than touching the edges.
- Each of the three labels (low/goal/high) is positioned via a `Stack` + `Positioned`, centered under its own point's actual pixel x-position — not assumed evenly spaced. This means an asymmetric band (goal off-center) will still line up correctly whenever the confidence calculation stops being symmetric.

### Lift overview text — 3 short icon-prefixed cues, not a paragraph
`MuscleMap.liftOverview` is `Map<String, List<LiftCue>>`, not a block of prose — after seeing it rendered, one dense paragraph read like a textbook page rather than something a coach says right before your set on a lift you already know. Each seeded lift gets exactly 3 lines, one per `CueKind`:
- **setup** (▶ icon) — starting position in a few words.
- **motion** (⇄ icon) — the range-of-motion cue, what actually moves.
- **safety** (⚠ icon, warning-colored) — the one injury/mistake worth remembering, not a full list.

Explicitly **not** meant to be final copy or exhaustive coaching — placeholder-quality content, the point of this round was proving the layout/formatting works, not writing final copy. No external links/embedded video yet (see below) — the cue lines + the existing "watch on YouTube" button are the stand-in.

### Explicitly deferred / open questions
- **Embedded YouTube player** vs. keeping the "watch on YouTube" launch button: there's a real Flutter package for in-app YouTube embedding, not yet evaluated the way `flutter_body_heatmap` was — worth checking before committing either way, since embedding is a real dependency + build-effort decision, not a free upgrade.
- **Box-plot (or similar) chart** for per-workout weight range (warm-up to heaviest) — a good idea, not scoped/committed to yet.
- **Randomized-math destructive-action confirmation** (mentioned above) — a deliberate future pass across Delete Exercise, Wipe Data, and Load Test Data, not built yet.

## Editing/deleting a logged session — implemented
`EditLiftSessionForm` (opened from either the Lift detail history or the Workouts tab) lets you change the date, edit/add/remove individual sets (reps/weight/RPE), edit notes, or delete the whole session with a confirm dialog. Sets are replaced wholesale on save (`LiftRepository.replaceSets`: delete all existing sets for that session, reinsert the edited list) rather than diffed — simpler, and fine at this data scale. Session-level fields (date, notes) update via `LiftRepository.updateSession` / `LiftSession.copyWith`.

## Known gaps / next up
- Workouts tab has no date-range filter/pagination yet — fine at current data volumes, revisit if history gets long.
