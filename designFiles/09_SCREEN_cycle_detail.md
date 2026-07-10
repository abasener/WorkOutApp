# Screen: Cycle Detail

Reached only by tapping the nondescript Cycle card on Metrics — never surfaced on Home, no separate nav entry, no FAB quick-log option. This is the one screen in the app explicitly designed to stay out of casual view (e.g. a gym friend glancing at the phone).

## Contents — implemented
1. **Summary stats** (top, two cards side by side): average cycle length, average period length. Both computed live from flow entries via `CycleAnalysis.compute` — there's no stored period-start/end record (see `01_DATA_MODEL.md`), a period is just a run of consecutive flow>0 days.
2. **Two small bar charts** (`SimpleBarChart`), side by side in one row: period length per past cycle, and cycle length per interval — both there specifically so the user can see *variability*, not just an average.
3. **Calendar** (scrollable month view, prev/next month navigation): red dot on any day with a logged flow > 0, dot **size scales with the flow value** (0-4). Tapping any day opens a dialog with a **4-circle fill selector** (not a numeric picker) — tapping circle N fills circles 1..N and sets flow = N; tapping the currently-filled top circle again clears it back to 0. 0 itself ("logged, no bleeding") is reached only via that clear-tap, not a 5th circle.

## Explicitly deferred (documented, not built)
- **Metric-overlay dropdown**: overlaying sleep duration, steps, workout days, workout intensity, and PR days onto the calendar (as dot size/color, a heatmap, or similar — exact visual TBD). The user flagged this as "useful to know about" but "a bit down the road" — deliberately not stubbed out with a non-functional dropdown in the UI, per the project's own "no half-finished implementations" rule. Revisit once the core flow-logging + stats above have been used for a while.
- **PIN/biometric lock** on this screen specifically — still just relies on the Metrics card being nondescript (per `00_UX_DESIGN.md`), no extra gate on the detail screen itself yet.
