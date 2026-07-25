import 'package:flutter_test/flutter_test.dart';
import 'package:terpinlift/data/repositories/metrics_repository.dart';

void main() {
  group('MetricsRepository.decayedSorenessLevel', () {
    test('logged today (0 days elapsed) is untouched, no decay applied', () {
      expect(MetricsRepository.decayedSorenessLevel(4, 0), 4);
    });

    test('decays at the documented ~1 level per 1.5 days', () {
      expect(MetricsRepository.decayedSorenessLevel(5, 1), closeTo(4.33, 0.01));
      expect(MetricsRepository.decayedSorenessLevel(5, 3), 3);
    });

    test(
      'a max rating fully resolves to 0 within about a week, not sooner or held forever',
      () {
        expect(
          MetricsRepository.decayedSorenessLevel(5, 7),
          closeTo(0.33, 0.01),
        );
        expect(MetricsRepository.decayedSorenessLevel(5, 8), 0);
      },
    );

    test('never goes negative for a very old, unconfirmed log', () {
      expect(MetricsRepository.decayedSorenessLevel(5, 100), 0);
    });

    test(
      'a light rating (already low) hits the floor sooner than a heavy one',
      () {
        expect(MetricsRepository.decayedSorenessLevel(1, 2), 0);
      },
    );
  });
}
