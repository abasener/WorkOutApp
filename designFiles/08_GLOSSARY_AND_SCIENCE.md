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
