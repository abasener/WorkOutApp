import 'package:flutter_test/flutter_test.dart';
import 'package:terpinlift/services/units.dart';

/// `Units.format` used to hard-round every weight to a whole number
/// (`.round()`) regardless of what was actually logged — this is the fix
/// for that: a real decimal like a 145.4 bodyweight entry or a 100.5 PR
/// must survive display, not just storage.
void main() {
  setUp(() {
    Units.current = WeightUnit.lb;
    Units.hideWeight = false;
  });

  group('Units.format', () {
    test('preserves a real decimal instead of rounding it away', () {
      expect(Units.format(145.4), '145.4 lb');
      expect(Units.format(100.5), '100.5 lb');
    });

    test('a whole-number weight still shows with no decimal', () {
      expect(Units.format(145.0), '145 lb');
    });

    test('kg conversion is capped at 2 decimals, not the raw conversion '
        'noise', () {
      Units.current = WeightUnit.kg;
      // 100 lb -> 45.359237 kg
      expect(Units.format(100), '45.36 kg');
    });

    test('a lb value entered as a whole number stays whole when displayed '
        'in lb, even though the same value would show decimals in kg', () {
      expect(Units.format(150), '150 lb');
    });
  });

  group('Units.formatMaskable', () {
    test('masks to a placeholder when hideWeight is on, real value '
        'otherwise', () {
      Units.hideWeight = true;
      expect(Units.formatMaskable(145.4), '--- lb');
      Units.hideWeight = false;
      expect(Units.formatMaskable(145.4), '145.4 lb');
    });
  });
}
