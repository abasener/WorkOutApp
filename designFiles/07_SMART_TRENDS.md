# Smart Trends Engine (the "not-quite-AI" layer)

Guiding principle from the user: **the "smart" lives in the trend analysis, not in workout planning.** This app never sequences your workout or balances movement selection — you decide what to train. It only answers two things well: *are you recovered*, and *what could you lift*. Framed as a navigation system, not a coach.

Build in layers. Do not attempt layer 4 until layers 1-3 are solid and there's months of real logged data — a trained model will not beat well-tuned heuristics on this little data anyway.

## Layer 1 — Rule-based recency/rotation (implemented)
Simple recency queries: days since each lift was last trained (`TrendEngine.daysSinceLastTrained`), surfaced two ways:
- Home status cards: "X hasn't been trained in N days — looks primed" / "X was just trained — likely still recovering."
- Lifts list **readiness score**: 0-5, purely time-based (0 the day of the lift, +1/day, capped at 5; never-trained = 5). This is intentionally the crudest possible version of "readiness" — no soreness/RPE input yet, that's layer 3.

## Chart trend lines vs. the prediction box (important distinction)
The dashed trend line drawn on every chart (`LabeledTrendChart`, see `00_UX_DESIGN.md`) is **cosmetic/statistical only** — moving-average curves for weight/steps/sleep, a quadratic fit for lift e1RM. It is NOT the same thing as the "Predicted Next e1RM" box on the Lift detail page, which stays the bespoke RPE-weighted heuristic below. Don't conflate the two when reasoning about "the prediction" — the chart's dashed line is a simple trend/extrapolation; the box is the one that actually reasons about effort/recency.

## Layer 2 — e1RM-based progressive overload signal (implemented)
Every set converts to an estimated 1RM (Epley formula — see `08_GLOSSARY_AND_SCIENCE.md`). Track e1RM over time per lift, not raw weight. This is what the e1RM trend chart and the "predicted next lift" number are built from (`TrendEngine.predictNextE1rm`).

**Prediction band, current state:** the confidence range shown to the user is a **fixed ±50lb** around the goal, not yet derived from actual variance in the data — an explicit placeholder the user asked for rather than an interim guess we chose ourselves. Revisit once layer 4 (or at least a proper variance calculation from recent e1RM spread) is in place.

## Layer 3 — RPE/effort-weighted confidence
Not every set counts equally. A set logged at RPE 9-10 is a strong, high-confidence data point about current max capability; a set at RPE 3-5 (recovery/light day) is a real data point but should pull the trend/estimate less. Concretely: weight each e1RM sample's contribution to the rolling trend by a function of its RPE (near-max effort = high weight, low effort = low weight) rather than by raw recency alone. This directly solves the "I did a 30%-effort day, don't read that as a strength loss" problem the user raised.

**Implemented so far:** `predictNextE1rm` blends the last session's e1RM with the recent 5-session average, weighted by that last session's average RPE (near-max → trust the last session more; low-effort → lean on the average). `lastIntensity` classifies a session's average RPE into All-out / Normal / Recovery-light, shown on the lift detail screen. Soreness is now tracked **per body part** (core/back/arms/legs/chest, 0-5 scale — see `08_GLOSSARY_AND_SCIENCE.md`), which is the data layer 3 needs but doesn't consume yet. **Not yet implemented:** actually feeding that per-region soreness trend or RPE-trend-over-time into the readiness score — the Lifts list readiness score is still layer-1-only (pure days-since-trained).

Recovery/readiness flags at this layer combine:
- days since last session for that lift/movement pattern (layer 1)
- recent soreness trend (short 7d rolling average, see glossary re: ACWR-style windows)
- recent RPE trend (climbing RPE for the same weight/reps over time = fatigue accumulating)

Still just weighted arithmetic/exponential smoothing — no training required, but grounded in real strength-training research (RPE-to-%1RM correlation, load-monitoring literature) rather than arbitrary made-up weights. This is the layer where "look over research on soreness/lifting/speed-of-strength-change" work should get folded in as tuning for the weighting functions.

## Layer 4 — longitudinal predictive modeling (stretch goal, not scheduled)
True learned prediction (e.g. regression fit to the user's own longitudinal e1RM/RPE/soreness history rather than hand-set weights) becomes viable once there's a real multi-month dataset. Until then it's explicitly out of scope — noted here so it isn't lost, not so it gets attempted early.

## Recomposition flag (weight trend × strength trend)
Separate small heuristic, same "flag, don't fabricate precision" philosophy as everything else:
- Compare bodyweight rolling trend (28d) against e1RM rolling trend (28d) across major lifts.
- If bodyweight is flat/slightly up while e1RM is meaningfully up → surface a qualitative annotation on the weight trend view (something like "consistent with recomposition, not a stall") rather than any invented muscle-mass-gained number.
- Reference ranges for plausible lean-mass-gain rates (training-age-dependent, from commonly cited lean-gain literature — see glossary) inform what counts as "meaningful" e1RM movement for this flag, but the output stays qualitative.

## Cycle-trend flag (separate, its own light heuristic)
Once enough cycle_log + soreness/energy data exists: look for correlation between cycle phase and logged soreness/energy dips (not for "cycle syncing" prescriptions — just a "heads up, you tend to feel low around this point, that's probably why today's numbers are off" flag). Same rule-based-first approach as everything above; stays entirely within the nondescript/private Cycle surface, never bleeds into main Home cards.

## Fitbit integration (deferred, not blocking anything above)
OAuth2 personal-app registration against Fitbit's Web API is realistic for a single-user app (self-authorizing your own account doesn't need Fitbit marketplace approval). Would eventually feed steps/sleep/RHR automatically instead of manual entry. Scheduled after core logging + layers 1-3 are working; RHR explicitly out of scope per user (not manually entering it, and no urgency to automate something they don't want typed in anyway).
