# Screen: Metrics

Home for all the non-lift logs. Two tabs: **Overview** (the original card-per-metric layout below) and **Days**.

## Days tab — implemented
Added after real use surfaced a real gap: a mistyped bodyweight (or steps/sleep/soreness) entry had no fix path short of wiping data. Mirrors the Lifts screen's "Workouts" tab — every logged entry (bodyweight, steps, sleep, soreness; explicitly **not** cycle entries, which stay confined to their own nondescript surface) grouped by date, most recent day first, each row with an icon (balance scale for weight, footstep icon for steps, bed for sleep, flame for soreness), a value, and an edit pencil.
- **Soreness rows** collapse to **one row per day**, not one per entry — all regions logged that day show as tags on a single "Soreness (Legs) (Chest) ..." row (revised after the user pointed out one-row-per-region cluttered the list). Tapping it reopens the full `SorenessBodyMapForm` tap-the-body-map sheet, pre-set to that day (`initialDate`), so every region can be corrected part-by-part in the same familiar UI used for logging, rather than a separate single-region dialog.
- **Weight/steps/sleep rows** reuse `LogSimpleMetricForm` in a new edit mode (`editingId` + prefilled value/date) that updates the existing row in place instead of inserting a new one — `MetricsRepository.update` / `BodyweightRepository.update`, both new.
- Respects the **Hide weight numbers** setting (`06_SCREEN_settings.md`) same as everywhere else — weight rows mask to "---lb" when it's on; you can still tap through to edit (the edit form always shows the real number, since you need it to fix it).

## Overview tab — implemented (cards)
- **Steps** — `LabeledTrendChart`, 6-month cap, prediction extension on.
- **Sleep (hrs)** — `LabeledTrendChart`, 6-month cap, no prediction extension (not one of the "things with predictions" yet).
- **Soreness** — replaced the trend chart with a small non-interactive body-heatmap preview (front + back side by side) showing each region's most recent 0-5 level; tapping the card opens the same body-map logging sheet used from the FAB. See `00_UX_DESIGN.md` "Soreness body map."

### Resolved — Metrics soreness preview refresh bug
Was a real bug, not a timing illusion: `MetricsRepository.getByType` ordered only by `date DESC`, with no tiebreaker for multiple same-day entries. Logging soreness twice in one day (e.g. morning + evening — the user's actual pattern, since their DOMS often peaks ~36h post-training and can meaningfully shift within a day) meant SQLite fell back to insertion order for the tie, so the **first** entry of the day kept winning over a later same-day correction, until the calendar date rolled over. Fixed with `orderBy: 'date DESC, logged_at DESC, id DESC'`. This wasn't just a display glitch — `ReadinessEngine.computeMuscleReadiness`'s soreness factor reads through the same `getLatest()` path, so the readiness compass had been silently using stale same-day soreness too.

**Multiple entries per day: kept, not collapsed to one-per-day-overwrite.** Discussed since it's real DOMS-timing signal, not just data clutter — the fix above makes "most recent entry" reliably mean the truly latest one, which is all the compass/preview need (they want "how sore right now," not an intra-day time series). No need to average or retain every same-day point for that purpose; the Days tab (above) already lets old same-day entries be corrected individually if needed.

### Soreness sub-splitting — implemented
The original 5 broad categories (core/back/arms/legs/chest) lumped together muscles that genuinely different lift patterns train — e.g. "Back" mixed pulldown/pull-up soreness (lats, upper back) with deadlift/good-morning soreness (erectors, lower back). Went finer, but **by common lift-pattern grouping, not full 23-`Muscle` anatomy** — the user's explicit concern was tap-precision/decision fatigue causing fall-off at full granularity, so this stops well short of that. New `SorenessRegion` enum (`14` regions, `metric_entry.dart`), each mapped to specific `Muscle` values via `MuscleMap.sorenessRegionGroups` (a parallel, finer sibling to `MuscleMap.broadGroups` — that one is untouched, still used for Training Composition and the Home status icons' recovery-window math):
- **Chest** — unchanged, still one region.
- **Core** → Abs / Obliques (straight-plank/crunch soreness vs. side-plank/twist soreness fire differently).
- **Back** → Upper Back / Lower Back.
- **Arms** → Biceps / Triceps / Shoulders / Forearms.
- **Legs** → Quads / Hamstrings / Glutes / Calves / Inner Thigh.
- Minor joint-adjacent regions (knees, tibialis, ankles, feet) fold into the nearest major region (quads/calves) rather than getting their own tap target.

Because the tap interaction is "tap wherever it's sore on the body silhouette" (not a checklist you fill out every field), more categories doesn't mean more *required* taps per log — the existing fine-grained `Muscle` tap targets in `flutter_body_heatmap` already supported this resolution, the app was just coarsely bucketing them. `SorenessBodyMapForm` now routes a tap to its `SorenessRegion` (via `MuscleMap.regionForMuscle`) instead of the old broad `ExerciseCategory`; `ReadinessEngine.computeMuscleReadiness`'s soreness-proxy step reads per-region too, so e.g. sore hamstrings no longer dampen quad readiness.

**Migration note (real data existed by the time this shipped):** old `MetricType.fromKey` has no fallback for an unrecognized key, so leftover rows under the retired 5 broad soreness keys would have crashed anything reading `metrics_log` broadly (the Days tab, notably) the next time it ran. Version-7 migration remaps old rows to one representative sub-region per old category (`soreness_core`→Abs, `soreness_back`→Upper Back, `soreness_arms`→Biceps, `soreness_legs`→Quads, `soreness_chest` unchanged) — not anatomically precise for that older history, but preserves it instead of crashing or silently dropping it. `TestDataService`'s synthetic soreness generator uses the same representative-region mapping.
- **Weight (weekly avg)** — `LabeledTrendChart`, prediction extension on, numeric axis ticks, but each plotted dot is **that week's average**, never a raw daily bodyweight reading. This is the resolved compromise from the original "don't be weight-motivated" ask — see `00_UX_DESIGN.md`.
- **Cycle** — deliberately nondescript per `00_UX_DESIGN.md`: plain "Cycle" label + calendar icon + a plain count ("N days logged"), same visual weight as other cards, no preview chart. Tap opens `CycleDetailScreen`.

## Later additions (not v1, just noted so schema/layout doesn't need rework)
- Timezone travel flag
- Weather
- Drinks/alcohol

These would follow the same `metrics_log` generic-row pattern (see `01_DATA_MODEL.md`) — new `metric_type` values, no migration needed, just new cards here.

## Open question
- Whether Fitbit-sourced metrics (steps, sleep, RHR — later phase per `07_SMART_TRENDS.md`) replace manual entry outright once connected, or coexist as "manual override always wins" — decide when Fitbit integration is actually scheduled.
