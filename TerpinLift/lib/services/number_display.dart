/// Shared "show exactly as much precision as the value actually has, never
/// more" formatting — consolidates what used to be three near-identical
/// hand-rolled versions (`CustomMetric.formatValue`, and three copies inside
/// `plate_calculator_sheet.dart`). See designFiles for the rounding-bug fix
/// this was written for: `Units.format()` used to hard-round every weight to
/// a whole number regardless of what was actually logged.
abstract class NumberDisplay {
  /// Rounds to [maxDecimals] (a safety ceiling against float noise like
  /// `145.39999999999998`, not a target precision), then strips trailing
  /// zeros: `145.4000` -> `"145.4"`, `145.0000` -> `"145"`.
  static String trim(double value, {int maxDecimals = 4}) {
    final rounded = _roundTo(value, maxDecimals);
    var text = rounded.toStringAsFixed(maxDecimals);
    if (text.contains('.')) {
      text = text.replaceFirst(RegExp(r'0+$'), '');
      text = text.replaceFirst(RegExp(r'\.$'), '');
    }
    return text;
  }

  /// How many decimal places are actually needed to represent every value
  /// in [values] exactly, capped at [maxDecimals] — `[1, 2, 3]` -> `0`,
  /// `[1, 2.5, 3]` -> `1`. Used to decide a *predicted* number's display
  /// precision from its real reference inputs (e.g. the same-rep weight
  /// history a prediction was computed from) rather than whatever raw
  /// precision falls out of the averaging math that produced it.
  static int precisionNeeded(List<double> values, {int maxDecimals = 4}) {
    var maxPrecision = 0;
    for (final v in values) {
      // Doesn't cleanly reduce at any level up to the cap (e.g. a genuine
      // repeating decimal) — falls back to the full cap for this value
      // rather than silently contributing 0, which would understate how
      // much precision it actually needs.
      var neededForThisValue = maxDecimals;
      for (var p = 0; p <= maxDecimals; p++) {
        if ((v - _roundTo(v, p)).abs() < 1e-9) {
          neededForThisValue = p;
          break;
        }
      }
      if (neededForThisValue > maxPrecision) maxPrecision = neededForThisValue;
    }
    return maxPrecision;
  }

  /// Rounds [value] to exactly [decimals] places — the piece a caller
  /// needs when it wants to pin a *computed* value (e.g. a prediction) to
  /// a precision derived from [precisionNeeded] before that value gets
  /// displayed, rather than trusting whatever raw digits fell out of the
  /// math that produced it.
  static double roundTo(double value, int decimals) =>
      _roundTo(value, decimals);

  static double _roundTo(double value, int decimals) {
    final factor = _pow10(decimals);
    return (value * factor).round() / factor;
  }

  static double _pow10(int exponent) {
    var result = 1.0;
    for (var i = 0; i < exponent; i++) {
      result *= 10;
    }
    return result;
  }
}
