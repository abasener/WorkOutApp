enum CalcOp { add, subtract, multiply, divide }

extension CalcOpSymbol on CalcOp {
  String get symbol {
    switch (this) {
      case CalcOp.add:
        return '+';
      case CalcOp.subtract:
        return '−';
      case CalcOp.multiply:
        return '×';
      case CalcOp.divide:
        return '÷';
    }
  }
}

/// Pure left-to-right (no operator precedence) arithmetic engine for the
/// simple 4-function calculator tab — the same behavior as a basic physical
/// calculator, not an expression parser. No UI/state beyond the running
/// accumulator and pending operator, so it's directly testable.
class CalculatorEngine {
  double? _accumulator;
  CalcOp? _pendingOp;

  double? get accumulator => _accumulator;
  CalcOp? get pendingOp => _pendingOp;

  static double _apply(double a, double b, CalcOp op) {
    switch (op) {
      case CalcOp.add:
        return a + b;
      case CalcOp.subtract:
        return a - b;
      case CalcOp.multiply:
        return a * b;
      case CalcOp.divide:
        return b == 0 ? double.nan : a / b;
    }
  }

  /// Call when an operator (or "=", passing `null`) is pressed with
  /// whatever number is currently on screen. Resolves any operator already
  /// pending against that number, stores the new pending operator (or
  /// clears it, for "="), and returns the value that should now be shown.
  double onOperator(double displayed, CalcOp? nextOp) {
    final result = _pendingOp != null && _accumulator != null
        ? _apply(_accumulator!, displayed, _pendingOp!)
        : displayed;
    _accumulator = result;
    _pendingOp = nextOp;
    return result;
  }

  void clear() {
    _accumulator = null;
    _pendingOp = null;
  }
}
