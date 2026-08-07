import 'exercise.dart';

/// A saved, reusable rotation of training days (e.g. the seeded default
/// matching the source PDF). See designFiles/10_WORKOUT_PLANNER.md.
class WorkoutTemplate {
  final int? id;
  final String name;
  final bool isDefault;
  final String created;

  const WorkoutTemplate({
    this.id,
    required this.name,
    this.isDefault = false,
    required this.created,
  });

  factory WorkoutTemplate.fromMap(Map<String, dynamic> m) => WorkoutTemplate(
    id: m['id'] as int?,
    name: m['name'] as String,
    isDefault: (m['is_default'] as int) == 1,
    created: m['created'] as String,
  );

  Map<String, dynamic> toMap() => {
    'name': name,
    'is_default': isDefault ? 1 : 0,
    'created': created,
  };
}

/// One day within a [WorkoutTemplate] — a label plus the movement-pattern
/// slots that day covers (e.g. Day 2 = Horizontal Push, Vertical Pull,
/// Core). No stored per-slot completion — see the design doc for why.
class WorkoutTemplateDay {
  final int? id;
  final int templateId;
  final int dayOrder;
  final String dayLabel;
  final List<MovementPattern> patterns;

  /// Soft-hide flag — a day whose `active` is false still exists (so any
  /// `planned_sessions.template_day_id` history pointing at it keeps
  /// resolving correctly) but no longer appears in `getDaysForTemplate`.
  /// Set when a template import removes a day that already has history —
  /// see `WorkoutPlanRepository.replaceTemplateDays`.
  final bool active;

  const WorkoutTemplateDay({
    this.id,
    required this.templateId,
    required this.dayOrder,
    required this.dayLabel,
    required this.patterns,
    this.active = true,
  });

  factory WorkoutTemplateDay.fromMap(Map<String, dynamic> m) =>
      WorkoutTemplateDay(
        id: m['id'] as int?,
        templateId: m['template_id'] as int,
        dayOrder: m['day_order'] as int,
        dayLabel: m['day_label'] as String,
        patterns: (m['patterns'] as String)
            .split(',')
            .where((s) => s.isNotEmpty)
            .map(
              (key) => MovementPattern.values.firstWhere((p) => p.name == key),
            )
            .toList(),
        active: (m['active'] as int? ?? 1) == 1,
      );

  Map<String, dynamic> toMap() => {
    'template_id': templateId,
    'day_order': dayOrder,
    'day_label': dayLabel,
    'patterns': patterns.map((p) => p.name).join(','),
    'active': active ? 1 : 0,
  };
}

enum PlannedSessionStatus { active, completed, aborted }

extension PlannedSessionStatusKey on PlannedSessionStatus {
  String get key => name;
  static PlannedSessionStatus fromKey(String key) =>
      PlannedSessionStatus.values.firstWhere((s) => s.name == key);
}

/// One "session" (user-facing term) started from a [WorkoutTemplateDay] —
/// see designFiles/10_WORKOUT_PLANNER.md for the full interaction model.
class PlannedSession {
  final int? id;
  final int templateDayId;
  final String date; // 'YYYY-MM-DD'
  final String startedAt; // ISO datetime
  final String? completedAt;
  final PlannedSessionStatus status;
  final String? notes;

  const PlannedSession({
    this.id,
    required this.templateDayId,
    required this.date,
    required this.startedAt,
    this.completedAt,
    required this.status,
    this.notes,
  });

  factory PlannedSession.fromMap(Map<String, dynamic> m) => PlannedSession(
    id: m['id'] as int?,
    templateDayId: m['template_day_id'] as int,
    date: m['date'] as String,
    startedAt: m['started_at'] as String,
    completedAt: m['completed_at'] as String?,
    status: PlannedSessionStatusKey.fromKey(m['status'] as String),
    notes: m['notes'] as String?,
  );

  Map<String, dynamic> toMap() => {
    'template_day_id': templateDayId,
    'date': date,
    'started_at': startedAt,
    'completed_at': completedAt,
    'status': status.key,
    'notes': notes,
  };

  PlannedSession copyWith({
    String? startedAt,
    String? completedAt,
    PlannedSessionStatus? status,
    String? notes,
  }) => PlannedSession(
    id: id,
    templateDayId: templateDayId,
    date: date,
    startedAt: startedAt ?? this.startedAt,
    completedAt: completedAt ?? this.completedAt,
    status: status ?? this.status,
    notes: notes ?? this.notes,
  );
}
