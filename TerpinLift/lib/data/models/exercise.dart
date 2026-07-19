import 'package:flutter_body_heatmap/flutter_body_heatmap.dart';

import 'distance_unit.dart';

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

/// Which target the Goal gauge uses for this exercise — the published
/// bodyweight-ratio/rep-count standard, or the user's own `custom_goals`
/// entry. `null` (unset) means auto: standard if one exists, otherwise
/// custom if the user has set one, otherwise no goal shown. Explicit
/// `custom` lets the user override a lift that *does* have a standard.
enum GoalSource { standard, custom }

extension GoalSourceKey on GoalSource {
  String get key => name;
  static GoalSource? fromKey(String? key) {
    for (final v in GoalSource.values) {
      if (v.name == key) return v;
    }
    return null;
  }
}

/// Which number leads on Lift detail's near-term prediction and the Goal
/// gauge — the literal heaviest weight ever logged (no formula), or the
/// gender-scaled-Epley-projected 1RM. `null` (unset) means auto: `predicted`
/// for compound/free-weight lifts (where a 1RM estimate is a meaningful,
/// literature-backed concept), `trueMax` for machine/isolation lifts (where
/// it much less reliably is — see designFiles/07_SMART_TRENDS.md).
enum ProgressMetric { predicted, trueMax }

extension ProgressMetricKey on ProgressMetric {
  String get key => name;
  static ProgressMetric? fromKey(String? key) {
    for (final v in ProgressMetric.values) {
      if (v.name == key) return v;
    }
    return null;
  }
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

  /// `null` = auto (see [GoalSource]'s doc comment).
  final GoalSource? goalSource;

  /// `null` = auto (see [ProgressMetric]'s doc comment).
  final ProgressMetric? progressMetric;

  /// Free-text personal notes the user writes themselves — form cues,
  /// reminders, whatever they want. Replaces the old curated per-lift
  /// "Overview" cues entirely (`designFiles/03_SCREEN_lifts.md`); `null` =
  /// nothing written yet.
  final String? notes;

  /// Fine-grained muscles this exercise targets, set by the user (either at
  /// creation or later via the muscle-selector popup) — takes priority over
  /// `MuscleMap.liftMuscles`'s curated fallback when non-empty. Empty for
  /// exercises that haven't had this set (older installs, or a user who
  /// skipped it where it was optional).
  final List<Muscle> targetMuscles;

  /// Only meaningful for `ExerciseType.cardio`-tagged exercises — which
  /// distance unit its entries display/convert in (a run tracked in miles
  /// and a row tracked in meters can coexist app-wide). `null` = not set
  /// yet (falls back to `CardioUnits.defaultUnit`) or not a cardio exercise.
  /// See designFiles/11_SCREEN_cardio.md.
  final DistanceUnit? cardioUnit;

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
    this.goalSource,
    this.progressMetric,
    this.notes,
    this.targetMuscles = const [],
    this.cardioUnit,
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
        goalSource: GoalSourceKey.fromKey(m['goal_source'] as String?),
        progressMetric: ProgressMetricKey.fromKey(m['progress_metric'] as String?),
        notes: m['notes'] as String?,
        targetMuscles: ((m['target_muscles'] as String?) ?? '')
            .split(',')
            .where((s) => s.isNotEmpty)
            .map((key) => Muscle.values.firstWhere((mu) => mu.name == key))
            .toList(),
        cardioUnit: DistanceUnitKey.fromKey(m['cardio_unit'] as String?),
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
        'goal_source': goalSource?.key,
        'progress_metric': progressMetric?.key,
        'notes': notes,
        'target_muscles': targetMuscles.map((m) => m.name).join(','),
        'cardio_unit': cardioUnit?.key,
      };

  Exercise copyWith({
    String? name,
    List<ExerciseCategory>? categories,
    List<ExerciseType>? equipmentTags,
    List<MovementPattern>? patterns,
    String? youtubeUrl,
    bool? pinned,
    // Nullable fields that need to support being explicitly *cleared* (not
    // just "left unchanged") — pass e.g. `clearGoalSource: true` to reset
    // to auto rather than passing `goalSource: null` (which `??` would just
    // ignore).
    GoalSource? goalSource,
    bool clearGoalSource = false,
    ProgressMetric? progressMetric,
    bool clearProgressMetric = false,
    String? notes,
    bool clearNotes = false,
    List<Muscle>? targetMuscles,
    DistanceUnit? cardioUnit,
    bool clearCardioUnit = false,
  }) =>
      Exercise(
        id: id,
        name: name ?? this.name,
        categories: categories ?? this.categories,
        equipmentTags: equipmentTags ?? this.equipmentTags,
        patterns: patterns ?? this.patterns,
        isSeeded: isSeeded,
        youtubeUrl: youtubeUrl ?? this.youtubeUrl,
        goalSource: clearGoalSource ? null : (goalSource ?? this.goalSource),
        progressMetric:
            clearProgressMetric ? null : (progressMetric ?? this.progressMetric),
        created: created,
        pinned: pinned ?? this.pinned,
        notes: clearNotes ? null : (notes ?? this.notes),
        targetMuscles: targetMuscles ?? this.targetMuscles,
        cardioUnit: clearCardioUnit ? null : (cardioUnit ?? this.cardioUnit),
      );
}
