# Play Store release (started 2026-07-21)

Tracking doc for getting TerrapinLift onto the Play Store under the "Basener Studio" developer account. Not a design decision doc like the others — this is a checklist/reference so the release steps survive context resets.

## Decided
- **App name (store listing / on-device label):** TerrapinLift. The Flutter/Dart project internals (package name `terpinlift`, directory names, etc.) are unchanged — that's purely internal and never user-facing, not worth a large rename for.
- **Package name (`applicationId`):** `com.basenerstudio.terrapinlift` — set in `android/app/build.gradle.kts`, and `MainActivity.kt` moved to match (`android/app/src/main/kotlin/com/basenerstudio/terrapinlift/MainActivity.kt`). Chosen deliberately over the shorter "terpin"/"Terp" form — "Terp"/"Terps" is a University of Maryland trademark; the full animal name "Terrapin" avoids that entirely. **This cannot be changed after the first Play Store publish** — a new package name would mean publishing as a separate, unconnected app.
  - **This wasn't always the name.** The project's very first commit (2026-07-10) scaffolded under `edu.umd.terpinlift` — the default `flutter create`/Android Studio auto-fills the applicationId's "organization" segment from whatever account is signed into the IDE, not a deliberate choice; in this case that happened to be a `@umd.edu` account. It was renamed to the real `com.basenerstudio.terrapinlift` in the "First Build" commit (2026-07-18), well before any of the Play Store planning below started (2026-07-21). `edu.umd.terpinlift` doesn't appear anywhere in the current source (only in old git history) — but a build installed under that old name *before* the rename can still be sitting on a real device, since nothing after the rename ever touches it. If you ever find an install using that name, it predates this whole plan and isn't connected to anything documented here.

## Local testing vs. the real app (added 2026-07-26)
A plain `flutter run` and a real Play Store release used to produce the **exact same applicationId** — which meant a local test install and the production app were fighting over the same package slot on a device, with nothing but "remember to not let that happen" standing between them. That's exactly how a real mix-up happened once already: a local test build ended up unable to update the actual daily-driver install, and uninstalling/reinstalling risked leaving the wrong app holding real data. Fixed structurally, not by relying on anyone remembering anything:

- **`android/app/build.gradle.kts`'s `debug` build type gets its own `applicationIdSuffix = ".dev"`** — a plain `flutter run` (debug by default) now always installs as **`com.basenerstudio.terrapinlift.dev`**, a completely separate app from the real `com.basenerstudio.terrapinlift`. They can coexist on the same device indefinitely, and the dev one can be freely uninstalled/reinstalled/wiped with zero risk to the real app's data.
- **`android/app/src/debug/AndroidManifest.xml` overrides the on-device label to "TerrapinLift Dev"** (`tools:replace="android:label"`, since the base manifest already sets one) and `versionNameSuffix = "-dev"` shows in Settings/About — so the two are visually distinguishable on the home screen and in-app, not just by package name under the hood.
- **`flutter build appbundle --release` / `flutter run --release` are unaffected** — the `release` build type has no suffix, so it always builds/installs as the real `com.basenerstudio.terrapinlift`, matching whatever's live on the Play Store. Verified by inspecting both build types' merged manifests after a real build of each.
- **Net effect:** there is no longer a "remember to switch the name back before shipping" step, because there's nothing to switch — debug and release are permanently, structurally different package names. Anyone who clones this repo and runs `flutter run` locally will never collide with a real install, including future testers, not just this one incident.

**Running the `.dev` build on a specific phone:**
```bash
cd ~/Documents/GitHub/WorkOutApp/TerpinLift && flutter run -d 63040DLCH005RT
```
`63040DLCH005RT` is the device id (`adb devices` lists it) for the Pixel 10 Pro this has been tested on — swap it for whatever `adb devices` shows for a different phone, or drop `-d <id>` entirely if only one device/emulator is connected. This installs as `com.basenerstudio.terrapinlift.dev`/"TerrapinLift Dev," safe to test against (including a real Import) with zero risk to whatever's installed as the real `com.basenerstudio.terrapinlift`.
- **Contact email:** splashbudgeting@gmail.com — used in the privacy policy and as the Play Console developer contact.
- **Privacy policy:** `/PRIVACY_POLICY.md` at the repo root (this repo is public on GitHub, so a plain committed markdown file works as the "hosted" policy Play requires a URL for — see below).

## Release signing (you need to do this part yourself)
Google Play requires every release build to be cryptographically signed, and the signing password should never end up in this conversation or in shell history — so generate the keystore yourself, in your own terminal:

```bash
cd android/app
keytool -genkey -v -keystore upload-keystore.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```

`keytool` will prompt you interactively for a keystore password, a key password, and your name/org details (org: Basener Studio is fine, doesn't need to be exact). Keep the resulting `upload-keystore.jks` and its passwords somewhere safe outside the repo — if you ever lose it, recovering Play Store publishing rights to updates is possible via Google's Play App Signing support flow, but it's a hassle, not automatic.

Then create `android/key.properties` (already gitignored — see `android/.gitignore`, `key.properties`/`**/*.jks`/`**/*.keystore` are all listed there by the standard Flutter template) with:

```properties
storePassword=<the keystore password you set>
keyPassword=<the key password you set>
keyAlias=upload
storeFile=upload-keystore.jks
```

`android/app/build.gradle.kts` already reads this file and wires it into the `release` build type's signing config (falls back to debug signing if `key.properties` doesn't exist, so `flutter run --release` and CI still work without it).

