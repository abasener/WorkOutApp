# Screen: Cycle Detail

Reached only by tapping the nondescript Cycle card on Metrics — never surfaced on Home, no separate nav entry, no FAB quick-log option. This is the one screen in the app explicitly designed to stay out of casual view (e.g. a gym friend glancing at the phone).

## Contents — implemented
1. **Summary stats** (top, two cards side by side): average cycle length, average period length. Both computed live from flow entries via `CycleAnalysis.compute` — there's no stored period-start/end record (see `01_DATA_MODEL.md`), a period is just a run of consecutive flow>0 days.
2. **Two small bar charts** (`SimpleBarChart`), side by side in one row: period length per past cycle, and cycle length per interval — both there specifically so the user can see *variability*, not just an average.
3. **Calendar** (scrollable month view, prev/next month navigation): red dot on any day with a logged flow > 0, dot **size scales with the flow value** (0-4). Tapping any day opens a dialog with a **4-circle fill selector** (not a numeric picker) — tapping circle N fills circles 1..N and sets flow = N; tapping the currently-filled top circle again clears it back to 0. 0 itself ("logged, no bleeding") is reached only via that clear-tap, not a 5th circle.
4. **Metric-overlay dropdown** (`CycleOverlay`): None / Sleep / Steps / Workout days / Intensity (avg RPE) / PRs. Selecting one tints each day cell's background (alpha 0.15-0.6, scaled by that day's normalized value within the focused month) behind the existing flow dot, so both are visible at once rather than replacing one with the other. Recomputed whenever the overlay choice or the focused month changes.
   - Sleep/Steps: min-max normalized within the visible month.
   - Workout days: binary (day has any logged lift session).
   - Intensity: average RPE across all sets logged that day (any exercise), normalized against a max of 10.
   - PRs: a day counts if **any** exercise hit a new best e1RM that day (per-exercise running-max comparison over that exercise's full history, not just the visible month).
   - Colors reuse the same 5 categorical hues as the Training Composition chart (blue/aqua/green/yellow/violet) — deliberately distinct from the flow dots' red so the two layers never get visually confused.

## Explicitly deferred (documented, not built)
- **PIN/biometric lock** on this screen specifically — still just relies on the Metrics card being nondescript (per `00_UX_DESIGN.md`), no extra gate on the detail screen itself yet.
