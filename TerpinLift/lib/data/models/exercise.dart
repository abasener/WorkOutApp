/// Rough body-region tags used to label exercises. An exercise can carry
/// more than one (e.g. Bench Press: chest + push + arms).
enum ExerciseCategory { legs, core, arms, back, chest, push, pull }

extension ExerciseCategoryLabel on ExerciseCategory {
  String get label {
    switch (this) {
      case ExerciseCategory.legs:
        return 'Legs';
      case ExerciseCategory.core:
        return 'Core';
      case ExerciseCategory.arms:
        return 'Arms';
      case ExerciseCategory.back:
        return 'Back';
      case ExerciseCategory.chest:
        return 'Chest';
      case ExerciseCategory.push:
        return 'Push';
      case ExerciseCategory.pull:
        return 'Pull';
    }
  }
}

/// Equipment/movement-type tags — a separate dimension from [ExerciseCategory]
/// (which body region a lift hits). Purely descriptive/filterable metadata
/// for now; sorting/filtering by these is a deliberate follow-up, not built
/// yet. Bodyweight movements track sets/reps/weight identically to everything
/// else for now (a goal-in-reps-not-lb variant is a future revisit, not this
/// round) — this tag is just a label.
enum ExerciseType { cardio, machine, compound, bodyweight, isolation }

extension ExerciseTypeLabel on ExerciseType {
  String get label {
    switch (this) {
      case ExerciseType.cardio:
        return 'Cardio';
      case ExerciseType.machine:
        return 'Machine';
      case ExerciseType.compound:
        return 'Compound';
      case ExerciseType.bodyweight:
        return 'Bodyweight';
      case ExerciseType.isolation:
        return 'Isolation';
    }
  }
}

/// A third tag dimension, parallel to [ExerciseCategory] (body part) and
/// [ExerciseType] (equipment) — which movement pattern a lift satisfies.
/// Powers the Workout Planner's pattern-pool browsing (see
/// designFiles/10_WORKOUT_PLANNER.md); not used by anything else in the app.
enum MovementPattern {
  squat,
  hinge,
  horizontalPush,
  verticalPush,
  horizontalPull,
  verticalPull,
  quadGlute,
  hamstringGlute,
  adductorAbductor,
  core,
  shoulderPrehab,
  armsAesthetic,
}

extension MovementPatternLabel on MovementPattern {
  String get label {
    switch (this) {
      case MovementPattern.squat:
        return 'Squat Pattern';
      case MovementPattern.hinge:
        return 'Hinge Pattern';
      case MovementPattern.horizontalPush:
        return 'Horizontal Push';
      case MovementPattern.verticalPush:
        return 'Vertical Push';
      case MovementPattern.horizontalPull:
        return 'Horizontal Pull';
      case MovementPattern.verticalPull:
        return 'Vertical Pull';
      case MovementPattern.quadGlute:
        return 'Quad / Glute';
      case MovementPattern.hamstringGlute:
        return 'Hamstring / Glute';
      case MovementPattern.adductorAbductor:
        return 'Adductor / Abductor';
      case MovementPattern.core:
        return 'Core';
      case MovementPattern.shoulderPrehab:
        return 'Shoulder Prehab';
      case MovementPattern.armsAesthetic:
        return 'Arms / Aesthetic';
    }
  }

  /// Main lift patterns show first / read as the "primary" slots; accessory
  /// patterns are the smaller-muscle/prehab-style ones. Purely a display
  /// grouping (e.g. for sectioning the pattern picker), not stored.
  bool get isMain => index <= MovementPattern.verticalPull.index;
}

class Exercise {
  final int? id;
  final String name;
  final List<ExerciseCategory> categories;
  final List<ExerciseType> equipmentTags;
  final List<MovementPattern> patterns;
  final bool isSeeded;
  final String? youtubeUrl;
  final String created;

  /// "Pinned" (push-pin icon on Lift detail) — the small set of lifts the
  /// user actually trains regularly, now that the seeded library covers
  /// ~75 exercises. Drives the quick-log dropdown (`LogLiftForm` only lists
  /// pinned exercises, since anything else is reachable via the Lifts list
  /// + that lift's own "+" button) and a Lifts-list quick filter.
  final bool pinned;

  const Exercise({
    this.id,
    required this.name,
    required this.categories,
    this.equipmentTags = const [],
    this.patterns = const [],
    required this.isSeeded,
    this.youtubeUrl,
    required this.created,
    this.pinned = false,
  });

  factory Exercise.fromMap(Map<String, dynamic> m) => Exercise(
        id: m['id'] as int?,
        name: m['name'] as String,
        categories: (m['category'] as String)
            .split(',')
            .where((s) => s.isNotEmpty)
            .map((key) => ExerciseCategory.values.firstWhere(
                  (c) => c.name == key,
                  orElse: () => ExerciseCategory.core,
                ))
            .toList(),
        equipmentTags: ((m['equipment_tags'] as String?) ?? '')
            .split(',')
            .where((s) => s.isNotEmpty)
            .map((key) => ExerciseType.values.firstWhere((t) => t.name == key))
            .toList(),
        patterns: ((m['movement_patterns'] as String?) ?? '')
            .split(',')
            .where((s) => s.isNotEmpty)
            .map((key) => MovementPattern.values.firstWhere((p) => p.name == key))
            .toList(),
        isSeeded: (m['is_seeded'] as int) == 1,
        youtubeUrl: m['youtube_url'] as String?,
        created: m['created'] as String,
        pinned: (m['pinned'] as int?) == 1,
      );

  Map<String, dynamic> toMap() => {
        'name': name,
        'category': categories.map((c) => c.name).join(','),
        'equipment_tags': equipmentTags.map((t) => t.name).join(','),
        'movement_patterns': patterns.map((p) => p.name).join(','),
        'is_seeded': isSeeded ? 1 : 0,
        'youtube_url': youtubeUrl,
        'created': created,
        'pinned': pinned ? 1 : 0,
      };

  Exercise copyWith({
    String? name,
    List<ExerciseCategory>? categories,
    List<ExerciseType>? equipmentTags,
    List<MovementPattern>? patterns,
    String? youtubeUrl,
    bool? pinned,
  }) =>
      Exercise(
        id: id,
        name: name ?? this.name,
        categories: categories ?? this.categories,
        equipmentTags: equipmentTags ?? this.equipmentTags,
        patterns: patterns ?? this.patterns,
        isSeeded: isSeeded,
        youtubeUrl: youtubeUrl ?? this.youtubeUrl,
        created: created,
        pinned: pinned ?? this.pinned,
      );
}
