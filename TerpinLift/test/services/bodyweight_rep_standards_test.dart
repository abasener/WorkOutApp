import 'package:flutter_test/flutter_test.dart';
import 'package:terpinlift/services/bodyweight_rep_standards.dart';
import 'package:terpinlift/services/strength_standards.dart';
import 'package:terpinlift/services/user_profile.dart';

void main() {
  group('BodyweightRepStandards', () {
    test('Pull Up and Push Up have standards; a barbell lift does not', () {
      expect(BodyweightRepStandards.hasStandard('Pull Up'), isTrue);
      expect(BodyweightRepStandards.hasStandard('Push Up'), isTrue);
      expect(BodyweightRepStandards.hasStandard('Back Squat'), isFalse);
    });

    test('rep targets are strictly increasing across tiers', () {
      final targets = BodyweightRepStandards.allTargets(
        exerciseName: 'Pull Up',
        gender: Gender.male,
        ageBucket: AgeBucket.twenties,
      )!;
      final values = StrengthTier.values.map((t) => targets[t]!).toList();
      for (var i = 1; i < values.length; i++) {
        expect(values[i], greaterThan(values[i - 1]));
      }
    });

    test('age-bucket multiplier never rounds a target down to 0 reps', () {
      final targets = BodyweightRepStandards.allTargets(
        exerciseName: 'Pull Up',
        gender: Gender.female,
        ageBucket: AgeBucket.sixtyPlus, // the steepest age multiplier
      )!;
      for (final v in targets.values) {
        expect(v, greaterThanOrEqualTo(1));
      }
    });

    test('an exercise with no table returns null', () {
      expect(
        BodyweightRepStandards.allTargets(
          exerciseName: 'Dip',
          gender: Gender.male,
          ageBucket: AgeBucket.twenties,
        ),
        isNull,
      );
    });
  });
}