## Building the release bundle
Play Store uploads want an **App Bundle** (`.aab`), not a plain APK:

```bash
flutter build appbundle --release
```

Output lands at `build/app/outputs/bundle/release/app-release.aab` — that's the file to upload in Play Console's "Production" (or "Internal testing," recommended first) release track. `/build/` is already gitignored at the repo root, so this file is never committed.

## What's still needed in Play Console (manual, interactive steps)
Roughly in the order Play Console asks for them:

1. **Create the app** — App name "TerrapinLift," default language, app/game = App, free/paid = Free (unless you want otherwise), declarations (not primarily for children, etc.).
2. **Store listing**
   - Short description (≤80 chars) and full description (≤4000 chars) — drafts below.
   - App icon (512×512) — already generated (`assets/icon/icon.png` via `flutter_launcher_icons`), just needs re-exporting at exactly 512×512 if the generated one isn't already that size.
   - Feature graphic (1024×500) — not generated yet, needs actual design work; ask if you want help drafting one.
   - Phone screenshots (at least 2, Play recommends 4-8) — capture these from a running build (`flutter run --release` on a device/emulator), no test data needed to look "real," though loading sample data first (Settings → dev mode → Load Sample Data) will make the screenshots look populated rather than empty.
   - Category: Health & Fitness. Tags/contact details (website optional, email above).
3. **Privacy policy URL** — once `PRIVACY_POLICY.md` is pushed to GitHub, use:
   `https://github.com/abasener/WorkOutApp/blob/main/PRIVACY_POLICY.md`
   (GitHub renders markdown as a normal webpage at that URL since the repo is public — no separate hosting needed. The raw text is also reachable at `https://raw.githubusercontent.com/abasener/WorkOutApp/main/PRIVACY_POLICY.md` if a form specifically wants a plain-text URL instead.)
4. **Data safety form** — answer "No data collected" across the board. Everything the app does is fully local (`sqflite`, `path_provider`) with zero analytics/ads/network SDKs in `pubspec.yaml` — see `PRIVACY_POLICY.md` for the full accounting of what's stored and why nothing leaves the device automatically.
5. **Content rating questionnaire (IARC)** — everything should be "No"/"None": no violence, no user-generated content shared with others, no user communication features, no location sharing, no gambling. Should land on "Everyone."
6. **Target audience & content** — not designed for or targeted at children; pick whatever general age range Play offers once the content rating comes back.
7. **App access** — "All functionality available without special access" (no login gate).
8. **Ads declaration** — no ads (`pubspec.yaml` has no ad SDK).
9. **Government app / COVID-19 app declarations** — No to both.
10. **Countries/regions** — your choice; "all countries" is the simplest default.
11. **Upload the `.aab`** to a release track (Internal testing first is the usual recommended path before Production) and roll out.

## Store listing copy (drafts, edit to taste)

**Short description** (70/80 chars):
> Track lifts, cardio, and recovery. All your data stays on your device.

**Full description:**
> TerrapinLift is a personal strength, cardio, and recovery tracker built for people who want their training data laid out clearly, without gamification, streaks, or a coach telling you what to do.
>
> TRACK YOUR TRAINING
> - Log lifts with sets, reps, weight, and a simple 0-10 effort scale
> - Track cardio (running, rowing, cycling, and more) with per-exercise distance units and pace
> - Build HIIT and circuit workouts with automatic or manual round timers
> - Everything logs into the same history, viewable by exercise or by day
>
> SEE YOUR RECOVERY, NOT JUST YOUR NUMBERS
> - A muscle-group readiness view shows what's recovered and ready to train
> - Soreness, sleep, and effort trends feed into that picture automatically
> - Strength trend charts and goal ranges, based on your own logged history, not a generic formula
>
> TRACK WHAT MATTERS TO YOU
> - Steps, sleep, soreness, and bodyweight, all with clear trend charts
> - Build your own custom metrics for anything else you want to track
> - Progress photos, organized by day
> - Optional menstrual cycle tracking, kept low-key and private on its own screen
>
> BUILT FOR ONE PERSON, ON ONE DEVICE
> - No account, no login, no cloud sync
> - All your data is stored locally in the app; nothing leaves your device unless you choose to export it
> - No ads, no in-app purchases, no analytics tracking you
>
> A customizable home dashboard, a Metrics tab for reviewing every non-lift stat, and full data export/import round out the app.
>
> TerrapinLift shows you what your own data says, and lets you decide what to do with it.

## Not done yet
- Feature graphic (1024×500) — needs actual design work.
- Screenshots — need a real device/emulator run to capture.
- Keystore/`key.properties` — you create these yourself (see above); not present in the repo.
- Actually pushing `PRIVACY_POLICY.md` to GitHub and creating the app entry in Play Console — both need your go-ahead/login, not done automatically.
