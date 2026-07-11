# Design Files

Planning docs, kept up to date as the plan evolves (chat context gets compacted over time — these files are the durable record). The actual Flutter project lives in `TerpinLift/`.

- `00_UX_DESIGN.md` — overall vibe, display philosophy (icon → plot → words), chart conventions (adaptive polynomial/moving-average trends), units system, soreness body map + lift muscle diagrams, nav structure, privacy/notification rules.
- `01_DATA_MODEL.md` — SQLite schema (tables, columns, migration notes).
- `02_SCREEN_home.md` / `03_SCREEN_lifts.md` / `04_SCREEN_quick_log.md` / `05_SCREEN_metrics.md` / `06_SCREEN_settings.md` / `09_SCREEN_cycle_detail.md` — one doc per screen.
- `07_SMART_TRENDS.md` — the layered plan for rule-based → RPE-weighted trend analysis (the "not-quite-AI" engine). No workout-planning logic — this only judges recovery/prediction, never picks exercises for you.
- `08_GLOSSARY_AND_SCIENCE.md` — plain-language source text for in-app "i" tooltips (RPE, e1RM, soreness, etc.) plus the sports-science reasoning behind each formula.

## Status
Core app is built and running (`TerpinLift/`): logging (5 seeded lifts + custom movements, sets/sessions with RPE, editable tags, per-session notes, edit/delete on any logged session), Home/Lifts/Metrics/Settings screens, a Workouts tab (Lifts screen) grouping every logged session by day with an RPE-intensity bar, adaptive trend charts (moving-average for weight/steps/sleep, degree-selected polynomial for lift e1RM), week rings, Training Split composition chart, a unified compass-derived readiness score (Lifts list + Lift detail, `ReadinessEngine`) with an always-visible confidence range, per-body-part soreness tracked via a tappable body-map diagram (`flutter_body_heatmap`, softened color scale) with the same muscle data reused for static per-lift "muscles worked" diagrams and 3-line icon-prefixed form cues, a per-muscle "Primed for Growth" readiness map on Home, a bodyweight-ratio Strength Goal gauge on Lift detail (gender + broad age-bucket adjusted, both new Settings fields), Cycle detail screen (flow calendar + variability bar charts + a metric-overlay dropdown for sleep/steps/workout days/intensity/PRs), lb/kg units toggle, backdatable quick-log entries, export/import, and a synthetic test-data generator with real narrative shape (growth/plateau/slump/rebound, DOMS-timed soreness decay, cycle-linked dips) for reviewing trends without waiting on real data.

## Known TBD (carry into next session)
- **Metrics soreness-map refresh timing** — not yet confirmed whether the small body-map preview on Metrics updates promptly after logging soreness elsewhere. Reproduce first before assuming it's a bug; see `05_SCREEN_metrics.md`.

## Still ahead
Personalized short-term sub-goals for the Strength Goal system (deliberately deferred until the main-goal gauge is proven out — see `07_SMART_TRENDS.md`). Fitbit integration (deferred), cycle-phase correlation flag, recomposition flag, and revisiting the text-based Home Status cards now that the richer "Primed for Growth" compass has already been unified into the Lifts list and Lift detail readiness scores — whether/how to bring Status in line too is an open question, deliberately not decided yet. Also: embedded YouTube player vs. launch button, a box-plot-style per-workout weight-range chart, and a randomized-math confirmation for destructive actions (delete exercise, wipe/load test data) — all explicitly deferred, see `03_SCREEN_lifts.md`.
