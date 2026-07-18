/// User-facing "reps in reserve" framing for effort — inverted from the
/// stored RPE scale (see `08_GLOSSARY_AND_SCIENCE.md`). Storage and every
/// downstream calculation (`ReadinessEngine`, `TrendEngine`, training
/// composition) keep the traditional RPE convention untouched (10 =
/// couldn't do another rep) — this is purely a display/entry-point
/// conversion. Most lifters think in "how many reps did I have left," not an
/// abstract 1-10 effort score, and the two are simple linear inverses of
/// each other, so flipping at the UI boundary is far less error-prone than
/// re-deriving every formula that already assumes the RPE direction.
///
/// **Reps-left domain is 0-10, not 1-10** — revised after real use: 0 means
/// what it sounds like ("tried one more, failed, didn't count it"), and
/// **9 and 10 both collapse to the RPE floor (1)** rather than getting their
/// own distinct RPE value. Past about 8 reps left, the user's own framing is
/// "this barely did anything, basically cardio" — there's no real
/// information in distinguishing 8 from 9 from 10 reps left, so rather than
/// force an 11-value input onto a 10-value RPE scale, the top end
/// deliberately compresses. This makes the round trip lossy at the very top
/// (editing a set originally logged as "10 left" will show back as "9") —
/// an accepted trade-off, not a bug, since 9 and 10 were never meant to mean
/// different things.
abstract class EffortDisplay {
  /// Stored RPE -> what the user sees/types (0 = truly failed, couldn't do
  /// another rep; 10 = so light it did essentially nothing).
  static double toDisplay(double rpe) => (10 - rpe).clamp(0, 10);

  /// What the user typed -> stored RPE. Reps-left 9 and 10 both clamp to the
  /// RPE floor (1) — see the class doc for why.
  static double fromDisplay(double display) => (10 - display).clamp(1, 10);
}
