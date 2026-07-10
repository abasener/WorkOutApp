# UX / Design Philosophy

## Vibe
- Dark theme, black + red accent (reference: "Analyze" screenshot mood).
- Data-forward, dashboard feel (reference: blue "Good morning Alex" app's information density and progress bars/rings) — NOT that app's color scheme, just its density/energy.
- This is a **navigation system, not a coach and not a motivation buddy**. It tells you what the data says; you decide what to do with it. Avoid gamification/score pressure (e.g. no single "86/100"-style score — see below).
- No cutting-edge tech needed. Personal, single-user, offline-first Android app.

## Core display philosophy (ruling principle for every screen)
When deciding how to show a piece of information, in priority order:
1. **Icon** — if a single glyph/icon can communicate it, use that (smallest footprint).
2. **Simple plot** — if the info is important enough to need more than an icon but a word isn't precise enough, use a small chart (sparkline, box-and-whisker, ring, bar).
3. **Words** — only when the above don't fit or the info isn't important enough to earn visual space.

Applies at two levels: a **collapsed/summary view** (icon or single headline number) that expands on tap into the **detail view** (plot, past trend, whisker range, etc.). Example: predicted-next-lift shows a big goal number by default; tapping expands into a box-and-whisker plot of the confidence range + recent trend.

**Exception learned in practice:** the lift prediction's confidence range turned out to read poorly when hidden behind a tap — it's now always shown expanded (see Confidence indicators below). Tap-to-expand is still the right default instinct elsewhere; this one case just needed to be visible up front because the range *is* the point of that card, not a detail.

## Charts (shared `LabeledTrendChart` convention — applies to basically every trend on the app)
- **Dots at every real logged data point**, connected by a solid line in the metric's accent color — never a bare line with no visible points.
- **A light dashed grey trend line** is drawn across every chart showing history, so growth/stability/decline reads at a glance even before looking at the dots. Its *shape* depends on `TrendStyle` (see next section) — no longer a single global linear-regression line for everything.
- **Prediction extension:** for charts tied to a prediction (lift e1RM, steps, bodyweight), the x-axis is widened so the last real data point sits at ~75% across, and the trend continues through the remaining 25% as "the prediction." This is a placeholder — no error region yet (see `07_SMART_TRENDS.md` layer 4) — just the trend's own extrapolation. Charts with no prediction concept yet (sleep, soreness) just show the trend across the actual data, no extension.
- **Axis ticks:** 7 evenly spaced on the x-axis (dates), 5 evenly spaced on the y-axis (values) — spaced by time/value, not snapped to exact data days.
- **History window:** dashboard charts (Home, Metrics) cap at ~6 months. A lift's own detail page shows its **entire** history, uncapped.
- **Bodyweight special case:** plotted as **one dot per week (that week's average)**, never a raw daily reading — satisfies "track the trend without being weight-motivated by an exact number." Axis still has real numeric ticks/labels; it's the *point density* that's hidden, not the scale.
- **Y-axis domain padding:** the actual logged data's min/max defines the "core" range, padded so real data occupies the center `_dataFillFraction` of vertical space (currently 0.6 — margin splits evenly above the highest point and below the lowest) — deliberately NOT stretched to also fit the trend curve or predicted value, which would compress the real data into a smaller band whenever the trend/prediction reaches further than the data itself. If the trend/prediction falls outside that data-defined range, it's clipped at the chart's own bounds rather than allowed to bleed into surrounding UI.

## Trend line math (`TrendStyle`, per metric)
Two families, chosen because a single straight-line fit reads wrong for both ends of this spectrum — noisy-but-flat metrics vs. plateauing-growth metrics:

- **`TrendStyle.movingAverage`** — weight, steps, sleep. A **trailing moving-average curve**, not a straight line: at each data point, average everything within a trailing window (see below), so the curve can visibly bend — flat for months, then sloped during a real shift (a diet change, a new gym routine), rather than one straight line dragging old behavior into the read. The **predicted segment's slope** comes from the smoothed curve's own recent trailing window (comparing its value now vs. `window` days ago), so a currently-flat metric predicts flat and a currently-shifting one predicts continued movement at roughly its recent pace — and that pace updates as new data comes in, not fixed at first calculation.
  - Window sizes (the knob controlling noise-smoothing vs. reaction speed): **sleep 30 days** (widest — day-to-day is noisy, real shifts are slow, so it should read close to flat unless there's a sustained change), **steps 21 days** (reacts a bit faster — a new gym program can plausibly shift daily steps sooner), **weight 42 days** (~6 of the already-weekly-averaged points — this is the metric where the *slope itself*, not the value, is the real signal, i.e. loss/gain pace).
- **`TrendStyle.polynomial`** — lift e1RM only. An **adaptive-degree** least-squares polynomial fit over the full history (degree 2-5), capturing "fast early gains, slowing/plateauing later" — including multiple plateaus — without hand-picking a fixed degree that might not fit a given lift's actual shape. Degree is chosen by trying 2, 3, 4, 5 in order and stopping at the **lowest degree whose R² clears a 0.92 threshold** (falls back to whichever degree fit best if none clear it) — a flat-cutoff version of the same idea AIC/BIC or cross-validation formalize, appropriate here since the data volumes are small and a simple rule is easier to reason about than proper information-criterion machinery. Degree is also capped by how much data exists (roughly 4 points per coefficient) so a short lift history can't produce an overfit high-degree squiggle. **Historical portion only** — the predicted segment does NOT extend the raw polynomial (which risks swinging wildly once extrapolated past sparse/noisy data — worse at higher degrees, this is Runge's phenomenon); instead it continues as a straight line at the curve's own tangent slope (its derivative) at the last data point. Gets the plateau-aware shape where there's real data, without a runaway curve in the part being extrapolated blind.

This is explicitly separate from the Lift detail page's "Predicted Next e1RM" box/confidence range — that's still the bespoke RPE-weighted heuristic in `TrendEngine`, untouched by this. This section only governs the dashed line drawn on charts.

## Soreness body map (replaces the old generic 1-10 soreness number)
- **Package:** `flutter_body_heatmap` (pub.dev) — pure `CustomPaint`, zero external dependencies, MIT licensed. Chosen over alternatives (`flutter_body_part_selector`, `muscle_map`, etc.) because it does continuous-intensity coloring (0.0-1.0 per muscle) rather than boolean selection, which is what a soreness *scale* needs. 23 fine-grained muscle regions, front/back views, tap callback returning the specific muscle tapped.
- **Entry scale: 0-5 flame icons (`FlameLevelPicker`), not a 1-10 number field.** Tapping flame N fills 1..N; tapping the already-filled top flame again clears to 0 — same fill-to-tap interaction as the cycle flow picker. Explicitly trades some precision for a much better, keyboard-free interface.
- **Broad categories for logging now:** the tap target is one of 5 broad regions — legs/core/chest/arms/back (same 5 as `ExerciseCategory` and the Training Composition chart) — each grouping several of the package's 23 fine-grained muscles (`MuscleMap.broadGroups`). Tapping any muscle within a group's area logs one soreness value for the whole group. Neck/head/hair/hands are unmapped (not one of the 5 tracked categories) — tapping there is a no-op.
- **Fine detail reserved for later:** the same fine-grained muscle set is already available for a more detailed soreness view down the road without needing a new package or asset — this was the point of picking a package with granular regions even though only broad taps are wired up today.
- **Timestamped, not just dated:** `metrics_log` gained a `logged_at` column (precise ISO datetime) specifically so logging soreness more than once in a day is possible and orderable — the day-granularity `date` field alone couldn't disambiguate multiple same-day entries.
- **Metrics screen preview:** a small, non-interactive version of the same heatmap shows each region's most recent level at a glance — tapping the card opens the same logging sheet. Replaces the old single soreness trend chart entirely (dev-stage breaking change, no real data existed to preserve).
- **Front + back shown side by side, always** — both the logging sheet and the Metrics preview show front and back at once (not a single view with a flip toggle), since a category can include muscles on either side (e.g. "legs" spans front quads and back hamstrings/glutes) and a flip button hid half the picture. Both views are fed the same data, so setting a category updates its color on both sides at once.
- **Body/border colors must differ from whatever surface the diagram sits on** — an early pass used the same color for the unhighlighted body silhouette as the surrounding `AppCard` background, which made highlighted muscles look like disconnected floating shapes instead of parts of a body outline. Fixed by giving the body/border their own distinct colors (`surfaceRaised` body + `textSecondary` border, `showBorder: true`) wherever the diagram sits on a card — applies to this map, the Metrics preview, and the Lift detail muscle diagram below.

## Lift muscle-highlight diagram
Static, front+back small heatmaps on the Lift detail screen showing which muscles a given lift hits — full intensity (1.0), no tap interaction, purely informational. Curated by hand for the 5 seeded lifts (`MuscleMap.liftMuscles`); custom exercises without a curated entry fall back to the muscles implied by their broad category tags. This is reference data, not derived from logged sets — "which muscles does Back Squat hit" doesn't change session to session.

**Lift chart sizing:** the e1RM charts (Home's per-lift cards, Lift detail's e1RM Trend) read as too compressed at a plain fixed height — they now use `CenteredTrendChart`, which is identical to a bare `LabeledTrendChart` (same full-width behavior as the Metrics charts) except its height is derived from a 2:1 width:height aspect ratio instead of a fixed pixel value. An earlier version also inset the chart to ~70% of the available width, centered — that read as "not full width" against the Metrics charts and was dropped; width behavior is now deliberately identical to every other chart, height is the only difference. Other charts (Metrics' steps/sleep/soreness/weight) are unaffected — revisit if they need the same taller treatment.

## Week rings ("This Week" on Home)
Replaced the plain checkmark strip: each of the last 7 days gets a ring — outer arc fills by % of the 10,000-step goal (capped at 100%), inner fill lights up if a workout was logged that day. Chosen over a pass/fail checkmark specifically to read as informative progress rather than punishment-y binary success/failure.

## Units
- All weight is stored canonically in **lb** in the database, always. A single global `WeightUnit` (lb/kg, persisted in `app_settings`) controls **display only** — every screen showing a weight goes through the shared `Units.format()` / `Units.displayValue()` helpers rather than assuming lb. Toggled from Settings.

## Training composition chart ("Training Split" on Home)
A 100%-stacked bar chart, one bar per **workout day** (not per calendar day) — showing what body parts got trained that day, weighted by effort.

- **Weighting: sum of RPE per session, not the live timer.** Timer duration would conflate actual working time with rest/walking between sets, and depends on the "track time" toggle being left on; RPE-sum is already fully populated today and is a cleaner volume-weighted-effort proxy (more sets at high RPE = more of that day's total stress). Sessions with no RPE logged contribute nothing (can't attribute a weight).
- **Multi-category exercises split evenly** across however many *body-part* tags (legs/core/chest/arms/back — push/pull excluded, they're movement patterns not body parts) the exercise carries — e.g. Bench (chest+push+arms) splits its RPE-sum between chest and arms after dropping push. This is a known simplifying assumption (not anatomically precise), with an easy fallback noted in code if it reads oddly: give the full RPE-sum to each tag instead of splitting it.
- **X-axis is workout-indexed, not calendar-spaced** — consecutive workout days sit back-to-back with rest-day gaps collapsed out entirely. Deliberately different from every other chart in the app: the point of this one is comparing workout-to-workout composition, and calendar gaps (already visible on Home's week rings and Metrics' trend charts) would just add noise here.
- **Colors:** sourced from the dataviz skill's validated categorical palette (dark-surface steps), taking the first 5 hues in their fixed CVD-safe order — blue, aqua, yellow, green, violet — deliberately skipping the palette's red slot so these categories are never visually confused with the app's one reserved red accent. Fixed mapping, never reassigned based on which categories appear on a given day: legs→blue, core→aqua, chest→yellow, arms→green, back→violet.
- Horizontally scrollable at a fixed bar width rather than history-capped — handles both a week of data and a year of data without needing an arbitrary cutoff.
- Legend (colored dot + label) always shown below the chart, per the 5-series-needs-a-legend rule; segment gaps (2px) provide the secondary encoding a same-family palette needs at this series count.
- **Visibility floor:** any category present at all (>0%) is display-bumped to at least 3% and the bar renormalized to still sum to 100% — otherwise a real-but-small sliver (e.g. 0.5%) renders under a pixel tall on a ~160px bar and reads as "missing" even though the data has it. This is a display-only adjustment in the chart widget; the stored/computed proportions in `TrainingCompositionService` are untouched.

## Explanatory tooltips ("i" info icon)
- Any term that isn't self-explanatory (RPE, e1RM, ACWR, rolling window, etc.) gets a small circled "i" next to it.
- Tap opens a short popover/bottom-sheet with a plain-language explanation (not a research paper — a sentence or two, written for the user, not a stats textbook).
- Build this as a **shared, reusable widget** early (e.g. `InfoTooltip(term: 'rpe')` pulling text from a central glossary map) since it'll be used throughout the app. See `05_GLOSSARY_AND_SCIENCE.md` for the source content.

## Navigation structure
Bottom nav, 5 destinations:

1. **Home** — the dashboard. Week rings (steps % + workout day), e1RM trend lines per lift (6-month cap), status cards (rest-day flags, "primed" flags, fallback "all good" card when nothing's notable). No push notifications for these — always just visible in-app when you open it.
2. **Lifts** — one card per tracked lift, showing category pills + a 0-5 readiness score; tapping opens that lift's detail (last-trained/intensity, always-visible confidence range, full-history e1RM trend, YouTube form link, muscle diagram later).
3. **FAB (center, quick log)** — opens a picker for what to log right now: lift set, weight, sleep, steps, soreness. **Cycle is deliberately not here** — it's only logged from its own detail screen off the Metrics tab, reached by tapping the calendar. See `04_SCREEN_quick_log.md`.
4. **Metrics** — the non-lift logs: steps, sleep, soreness, weight (weekly-avg chart), and the discreet cycle card (taps through to `09_SCREEN_cycle_detail.md`). Later: travel/timezone, weather, drinks.
5. **Settings** — units toggle (lb/kg), export/import data, wipe data / load test data (dev tools), cycle-tracking visibility toggle (future: PIN lock), admin/test mode, misc config (rolling window lengths, etc.).

## Cycle tracking privacy (v1 scope)
- Lives as a plain, nondescript card on the **Metrics** tab — same visual weight/style as any other metric card, just neutral wording ("Cycle" + calendar icon) and no explicit chart preview like Sleep might have.
- No PIN/lock in v1 — just "out of main view, not flagged as special." PIN/biometric lock is a documented future setting, not built now.

## Workout live-tracking flow (implemented, in a lighter form than originally planned)
- Opening the Log Lift form silently captures a wall-clock "opened at" timestamp — no visible countdown/stopwatch, no rest-state buttons to tap through. The user explicitly doesn't want to feel timed/gamified into rushing rest.
- Hitting "Done" captures the completion timestamp and stores both on the session. Backgrounding the *app* (switching to music, turning off the screen) doesn't break this, since it's wall-clock timestamps, not a running UI timer — the only failure case is the OS killing the process outright while backgrounded, which is an accepted v1 limitation, not engineered around.
- Dismissing the sheet without hitting "Done" simply discards it — nothing is written, which is the natural "abort" behavior.
- A **"Track time" toggle** (default ON) sits in the Log Lift form itself, in case the user forgets to open the form promptly and the timestamp would be misleading — turning it off logs the sets with no start/complete time on that session, not a global setting.
- Per-set timestamps (`set_started_at`/`set_completed_at`) remain in the schema for later rest-interval-based fatigue modeling, but aren't populated yet — only session-level start/complete are captured in this round.

## Confidence indicators
- Predicted-lift numbers are NOT bare point estimates. The confidence range (`RangeIndicator`) is **always shown**, not hidden behind a tap — an error-bar-style line from low to high with a bigger dot at the goal/expected value, numeric labels at all three points. (Originally this used tap-to-expand like other detail views; that read poorly in practice since the range itself is the point of the card, not incidental detail.)
- Band width is currently a **fixed ±50lb** around the goal — an explicit placeholder the user asked for, pending a real error-region model (recovery-aware, growing with distance from known data) described in `07_SMART_TRENDS.md` layer 4.
- Tap-to-expand (headline number → plot on tap) is still the right default elsewhere — this is a documented exception, not a reversal of the general rule.

## Explicitly avoided
- No visible bodyweight number anywhere in the main UI — stored and used internally (e.g. lift-as-%-bodyweight, recomposition flags) but never rendered as a number the user reads directly.
- No single gamified "score." No push notifications in v1 for any smart-trend content.
- No precise "you gained X kg of muscle" claims — recomposition signals are qualitative flags only (see science doc).
