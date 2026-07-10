# Screen: Lifts

List + detail for every tracked exercise (seeded big lifts + graduated custom movements).

## Lifts list — implemented
- One card per exercise: name, **category pills** (multi-tag — an exercise can carry more than one of legs/core/arms/back/chest/push/pull, rendered as small rounded pill chips; e.g. Bench = chest+push+arms, Back Squat = legs+push, Deadlift = back+legs+pull), and a **5-bar signal-style readiness indicator** (not text) on the right side near the chevron — bars fill left-to-right as readiness (0-5) increases, chosen over a plain "N/5" label for more visual weight at a glance.
  - Readiness is purely time-based for now (0 the day of the lift, +1 per day since, capped at 5; never-trained reads as 5/fully ready) — see `07_SMART_TRENDS.md` layer 1. Soreness/RPE-informed readiness is a later layer, not yet feeding this number.
- "+ Add custom movement" opens a sheet with a name field, multi-select category pills (`FilterChip`s), and an optional YouTube URL — defining the exercise here; actual set-logging still happens via the FAB.

## Lift detail — implemented
-1. **Muscles Worked**: static front+back small heatmap diagrams (non-interactive, full intensity) showing which muscles this lift hits — curated per seeded lift, falls back to broad-category muscles for custom exercises without a curated entry. See `00_UX_DESIGN.md` "Lift muscle-highlight diagram."
0. **Edit button** (AppBar, pencil icon): reopens the same Add/Edit sheet used from the Lifts list, pre-filled with this exercise's current name/categories/YouTube link, updating in place rather than creating a duplicate. Added after a seeded exercise's category tags were found stale (dating from before multi-category support existed) with no way to fix it short of a full data wipe — this closes that gap for both seeded and custom exercises. Category pills are also now shown directly on this screen, above the YouTube button.
1. **Header**: YouTube form-check button if a link is set. Muscle-group diagram still not built (see Known gaps).
2. **Last trained / Last intensity cards**: "N days ago" (or "Today") and a label derived from the last session's average RPE — All-out (≥9), Normal (6-8), Recovery/light (≤5), or "—" if no RPE was logged.
3. **Predicted-next-e1RM card**: always-visible `RangeIndicator` (error-bar line, fixed ±50lb band around the goal, numeric labels at low/goal/high) — no tap-to-expand here, see `00_UX_DESIGN.md` Confidence indicators.
4. **e1RM Trend**: `LabeledTrendChart`, full history (no 6-month cap, unlike the dashboards), prediction extension on.
5. **History**: full session/set log, each set showing reps, weight (unit-aware via `Units.format`), and RPE — plus a session's free-text notes (from the Log Lift form's optional notes field) shown italicized under its sets, when present.

## Known gaps / next up
- Muscle-group diagram: still not built — needs an asset source (static SVGs per category), scoped as its own task, not a v1 blocker.
- Lifts list still shows every exercise with no "recent/active only" filter — revisit if the list gets long with custom movements.
