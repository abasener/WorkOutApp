# Glossary & Sports-Science Reference

Two purposes: (1) source content for the in-app "i" info-tooltips, written plain; (2) the research grounding behind the smart-trends formulas, so we're not inventing arbitrary math. Not a literature review — just enough to justify each formula choice and to revisit if something feels off in practice.

---

## RPE (Rate of Perceived Exertion) — 1-10 scale
**In-app tooltip (plain language draft):** "How hard that set felt, 1-10. 10 = you couldn't have done another rep. 7 = you probably had about 3 more reps in you. Lower numbers = an easier/recovery-style set. This isn't about pain, just effort."

**Background:** Adapted from the RPE scale used widely in strength-training research and autoregulation programs (Tuchscherer's RPE chart, Helms et al.'s work on RPE-based autoregulation), which is itself an adaptation of Borg's general perceived-exertion scale into a "reps in reserve" framing. There are published tables correlating RPE + reps performed to an approximate %1RM. We don't need to hardcode those exact tables day one, but they're the reference to pull from when tuning the RPE-weighting function in layer 3 of `07_SMART_TRENDS.md`.

## Soreness — 0-5 scale, per body part
**Revised:** originally a single 1-10 generic number; now 5 separate region scores (core/back/arms/legs/chest), each 0-5, entered by tapping a body-map diagram (flame icons, not a number field) rather than typing. See `00_UX_DESIGN.md` "Soreness body map" for the interaction and package details.

**In-app framing:** how sore each broad body region is today, independent of any specific lift — used to judge recovery, not to compare against a specific workout.

**Background:** Deliberately kept as a separate concept from RPE even though both are small self-report scales — RPE is per-set effort during a lift, soreness is a daily general-recovery signal (loosely related to DOMS — delayed-onset muscle soreness — literature, but this app is not attempting a rigorous DOMS model, just a self-report trend input). Splitting by body part (rather than one whole-body number) is what makes this usable as a future input to per-lift readiness scoring (`07_SMART_TRENDS.md`) — "legs are still sore, chest looks primed" needs region-level data, not a single aggregate.

## Readiness ("Primed for Growth" muscle map)
**In-app tooltip (actual copy, `Glossary._entries['readiness']`):** "How ready each muscle looks to be trained hard again, blending a few things: how long it's been since you last trained it (bigger muscle groups like legs and back get a longer recovery window than smaller ones like arms, based on typical strength-training recovery guidance), how sore that area currently is, your recent sleep, whether your effort (RPE) has been creeping up there lately, and whether your lift numbers for it have dipped against your recent average. Greener = more ready, dimmer = still recovering. It's a heuristic blend of real training-science signals, not a lab measurement of your actual muscles."

**Why this level of detail and no more:** the user explicitly wants someone reading this to think "that makes sense, I can trust it" — not have enough to reverse-engineer the exact formula. So the tooltip names every *factor* (recency, soreness, sleep, RPE trend, overload trend) and gestures at the research direction (muscle-size-dependent recovery windows), but doesn't give the recovery-hour table, the multiplier values, or the exact multiplicative combination — that detail lives in `07_SMART_TRENDS.md` and `ReadinessEngine` for us to reference, not in the app.

## Strength Goal (bodyweight-ratio standards)
**In-app tooltip (actual copy, `Glossary._entries['strength_goal']`):** "A long-term target based on how your current best lift compares to commonly cited bodyweight-ratio strength standards (e.g. squat = some multiple of bodyweight), adjusted for gender and a broad age bracket. These are directional, generalized figures — not a personally measured standard — meant to help guide steady progress, not to say what you should be able to lift."

