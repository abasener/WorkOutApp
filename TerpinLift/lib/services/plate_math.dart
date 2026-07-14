/// Pure math for the barbell plate calculator (`PlateCalculatorSheet`) — no
/// UI, so it's directly testable. Plates are entered for one side only and
/// mirrored, matching how you'd actually load a bar.
abstract class PlateMath {
  static double totalWeight(double barWeight, List<double> platesOneSide) {
    final perSide = platesOneSide.fold<double>(0, (a, b) => a + b);
    return barWeight + perSide * 2;
  }
}
