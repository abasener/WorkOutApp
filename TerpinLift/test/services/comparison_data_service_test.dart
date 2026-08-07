import 'package:flutter_test/flutter_test.dart';
import 'package:terpinlift/services/comparison_data_service.dart';

void main() {
  group('ComparisonDataService.sumPerDay', () {
    test('collapses same-day entries into one, summed', () {
      final raw = [
        ComparisonEntry(DateTime(2026, 1, 1), 3),
        ComparisonEntry(DateTime(2026, 1, 1), 2),
        ComparisonEntry(DateTime(2026, 1, 2), 5),
      ];
      final result = ComparisonDataService.sumPerDay(raw);
      expect(result, hasLength(2));
      expect(result[0].date, DateTime(2026, 1, 1));
      expect(result[0].value, 5); // 3 + 2
      expect(result[1].date, DateTime(2026, 1, 2));
      expect(result[1].value, 5);
    });

    test('a single entry per day passes through unchanged', () {
      final raw = [ComparisonEntry(DateTime(2026, 1, 1), 8.5)];
      final result = ComparisonDataService.sumPerDay(raw);
      expect(result, hasLength(1));
      expect(result.single.value, 8.5);
    });

    test('result is sorted by date regardless of input order', () {
      final raw = [
        ComparisonEntry(DateTime(2026, 1, 5), 1),
        ComparisonEntry(DateTime(2026, 1, 1), 1),
        ComparisonEntry(DateTime(2026, 1, 3), 1),
      ];
      final result = ComparisonDataService.sumPerDay(raw);
      expect(result.map((e) => e.date), [
        DateTime(2026, 1, 1),
        DateTime(2026, 1, 3),
        DateTime(2026, 1, 5),
      ]);
    });
  });

  group('ComparisonDataService.aggregateForCharts', () {
    test('numeric series still sums same-day entries', () {
      final raw = [
        ComparisonEntry(DateTime(2026, 1, 1), 3),
        ComparisonEntry(DateTime(2026, 1, 1), 2),
      ];
      final result = ComparisonDataService.aggregateForCharts(raw, false);
      expect(result, hasLength(1));
      expect(result.single.date, DateTime(2026, 1, 1));
      expect(result.single.value, 5);
    });

    test('categorical series keeps same-day entries separate, not summed — '
        'legs (0) and chest (2) on the same day stay two points, not one '
        'merged into 2 (which would collide with chest\'s own index)', () {
      final raw = [
        ComparisonEntry(DateTime(2026, 1, 1), 0), // legs
        ComparisonEntry(DateTime(2026, 1, 1), 2), // chest
      ];
      final result = ComparisonDataService.aggregateForCharts(raw, true);
      expect(result, hasLength(2));
      expect(result.map((e) => e.value), containsAll([0.0, 2.0]));
    });

    test('categorical series result is still sorted by date', () {
      final raw = [
        ComparisonEntry(DateTime(2026, 1, 5), 1),
        ComparisonEntry(DateTime(2026, 1, 1), 0),
      ];
      final result = ComparisonDataService.aggregateForCharts(raw, true);
      expect(result.map((e) => e.date), [
        DateTime(2026, 1, 1),
        DateTime(2026, 1, 5),
      ]);
    });
  });

  group('ComparisonDataService.weeklyAverage', () {
    test('averages entries within the same Mon-Sun week', () {
      // 2026-01-05 is a Monday, 2026-01-08 a Thursday — same week.
      final raw = [
        ComparisonEntry(DateTime(2026, 1, 5), 150),
        ComparisonEntry(DateTime(2026, 1, 8), 152),
      ];
      final result = ComparisonDataService.weeklyAverage(raw);
      expect(result, hasLength(1));
      expect(result.single.date, DateTime(2026, 1, 5));
      expect(result.single.value, 151);
    });

    test('entries in different weeks stay separate points', () {
      final raw = [
        ComparisonEntry(DateTime(2026, 1, 5), 150), // week of Jan 5
        ComparisonEntry(DateTime(2026, 1, 12), 148), // week of Jan 12
      ];
      final result = ComparisonDataService.weeklyAverage(raw);
      expect(result, hasLength(2));
      expect(result.map((e) => e.value), [150.0, 148.0]);
    });
  });

  group('ComparisonDataService.scatterPairs', () {
    test('one entry each on a shared date makes one pair', () {
      final a = [ComparisonEntry(DateTime(2026, 1, 1), 8)];
      final b = [ComparisonEntry(DateTime(2026, 1, 1), 40)];
      final pairs = ComparisonDataService.scatterPairs(a, b);
      expect(pairs, [(8.0, 40.0)]);
    });

    test('a date with data on only one side produces no pair', () {
      final a = [ComparisonEntry(DateTime(2026, 1, 1), 8)];
      final b = [ComparisonEntry(DateTime(2026, 1, 2), 40)];
      expect(ComparisonDataService.scatterPairs(a, b), isEmpty);
    });

    test('multiple same-day entries repeat, not merge — 2 mood logs + '
        '1 sleep log makes 2 points, sleep value repeated for each', () {
      final sleep = [ComparisonEntry(DateTime(2026, 1, 1), 8)];
      final mood = [
        ComparisonEntry(DateTime(2026, 1, 1), 3), // "good"
        ComparisonEntry(DateTime(2026, 1, 1), 2), // "normal"
      ];
      final pairs = ComparisonDataService.scatterPairs(sleep, mood);
      expect(pairs, hasLength(2));
      expect(pairs, containsAll([(8.0, 3.0), (8.0, 2.0)]));
    });

    test(
      'multiple entries on both sides produce the full cartesian product',
      () {
        final a = [
          ComparisonEntry(DateTime(2026, 1, 1), 1),
          ComparisonEntry(DateTime(2026, 1, 1), 2),
        ];
        final b = [
          ComparisonEntry(DateTime(2026, 1, 1), 10),
          ComparisonEntry(DateTime(2026, 1, 1), 20),
        ];
        final pairs = ComparisonDataService.scatterPairs(a, b);
        expect(pairs, hasLength(4));
        expect(
          pairs,
          containsAll([(1.0, 10.0), (1.0, 20.0), (2.0, 10.0), (2.0, 20.0)]),
        );
      },
    );

    test('empty input on either side produces no pairs', () {
      expect(ComparisonDataService.scatterPairs([], []), isEmpty);
      final a = [ComparisonEntry(DateTime(2026, 1, 1), 1)];
      expect(ComparisonDataService.scatterPairs(a, []), isEmpty);
    });
  });
}