**Background:** Approximate figures in the spirit of publicly aggregated strength-standard tables (e.g. Strength Level, ExRx, Lon Kilgore's tables) — 5 tiers (Beginner/Novice/Intermediate/Advanced/Elite) × bodyweight multiples × gender, for the 4 lifts with commonly-cited standards (squat, bench, deadlift, overhead press); Front Squat has no independently published standard and is derived as ~83% of Back Squat, a commonly cited rough ratio between the two lifts. Age is handled as a broad bucket multiplier (under-20/20s/30s/40s/50s/60+), not a smooth age-graduated formula — the shape (flat through the 20s, gradual decline through the 30s-40s, steeper after 50) loosely mirrors published age-graduated powerlifting adjustment formulas, without claiming that level of precision for an individual user. See `07_SMART_TRENDS.md` "Strength-standard Goal system" for the full tier tables and multipliers.

**Current-PR decay:** the gauge's marker isn't a naive all-time max — it applies a slow, forgiving taper (`StrengthStandards.effectiveBestE1rm`) grounded in detraining research showing strength holds for months after a peak in trained lifters and doesn't fully vanish even after a real layoff (retained "muscle memory" makes it faster to regain than it was to build). No decay for ~10 weeks after the PR, then a slow linear taper over ~9 months to a floor of 85% of the peak — never written to zero. Deliberately kept as a single plain number, not a visible confidence range; see `07_SMART_TRENDS.md` for what was considered and explicitly rejected (a consistency-weighted version, cross-lift decay dampening, age/gender-adjusted decay rate). The same decay function is reused as-is (unit-agnostic) for bodyweight movements' rep counts below.

**Strength Goal — bodyweight movements (rep-count standards):** `ExerciseType.bodyweight` lifts (Pull Up, Push Up) don't fit a bodyweight-ratio-of-load table — published standards for these are flat rep counts (e.g. "Beginner: 1-3 pull-ups, Elite: 20+"). `BodyweightRepStandards` is a separate, smaller table in that shape, same 5-tier/gender/age-bucket pattern, plugged into the same `StrengthGoalGauge` widget with a rep-count formatter instead of a weight one. The gauge's current-position marker only counts **plain-bodyweight** sets (no assistance, no added weight) — an assisted or weighted PR isn't comparable to the published unassisted numbers this table is based on, even though it still counts toward the Predicted Next box. **In-app tooltip for this case** (`Glossary._entries['strength_goal_bodyweight']`): "A long-term target based on your best plain-bodyweight rep count (no assistance, no added weight) against commonly cited rep-count standards for this movement, adjusted for gender and a broad age bracket. Assisted or weighted sets still count toward your Predicted Next range above, just not this rep-standard ladder — it's meant to stay comparable to the published numbers it's based on."

**e1RM for bodyweight movements:** `LiftSet.weight` for these lifts is the *signed added/assisted load* (negative/0/positive), not a total, so plain Epley (`weight × (1 + reps/30)`) breaks down at 0 or negative weight — it would read a flawless 15-rep bodyweight set as "0 strength." `SessionWithSets.bodyweightAdjustedBestE1rm(bodyweightLb)` fixes this by feeding Epley the *total* load actually moved (`bodyweightLb + addedLoad`) instead, which stays positive and monotonic across the whole assisted → bodyweight → weighted range — the same trick real fitness apps use for weighted/assisted pull-ups and dips. `TrendEngine.predictNextE1rm` takes an optional value-selector so this is a substitution at the call site, not a different prediction algorithm.

## e1RM (estimated one-rep max)
**In-app tooltip (plain language draft):** "An estimate of your max single-rep lift, calculated from whatever reps/weight you actually did. Lets a 5-rep set and a 3-rep set at different weights compare fairly on the same scale."

**Background / formula options:**
- **Epley formula:** `e1RM = weight × (1 + reps / 30)`
- **Brzycki formula:** `e1RM = weight × 36 / (37 − reps)`

Both are long-established, widely used approximations in strength training (accuracy degrades above ~10-12 reps, which is fine here since the tracked lifts are low-rep compound movements). Pick one as default (Epley is the more commonly used, simpler one) — not critical which, just be consistent so trend lines are comparable over time.

**Why e1RM instead of raw weight:** this is the core mechanism that solves the user's "I went 30% effort today, don't call that a strength loss" concern — raw weight lifted isn't comparable across different rep counts or effort levels, e1RM (further adjusted by RPE-weighting, see below) is.

## RPE-weighted confidence (layer 3 mechanism)
Not a named published formula — this app's specific combination of two established ideas:
1. RPE-to-%1RM correlation tables (from the RPE/autoregulation literature above) imply how "trustworthy" a given set is as a true-max indicator.
2. Weight each session's e1RM contribution to the rolling trend line by a function of its RPE — e.g., a set at RPE 9-10 counts close to full weight, a set at RPE 3-5 counts much less. Exact weighting curve is a tuning parameter, not fixed — start simple (e.g. linear or a smooth step function off RPE) and adjust once real data shows how noisy/clean the resulting trend looks.

## Rolling windows — 7-day / 28-day (short/long)
**Background:** Modeled on the **Acute:Chronic Workload Ratio (ACWR)** concept from sports-science load-monitoring / injury-prediction research (notably Tim Gabbett's work) — acute window (commonly 7 days) captures "how has this week been," chronic window (commonly 28 days, sometimes expressed as a rolling average of 4 acute weeks) captures "what's normal for you lately." Comparing the two is how the field flags overreaching/fatigue risk without needing individualized baselines beyond the athlete's own recent history — which fits this app's "trend, not absolute number" philosophy well. Applied here to soreness, steps, and volume/e1RM trends, not just injury-risk load (the original ACWR use case), so treat the exact ratio math as a starting point to adapt rather than a rule to copy literally.

## Recomposition / lean-mass-gain plausibility ranges
**Background:** Rough monthly lean-mass-gain ceilings commonly cited in evidence-based hypertrophy literature (e.g. summarized by researchers/coaches like Alan Aragon and Eric Helms, building on longer-standing sports-nutrition research) — roughly: untrained/novice lifters can gain lean mass fastest (rough figures cited around 1-1.5% bodyweight/month), tapering substantially as training age increases. These numbers are population-level approximations, not personalized measurements (real lean-mass measurement needs DEXA/BodPod-grade tools this app doesn't have access to) — used here only to sanity-check whether a "bodyweight flat, e1RM up" pattern is *plausibly* explained by recomposition, feeding a qualitative flag rather than any claimed kg-of-muscle number. See `07_SMART_TRENDS.md` recomposition flag section.

## Cycle-phase correlation (light pattern-flagging, not cycle-syncing)
No specific formula yet — deliberately deferred until there's enough paired `cycle_log` + soreness/energy data to look for a real correlation rather than guessing at one. When revisited: simplest approach is comparing average soreness/energy metrics grouped by days-since-cycle-start, flagging if a consistent dip shows up, without prescribing any training change — purely a "here's context for why today might feel off" signal, consistent with the rest of this doc's "flag, don't prescribe" pattern.

---

## Open research questions to keep an eye on (not blocking, just worth revisiting)
- Whether the RPE-weighting curve for e1RM confidence should be linear or something steeper (e.g. quadratic dropoff below RPE 6) — decide empirically once real data exists.
- Whether 7/28-day is the right window pairing for *soreness* specifically (ACWR's original use case is training load, soreness may behave differently) — worth revisiting once a few months of soreness data exists.
