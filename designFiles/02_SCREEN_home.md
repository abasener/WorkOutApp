# Screen: Home

The dashboard. First thing seen on open. Data-forward, per the icon → plot → words priority (see `00_UX_DESIGN.md`).

## Contents (top to bottom) — implemented

1. **This Week rings** — one ring per day (last 7 days): outer arc fills by % of the 10,000-step goal, inner fill lights up if a workout was logged that day. Replaced an earlier plain checkmark strip — rings read as progress, not pass/fail.
2. **Primed for Growth** — the front+back per-muscle readiness heatmap (green scale), the app's actual "compass." Moved to be the second thing shown (right after This Week) — it's the primary "what should I even look at today" signal, so it earns the prominent slot. Has an "i" info icon next to the title (`InfoTooltip(glossaryKey: 'readiness')`) explaining the contributing factors in plain language (recency with muscle-specific recovery windows, soreness, sleep, RPE trend, overload trend) without spelling out the exact formula — enough for "that makes sense, I can trust it," not enough to reverse-engineer. See `07_SMART_TRENDS.md` for the full formula and `08_GLOSSARY_AND_SCIENCE.md` for the tooltip copy. Shipped additively alongside the Status cards below, not replacing them — whether those should eventually be merged/revisited is still open.
3. **Training Split** — a 100%-stacked bar chart, one bar per workout day (rest days collapsed out, not calendar-spaced), showing that day's training weighted across body parts (legs/core/chest/arms/back) by RPE-sum. A "zoom out" view sitting above the per-lift trends — see `00_UX_DESIGN.md` "Training composition chart" for the full reasoning (why RPE-sum over the timer, multi-category attribution, color choices).
4. **Strength trend lines** — `CenteredTrendChart` (2:1 aspect) per actively-tracked lift (top 4 by recent activity), e1RM not raw weight (see `08_GLOSSARY_AND_SCIENCE.md`), capped to the last ~6 months, with the prediction extension on (last point at 75%, adaptive-degree polynomial trend continues). Tap-through to the lift's full detail isn't wired from these cards yet — only from the Lifts tab list.
5. **Status cards** — the "smart trend" widgets. Currently just the layer-1 recency flag ("X hasn't been trained in N days — looks primed" / "X was just trained — likely still recovering"), one card per flagged lift, icon + text. Fallback "All good" card when nothing's notable. Never a push notification — in-app only, every time the screen loads.
6. Bottom nav bar (shared across all screens — see `00_UX_DESIGN.md` for the 5 destinations).

## Known gaps / next up
- Status cards are still just the recency heuristic (layer 1 in `07_SMART_TRENDS.md`) — the richer signal now exists (feeding Primed for Growth) but the text-based Status cards haven't been revisited to match it. Whether/how to merge them is an open question for later, deliberately not decided yet.
- No ordering/priority rule yet for when multiple status flags are true at once — currently just lists them all.
- Strength trend cards aren't tappable through to the lift detail screen yet (only the Lifts tab list is).
- No specific "random widget" ideas queued for Home yet — noted as an open slot if/when the user thinks of one.
