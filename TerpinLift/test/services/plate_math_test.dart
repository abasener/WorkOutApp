import 'package:flutter_test/flutter_test.dart';
import 'package:terpinlift/services/plate_math.dart';

void main() {
  group('PlateMath.totalWeight', () {
    test('bar with no plates is just the bar weight', () {
      expect(PlateMath.totalWeight(45, []), 45);
    });

    test('plates are doubled (mirrored to the other side) then added to the bar', () {
      // 45 lb bar + (45 + 25 + 10) per side * 2 = 45 + 160 = 205
      expect(PlateMath.totalWeight(45, [45, 25, 10]), 205);
    });

    test('a single plate per side still doubles correctly', () {
      expect(PlateMath.totalWeight(20, [10]), 40);
    });
  });
}
