# Monetization plan (notes only, not built yet)

Not for right now — the plan is: ship this round's improvements, run it past the 12+ beta testers for real-world feedback, and only start building any of this once that feedback loop is underway. This doc exists so the thinking isn't lost between now and then, not as a build spec.

## Why monetize this one at all
The user's own framing (2026-08-02): not "does this specific app need to make money," but building the general skill/practice of turning finished personal projects into income. This app is a reasonable low-risk one to practice on since it's already built and the user will keep using it either way regardless of outcome.

## Model: one-time unlock, not a subscription
A subscription implies ongoing service cost (cloud sync, hosted compute, something recurring) — this app deliberately has none of that, so charging monthly would be asking for recurring payment for something that costs nothing ongoing to provide. That also cuts against the app's own personality (`00_UX_DESIGN.md`: not a coach, not a motivation buddy, no gamification pressure) — a subscription nag fits that poorly. A one-time Play Billing purchase needs no backend at all: Google's own servers handle purchase verification and entitlement lookup, so there's no server, no account system, no database of paying users to stand up or maintain. This is a real point in favor of the model, not just a preference.

**Trial-timer vs. feature-gate:** feature-gate, not a time-limited trial. A trial needs to track "when did this install first happen" with no account/server to anchor that to — trivially reset by uninstall/reinstall on a fully local app. Feature-gating is just "is this purchased, yes/no," checked once via Play Billing's own entitlement — nothing to spoof by resetting a clock.

## What to gate — leaning toward gating insight, not logging
Initial instinct was "basic pinned lifts free, everything else (cardio, machines) paid." Reconsidered: lift/cardio logging itself is commoditized — every fitness app does sets/reps/weight — so gating *logging* mostly just frustrates a free user without showing them what's actually different about this app. The genuinely differentiated part is the readiness/smart-trends layer.

**Leaning toward:** full logging free (any lift, cardio, HIIT, custom metrics — the whole logging experience, unrestricted), with the **insights layer gated**: Primed for Growth, readiness bars/status icons, trend predictions, goal gauges. This shows a free user the complete "what does using this feel like" experience (better conversion than a crippled trial), while the paid unlock is clearly the differentiated thing, not an arbitrary lift-count wall.

**Export/Import should stay free regardless of tier.** Gating a user's ability to get their own data out reads as hostile and directly contradicts the "your data is always yours" stance already in the privacy policy — the goodwill from never locking someone out of their own data is worth more than whatever conversion pressure withholding it would buy.

## Beta tester grandfathering
Whoever tests during this free beta period should almost certainly keep full access for free forever, as thanks for testing. Mechanism: stamp a `first_launch_date` into `app_settings` on first run (cheap, should be added **before** the Play Store push described below — retrofitting this after testers already have the app installed means no record of who installed when). Anyone whose first-launch predates the eventual paywall cutover date keeps full access unconditionally.

## Pricing
One-time purchase, **$4.99–$6.99** range — fits an indie utility app in this category, and this app has more real depth (readiness modeling, planner, HIIT, custom metrics) than a lot of $5 trackers. Start toward the low end: with zero reviews/reputation yet, price is doing double duty as a trust signal. Raising price later is easy (existing buyers keep access regardless); undoing an initially-too-high price is not.

## What's expected of a paid app (and what isn't)
Less than it might seem for this category — no accounts or cloud sync expected from a $5 utility app; "no subscription, no cloud, pay once, own it forever, your data never leaves your phone" is a real differentiator against subscription-fatigue from Strava/WHOOP-style apps, and it's already the pitch. What actually matters:
- **Data safety bar goes up** once money's involved — people are far less forgiving of a bug that eats *paid-for* data than a free app's. (The Export/Import relational-integrity bug fixed 2026-07-26 is exactly the class of thing that needs to be airtight before charging.)
- **Restore purchases** — standard Play Billing plumbing, needed so a new phone doesn't lose access.
- **A real support contact** — already have one (splashbudgeting@gmail.com).

## What to build, when actually starting this
- `in_app_purchase` package + one Play Console product (one-time, non-consumable).
- Gate the insights screens/widgets behind a simple `AppServices.isPro`-style check, sourced from Billing entitlement + the grandfather-date check above.
- Update store listing copy and `PRIVACY_POLICY.md` — current copy explicitly says "no in-app purchases," which will need real editing, not just an addition.
- Purchase-restore flow, tested in Google's sandbox before going live.
- Pick and register for payout/tax setup on the developer account if not already done.

## Open questions for later
- Exact insights-vs-logging split needs a final pass once there's actual usage data — this doc is the current best guess, not a locked decision.
- Whether "Primed for Growth" specifically should have a limited free preview (e.g. see it, but not the full explanation/legend) vs. fully hidden until unlocked.
