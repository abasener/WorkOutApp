# Screen: Settings

## Implemented
- **Profile: Gender toggle (Female/Male)** — defaults to Female (matches how this app was framed from the start), persisted in `app_settings` (`gender` key), read via `UserProfile.gender`. Feeds the bodyweight-ratio strength-standard Goal gauge on Lift detail (`07_SMART_TRENDS.md`) — not used or shown anywhere else.
- **Profile: Birth year** (plain number field, validated 1900–current year) — persisted in `app_settings` (`birth_year` key). Converted to a broad `AgeBucket` (`UserProfile.ageBucket`: under-20 / 20s / 30s / 40s / 50s / 60+) rather than an exact age, per the user's call — a bucket-based multiplier on the strength standards, not a precise age-graduated formula. Unset defaults to the 20s/reference bucket (no age adjustment) rather than blocking the Goal feature.
- **Units toggle (lb/kg)** — a pill switch; persisted in `app_settings` (`weight_unit` key). All weight is stored canonically in lb; this only controls display via the shared `Units` helper (see `00_UX_DESIGN.md`).
- **Export data** — dumps every table (including `app_settings`) to a JSON file in the app's documents folder.
- **Import data** — restores from that export file (fresh-install restore, not a smart merge).
- **Wipe Data** — confirm dialog, then deletes all logged lifts/bodyweight/metrics/cycle entries but keeps the exercise list intact.
- **Load Test Data** — confirm dialog, then fully wipes (including exercises) and generates ~2 months of synthetic history across every tracked thing (lifts with varying effort/RPE, steps, sleep, soreness, bodyweight, cycle flow) so trends/predictions can be reviewed without waiting on real data. See `TestDataService`.

## Not yet built
- **Rolling window config** — the short/long trend windows (default 7d / 28d, see `08_GLOSSARY_AND_SCIENCE.md`) aren't exposed as adjustable settings yet; still hardcoded where used.
- Cycle-tracking visibility toggle (hide the Metrics card entirely / PIN-lock it) — still just relies on the card being nondescript, per `00_UX_DESIGN.md`.
- Fitbit account connection/auth management, once that integration is scheduled.
