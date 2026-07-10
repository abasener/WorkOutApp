# Screen: Quick Log (center FAB)

Single entry point for logging anything, opened from the bottom-nav FAB from any screen. Bottom sheet, per the starter bundle's modal-bottom-sheet pattern.

## Flow — implemented
1. Tap FAB → sheet with a picker: **Lift / Weight / Sleep / Steps / Soreness**. (**Cycle was removed from this picker** — it's only logged from the calendar on its own Cycle detail screen off Metrics, since a FAB button felt like the wrong place for something meant to stay out of casual view.)
2. Each choice opens the minimal form for that type:
   - **Lift**: pick exercise (dropdown) → enter set(s): reps, weight (unit-aware, labeled with the current lb/kg setting), RPE (with the shared "i" info-tooltip) → optional notes → "add another set" or "Done." Sheet is sized to at least half the screen height (previously it just fit its content, which felt cramped).
     - **Track time toggle** (default ON) in the form header: opening the form silently captures a wall-clock timestamp; hitting "Done" captures the completion timestamp; both are stored on the session only if the toggle is on. No visible countdown/timer UI. Dismissing the sheet without hitting Done discards everything (nothing partial gets written). See `00_UX_DESIGN.md` for the full reasoning.
   - **Weight**: single numeric entry (bodyweight, unit-aware).
   - **Sleep**: numeric entry (hours; quality dimension still TBD, see `01_DATA_MODEL.md` note).
   - **Steps**: numeric entry.
   - **Soreness**: opens `SorenessBodyMapForm` instead of a number field — tap a body region on a heatmap diagram, pick a 0-5 flame level for that region, save; repeatable per region, per session. See `00_UX_DESIGN.md` "Soreness body map."
   - **Every quick-log form has a `DatePickerField`** (shared widget) defaulting to today but backdatable to any past date — capped so you can't log a future date. Added so a missed entry (e.g. logging yesterday's steps once the day is over) doesn't have to be entered as "today."
3. Submit → `AppServices.signalReload()` so Home/Lifts/Metrics reflect the new entry immediately.

## Design notes
- Every numeric/scale field that isn't self-evident gets the shared `InfoTooltip` widget (RPE, soreness).
- Keep this screen fast — it's meant to be used mid-workout or in passing, not a place to browse/read data (that's Home/Lifts/Metrics).
