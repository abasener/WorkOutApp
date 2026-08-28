import 'package:flutter_test/flutter_test.dart';
import 'package:terpinlift/services/number_display.dart';

void main() {
  group('NumberDisplay.trim', () {
    test('shows exactly the decimals a value has, no trailing zeros', () {
      expect(NumberDisplay.trim(145.4), '145.4');
      expect(NumberDisplay.trim(145.0), '145');
      expect(NumberDisplay.trim(45.5000), '45.5');
      expect(NumberDisplay.trim(100.5), '100.5');
    });

    test('a whole number never shows a decimal point', () {
      expect(NumberDisplay.trim(100), '100');
      expect(NumberDisplay.trim(0), '0');
    });

    test('rounds float noise away at the maxDecimals safety ceiling', () {
      expect(NumberDisplay.trim(5.300000000000001), '5.3');
    });

    test('maxDecimals caps how much precision can show, e.g. for a kg '
        'conversion', () {
      // 100 lb -> kg introduces derived decimals nobody typed; capped at 2.
      expect(NumberDisplay.trim(45.359237, maxDecimals: 2), '45.36');
    });

    test('negative values are handled the same way', () {
      expect(NumberDisplay.trim(-2.5000), '-2.5');
    });
  });

  group('NumberDisplay.precisionNeeded', () {
    test('all-whole reference values need 0 decimals', () {
      expect(NumberDisplay.precisionNeeded([1, 2, 3]), 0);
    });

    test('one decimal value in the reference list needs 1 decimal', () {
      expect(NumberDisplay.precisionNeeded([1, 2.5, 3]), 1);
    });

    test('takes the max precision across every reference value', () {
      expect(NumberDisplay.precisionNeeded([1, 2.25, 3.5]), 2);
    });

    test('empty list needs 0 decimals', () {
      expect(NumberDisplay.precisionNeeded([]), 0);
    });

    test('never exceeds maxDecimals even for a genuinely repeating value', () {
      expect(NumberDisplay.precisionNeeded([1 / 3], maxDecimals: 4), 4);
    });
  });

  group('NumberDisplay.roundTo', () {
    test('rounds to the given number of decimal places', () {
      expect(NumberDisplay.roundTo(5.333333, 1), closeTo(5.3, 1e-9));
      expect(NumberDisplay.roundTo(5.0001, 0), 5.0);
    });
  });

  group('the exact scenario from the request', () {
    test('reference weights 1, 2, 3 (all whole) -> a predicted 5.0 displays '
        'as "5", not "5.0"', () {
      const reference = [1.0, 2.0, 3.0];
      const predicted = 5.0;
      final precision = NumberDisplay.precisionNeeded(reference);
      final rounded = NumberDisplay.roundTo(predicted, precision);
      expect(NumberDisplay.trim(rounded), '5');
    });

    test(
      'reference weights 1, 2.5, 3 -> a predicted 5.333333 (from '
      'backend averaging) displays as "5.3", matching the input precision',
      () {
        const reference = [1.0, 2.5, 3.0];
        const predicted = 5.333333;
        final precision = NumberDisplay.precisionNeeded(reference);
        final rounded = NumberDisplay.roundTo(predicted, precision);
        expect(NumberDisplay.trim(rounded), '5.3');
      },
    );
  });
}
