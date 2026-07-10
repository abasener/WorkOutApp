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

class Exercise {
  final int? id;
  final String name;
  final List<ExerciseCategory> categories;
  final bool isSeeded;
  final String? youtubeUrl;
  final String created;

  const Exercise({
    this.id,
    required this.name,
    required this.categories,
    required this.isSeeded,
    this.youtubeUrl,
    required this.created,
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
        isSeeded: (m['is_seeded'] as int) == 1,
        youtubeUrl: m['youtube_url'] as String?,
        created: m['created'] as String,
      );

  Map<String, dynamic> toMap() => {
        'name': name,
        'category': categories.map((c) => c.name).join(','),
        'is_seeded': isSeeded ? 1 : 0,
        'youtube_url': youtubeUrl,
        'created': created,
      };

  Exercise copyWith({
    String? name,
    List<ExerciseCategory>? categories,
    String? youtubeUrl,
  }) =>
      Exercise(
        id: id,
        name: name ?? this.name,
        categories: categories ?? this.categories,
        isSeeded: isSeeded,
        youtubeUrl: youtubeUrl ?? this.youtubeUrl,
        created: created,
      );
}
