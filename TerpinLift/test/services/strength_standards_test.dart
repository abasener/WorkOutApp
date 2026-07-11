import 'package:flutter_test/flutter_test.dart';
import 'package:terpinlift/services/strength_standards.dart';
import 'package:terpinlift/services/user_profile.dart';

void main() {
  group('StrengthStandards.hasStandard / allTargets', () {
    test('the 4 barbell lifts with published tables have standards', () {
      for (final name in ['Back Squat', 'Bench Press', 'Deadlift', 'Overhead Press']) {
        expect(StrengthStandards.hasStandard(name), isTrue, reason: name);
      }
    });

    test('Front Squat is derived from Back Squat, not independently sourced', () {
      final front = StrengthStandards.allTargets(
        exerciseName: 'Front Squat',
        bodyweightLb: 150,
        gender: Gender.male,
        ageBucket: AgeBucket.twenties,
      )!;
      final back = StrengthStandards.allTargets(
        exerciseName: 'Back Squat',
        bodyweightLb: 150,
        gender: Gender.male,
        ageBucket: AgeBucket.twenties,
      )!;
      for (final tier in StrengthTier.values) {
        expect(front[tier], closeTo(back[tier]! * 0.83, 0.01));
      }
    });

    test('an untagged/custom exercise has no standard', () {
      expect(StrengthStandards.hasStandard('Cable Woodchopper'), isFalse);
      expect(
        StrengthStandards.allTargets(
          exerciseName: 'Cable Woodchopper',
          bodyweightLb: 150,
          gender: Gender.male,
          ageBucket: AgeBucket.twenties,
        ),
        isNull,
      );
    });

    test('targets scale up with bodyweight and are gender-distinct', () {
      final targets150 = StrengthStandards.allTargets(
        exerciseName: 'Bench Press',
        bodyweightLb: 150,
        gender: Gender.male,
        ageBucket: AgeBucket.twenties,
      )!;
      final targets200 = StrengthStandards.allTargets(
        exerciseName: 'Bench Press',
        bodyweightLb: 200,
        gender: Gender.male,
        ageBucket: AgeBucket.twenties,
      )!;
      final targetsFemale = StrengthStandards.allTargets(
        exerciseName: 'Bench Press',
        bodyweightLb: 150,
        gender: Gender.female,
        ageBucket: AgeBucket.twenties,
      )!;
      expect(targets200[StrengthTier.intermediate], greaterThan(targets150[StrengthTier.intermediate]!));
      expect(targetsFemale[StrengthTier.intermediate], isNot(targets150[StrengthTier.intermediate]));
    });

    test('tiers are strictly increasing', () {
      final targets = StrengthStandards.allTargets(
        exerciseName: 'Deadlift',
        bodyweightLb: 180,
        gender: Gender.male,
        ageBucket: AgeBucket.twenties,
      )!;
      final values = StrengthTier.values.map((t) => targets[t]!).toList();
      for (var i = 1; i < values.length; i++) {
        expect(values[i], greaterThan(values[i - 1]));
      }
    });
  });

  group('StrengthStandards.currentTier / nextTier', () {
    final targets = {
      StrengthTier.beginner: 100.0,
      StrengthTier.novice: 150.0,
      StrengthTier.intermediate: 200.0,
      StrengthTier.advanced: 250.0,
      StrengthTier.elite: 300.0,
    };

    test('below Beginner threshold reads as null (no tier reached)', () {
      expect(StrengthStandards.currentTier(50, targets), isNull);
    });

    test('exactly at a threshold counts as having reached it', () {
      expect(StrengthStandards.currentTier(200, targets), StrengthTier.intermediate);
    });

    test('between two thresholds reads as the lower one', () {
      expect(StrengthStandards.currentTier(220, targets), StrengthTier.intermediate);
    });

    test('at or above Elite reads as Elite', () {
      expect(StrengthStandards.currentTier(500, targets), StrengthTier.elite);
    });

    test('nextTier steps up by one, and Elite has nowhere higher to go', () {
      expect(StrengthStandards.nextTier(null), StrengthTier.beginner);
      expect(StrengthStandards.nextTier(StrengthTier.beginner), StrengthTier.novice);
      expect(StrengthStandards.nextTier(StrengthTier.elite), StrengthTier.elite);
    });
  });

  group('StrengthStandards.effectiveBestE1rm (detraining decay)', () {
    test('no decay within the grace period', () {
      final achieved = DateTime(2026, 1, 1);
      final now = achieved.add(const Duration(days: 69));
      expect(StrengthStandards.effectiveBestE1rm(300, achieved, now), 300);
    });

    test('no decay exactly at the grace boundary', () {
      final achieved = DateTime(2026, 1, 1);
      final now = achieved.add(const Duration(days: 70));
      expect(StrengthStandards.effectiveBestE1rm(300, achieved, now), 300);
    });

    test('decays partially partway through the taper window', () {
      final achieved = DateTime(2026, 1, 1);
      final now = achieved.add(const Duration(days: 70 + 135)); // halfway through taper
      final value = StrengthStandards.effectiveBestE1rm(300, achieved, now);
      expect(value, lessThan(300));
      expect(value, closeTo(300 * (1 - 0.15 * 0.5), 0.5));
    });

    test('never decays below the 85% floor, however long ago the peak was', () {
      final achieved = DateTime(2020, 1, 1);
      final now = DateTime(2026, 1, 1); // years later
      expect(StrengthStandards.effectiveBestE1rm(300, achieved, now), closeTo(300 * 0.85, 0.01));
    });

    test('is unit-agnostic — works the same on a raw rep count as on lb', () {
      final achieved = DateTime(2026, 1, 1);
      final now = achieved.add(const Duration(days: 365));
      expect(StrengthStandards.effectiveBestE1rm(20, achieved, now), closeTo(20 * 0.85, 0.01));
    });
  });
}
