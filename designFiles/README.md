# Design Files

Planning docs, kept up to date as the plan evolves (chat context gets compacted over time — these files are the durable record). The actual Flutter project lives in `TerpinLift/`.

- `00_UX_DESIGN.md` — overall vibe, display philosophy (icon → plot → words), chart conventions, units system, nav structure, privacy/notification rules.
- `01_DATA_MODEL.md` — SQLite schema (tables, columns, migration notes).
- `02_SCREEN_home.md` / `03_SCREEN_lifts.md` / `04_SCREEN_quick_log.md` / `05_SCREEN_metrics.md` / `06_SCREEN_settings.md` / `09_SCREEN_cycle_detail.md` — one doc per screen.
- `07_SMART_TRENDS.md` — the layered plan for rule-based → RPE-weighted trend analysis (the "not-quite-AI" engine). No workout-planning logic — this only judges recovery/prediction, never picks exercises for you.
- `08_GLOSSARY_AND_SCIENCE.md` — plain-language source text for in-app "i" tooltips (RPE, e1RM, etc.) plus the sports-science reasoning behind each formula.

## Status
Core app is built and running (`TerpinLift/`): logging (5 seeded lifts + custom movements, sets/sessions with RPE), Home/Lifts/Metrics/Settings screens, `LabeledTrendChart` (dots+line, dashed best-fit trend, prediction extension), week rings, lift readiness score + always-visible confidence range, Cycle detail screen (flow calendar + variability bar charts), lb/kg units toggle, export/import, and a synthetic test-data generator for reviewing trends without waiting on real data.

Still ahead: layer 3+ smart trends feeding Home (soreness/RPE-informed readiness, not just recency), muscle-group diagrams, Fitbit integration (deferred), cycle-phase correlation flag, recomposition flag, the cycle screen's metric-overlay dropdown (deliberately deferred, see `09_SCREEN_cycle_detail.md`).
