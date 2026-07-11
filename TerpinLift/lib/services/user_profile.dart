enum Gender { female, male }

extension GenderKey on Gender {
  String get key => this == Gender.female ? 'female' : 'male';
  String get label => this == Gender.female ? 'Female' : 'Male';
  static Gender fromKey(String? key) => key == 'male' ? Gender.male : Gender.female;
}

/// Broad age brackets for the strength-standard goal system — buckets, not a
/// precise age, per the user's call: "a 21 y/o and a 56 y/o are going to
/// have very different expected max lifts" but an exact age-graduated curve
/// is more precision than this needs.
enum AgeBucket { under20, twenties, thirties, forties, fifties, sixtyPlus }

extension AgeBucketInfo on AgeBucket {
  String get label {
    switch (this) {
      case AgeBucket.under20:
        return 'Under 20';
      case AgeBucket.twenties:
        return '20s';
      case AgeBucket.thirties:
        return '30s';
      case AgeBucket.forties:
        return '40s';
      case AgeBucket.fifties:
        return '50s';
      case AgeBucket.sixtyPlus:
        return '60+';
    }
  }

  /// Multiplier applied to the reference (20s) strength-standard numbers —
  /// a directional approximation of how expected max strength shifts with
  /// age (roughly flat through the 20s, gradual decline through the 30s-40s,
  /// steeper after 50), loosely mirroring the shape of published
  /// age-graduated powerlifting adjustment formulas. Not individually
  /// measured for any specific user.
  double get standardMultiplier {
    switch (this) {
      case AgeBucket.under20:
        return 0.9; // still developing into full adult capacity
      case AgeBucket.twenties:
        return 1.0; // reference bracket
      case AgeBucket.thirties:
        return 0.97;
      case AgeBucket.forties:
        return 0.90;
      case AgeBucket.fifties:
        return 0.80;
      case AgeBucket.sixtyPlus:
        return 0.68;
    }
  }

  static AgeBucket fromAge(int age) {
    if (age < 20) return AgeBucket.under20;
    if (age < 30) return AgeBucket.twenties;
    if (age < 40) return AgeBucket.thirties;
    if (age < 50) return AgeBucket.forties;
    if (age < 60) return AgeBucket.fifties;
    return AgeBucket.sixtyPlus;
  }
}

/// Minimal user-profile settings needed by anything that has to reason about
/// the user themselves rather than just their logged data — gender and birth
/// year, both currently only used by the strength-standard goal system.
/// Defaults: gender female (matches how this app was framed from the
/// start), birth year unset (goal system falls back to the 20s/reference
/// bucket, i.e. no age adjustment, until set).
abstract class UserProfile {
  static Gender gender = Gender.female;
  static int? birthYear;

  static AgeBucket get ageBucket {
    if (birthYear == null) return AgeBucket.twenties;
    final age = DateTime.now().year - birthYear!;
    return AgeBucketInfo.fromAge(age);
  }
}
