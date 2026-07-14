import 'package:flutter_test/flutter_test.dart';
import 'package:terpinlift/services/calculator_engine.dart';

void main() {
  group('CalculatorEngine', () {
    test('a single operator applies left-to-right, no precedence', () {
      final engine = CalculatorEngine();
      engine.onOperator(2, CalcOp.add); // 2 +
      final result = engine.onOperator(3, null); // = 5
      expect(result, 5);
    });

    test('chained operators each resolve against the running accumulator', () {
      final engine = CalculatorEngine();
      engine.onOperator(2, CalcOp.add); // 2 +
      engine.onOperator(3, CalcOp.multiply); // (2+3) * ... = 5, pending *
      final result = engine.onOperator(4, null); // 5 * 4 = 20
      expect(result, 20);
    });

    test('division by zero returns NaN rather than throwing', () {
      final engine = CalculatorEngine();
      engine.onOperator(5, CalcOp.divide);
      final result = engine.onOperator(0, null);
      expect(result.isNaN, isTrue);
    });

    test('clear resets the accumulator and pending operator', () {
      final engine = CalculatorEngine();
      engine.onOperator(2, CalcOp.add);
      engine.clear();
      expect(engine.accumulator, isNull);
      expect(engine.pendingOp, isNull);
      // A fresh operator press after clear behaves like a first entry.
      final result = engine.onOperator(9, null);
      expect(result, 9);
    });

    test('pressing "=" with no prior operator just returns the displayed value', () {
      final engine = CalculatorEngine();
      final result = engine.onOperator(7, null);
      expect(result, 7);
    });
  });
}
