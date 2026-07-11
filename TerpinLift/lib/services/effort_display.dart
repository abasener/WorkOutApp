/// User-facing "reps in reserve" framing for effort — inverted from the
/// stored RPE scale (see `08_GLOSSARY_AND_SCIENCE.md`). Storage and every
/// downstream calculation (`ReadinessEngine`, `TrendEngine.predictNextE1rm`,
/// training composition) keep the traditional RPE convention untouched
/// (10 = couldn't do another rep) — this is purely a display/entry-point
/// conversion. Most lifters think in "how many reps did I have left," not an
/// abstract 1-10 effort score, and the two are simple linear inverses of
/// each other, so flipping at the UI boundary is far less error-prone than
/// re-deriving every formula that already assumes the RPE direction.
abstract class EffortDisplay {
  /// Stored RPE -> what the user sees/types (1 = to failure, 10 = easy).
  static double toDisplay(double rpe) => 11 - rpe;

  /// What the user typed -> stored RPE.
  static double fromDisplay(double display) => 11 - display;
}
