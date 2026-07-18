import 'package:flutter_test/flutter_test.dart';
import 'package:terpinlift/services/effort_display.dart';

void main() {
  group('EffortDisplay', () {
    test('true failure at both ends: RPE 10 <-> "0 reps left"', () {
      expect(EffortDisplay.toDisplay(10), 0); // stored RPE 10 (failure) -> "0 reps left"
      expect(EffortDisplay.fromDisplay(0), 10); // "0 reps left" -> stored RPE 10
    });

    test('reps-left 9 and 10 both collapse to the RPE floor (1)', () {
      expect(EffortDisplay.fromDisplay(9), 1);
      expect(EffortDisplay.fromDisplay(10), 1);
    });

    test('fromDisplay(toDisplay(rpe)) round-trips for every real stored RPE (1-10)', () {
      for (var rpe = 1.0; rpe <= 10; rpe++) {
        expect(EffortDisplay.fromDisplay(EffortDisplay.toDisplay(rpe)), rpe);
      }
    });

    test('toDisplay(1) (easiest real RPE) reads as "9 reps left", not 10 — 10 is unreachable '
        'from a real stored RPE since it collapses into 9 on the way back', () {
      expect(EffortDisplay.toDisplay(1), 9);
    });

    test('midpoint maps onto itself', () {
      expect(EffortDisplay.toDisplay(5), 5);
    });
  });
}
