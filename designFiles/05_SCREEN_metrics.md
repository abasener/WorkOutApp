# Screen: Metrics

Home for all the non-lift logs. Each metric gets a card; tap to see its history/trend (Cycle taps through to a full separate screen — see `09_SCREEN_cycle_detail.md`).

## Cards — implemented
- **Steps** — `LabeledTrendChart`, 6-month cap, prediction extension on.
- **Sleep (hrs)** — `LabeledTrendChart`, 6-month cap, no prediction extension (not one of the "things with predictions" yet).
- **Soreness** — replaced the trend chart with a small non-interactive body-heatmap preview (front + back side by side) showing each region's most recent 0-5 level; tapping the card opens the same body-map logging sheet used from the FAB. See `00_UX_DESIGN.md` "Soreness body map."

### Known TBD — Metrics soreness preview refresh
Not yet confirmed whether this card's colors update correctly/promptly after logging soreness elsewhere (e.g. right after using the FAB's soreness sheet) — flagged during the last session as "might be a bug, might just be how reload timing works," not diagnosed yet. `_latestSoreness` is refreshed inside `MetricsScreen._load()`, which listens on `AppServices.reloadSignal` same as everything else — worth actually watching it happen on-device (log a soreness value, immediately check this card without navigating away and back) before assuming it's broken. Next session: reproduce first, then decide if it's a real bug (e.g. stale `getLatest` query, a missed `setState`) or just a case of not having looked at the right moment.
- **Weight (weekly avg)** — `LabeledTrendChart`, prediction extension on, numeric axis ticks, but each plotted dot is **that week's average**, never a raw daily bodyweight reading. This is the resolved compromise from the original "don't be weight-motivated" ask — see `00_UX_DESIGN.md`.
- **Cycle** — deliberately nondescript per `00_UX_DESIGN.md`: plain "Cycle" label + calendar icon + a plain count ("N days logged"), same visual weight as other cards, no preview chart. Tap opens `CycleDetailScreen`.

## Later additions (not v1, just noted so schema/layout doesn't need rework)
- Timezone travel flag
- Weather
- Drinks/alcohol

These would follow the same `metrics_log` generic-row pattern (see `01_DATA_MODEL.md`) — new `metric_type` values, no migration needed, just new cards here.

## Open question
- Whether Fitbit-sourced metrics (steps, sleep, RHR — later phase per `07_SMART_TRENDS.md`) replace manual entry outright once connected, or coexist as "manual override always wins" — decide when Fitbit integration is actually scheduled.
