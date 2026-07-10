enum WeightUnit { lb, kg }

extension WeightUnitKey on WeightUnit {
  String get key => this == WeightUnit.lb ? 'lb' : 'kg';
  static WeightUnit fromKey(String? key) => key == 'kg' ? WeightUnit.kg : WeightUnit.lb;
}

/// All weight is stored canonically in lb (see designFiles/01_DATA_MODEL.md).
/// This is the single conversion/formatting point for display — every screen
/// showing a weight should go through here rather than assuming "lb".
abstract class Units {
  static WeightUnit current = WeightUnit.lb;

  static double _lbToKg(double lb) => lb * 0.453592;

  static double displayValue(double lb) =>
      current == WeightUnit.lb ? lb : _lbToKg(lb);

  /// Inverse of [displayValue] — converts a value the user typed in the
  /// current display unit back to the canonical lb value for storage.
  static double toLb(double displayValue) =>
      current == WeightUnit.lb ? displayValue : displayValue / 0.453592;

  static String get suffix => current.key;

  static String format(double lb) => '${displayValue(lb).round()} $suffix';
}
