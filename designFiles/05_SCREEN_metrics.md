# Screen: Metrics

Home for all the non-lift logs. Each metric gets a card; tap to see its history/trend (Cycle taps through to a full separate screen — see `09_SCREEN_cycle_detail.md`).

## Cards — implemented
- **Steps** — `LabeledTrendChart`, 6-month cap, prediction extension on.
- **Sleep (hrs)** — `LabeledTrendChart`, 6-month cap, no prediction extension (not one of the "things with predictions" yet).
- **Soreness** — replaced the trend chart with a small non-interactive body-heatmap preview showing each region's most recent 0-5 level; tapping the card opens the same body-map logging sheet used from the FAB. See `00_UX_DESIGN.md` "Soreness body map."
- **Weight (weekly avg)** — `LabeledTrendChart`, prediction extension on, numeric axis ticks, but each plotted dot is **that week's average**, never a raw daily bodyweight reading. This is the resolved compromise from the original "don't be weight-motivated" ask — see `00_UX_DESIGN.md`.
- **Cycle** — deliberately nondescript per `00_UX_DESIGN.md`: plain "Cycle" label + calendar icon + a plain count ("N days logged"), same visual weight as other cards, no preview chart. Tap opens `CycleDetailScreen`.

## Later additions (not v1, just noted so schema/layout doesn't need rework)
- Timezone travel flag
- Weather
- Drinks/alcohol

These would follow the same `metrics_log` generic-row pattern (see `01_DATA_MODEL.md`) — new `metric_type` values, no migration needed, just new cards here.

## Open question
- Whether Fitbit-sourced metrics (steps, sleep, RHR — later phase per `07_SMART_TRENDS.md`) replace manual entry outright once connected, or coexist as "manual override always wins" — decide when Fitbit integration is actually scheduled.
