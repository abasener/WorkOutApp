import 'package:flutter_test/flutter_test.dart';
import 'package:terpinlift/services/effort_display.dart';

void main() {
  group('EffortDisplay', () {
    test('to-failure round-trips correctly at both ends of the scale', () {
      expect(EffortDisplay.toDisplay(10), 1); // stored RPE 10 (failure) -> "1 rep left"
      expect(EffortDisplay.toDisplay(1), 10); // stored RPE 1 (easy) -> "10 reps left"
    });

    test('fromDisplay is the exact inverse of toDisplay', () {
      for (var rpe = 1.0; rpe <= 10; rpe++) {
        expect(EffortDisplay.fromDisplay(EffortDisplay.toDisplay(rpe)), rpe);
      }
    });

    test('midpoint maps onto itself', () {
      expect(EffortDisplay.toDisplay(5.5), 5.5);
    });
  });
}
