enum HiitSessionStatus { active, completed, aborted }

extension HiitSessionStatusKey on HiitSessionStatus {
  String get key => name;
  static HiitSessionStatus fromKey(String key) =>
      HiitSessionStatus.values.firstWhere((s) => s.name == key, orElse: () => HiitSessionStatus.active);
}

/// Which phase the active session is currently showing — a work slot itself,
/// or the rest/transition screen that follows it (see `HiitSlot.restAfterSeconds`).
enum HiitPhase { work, rest }

extension HiitPhaseKey on HiitPhase {
  String get key => name;
  static HiitPhase fromKey(String? key) =>
      HiitPhase.values.firstWhere((p) => p.name == key, orElse: () => HiitPhase.work);
}

/// One HIIT workout — the container; its `HiitSlot` rows hold the actual
/// routine shape. Tracks enough live-session state
/// (`currentSequenceIndex`/`currentPhase`/`phaseStartedAt`/
/// `phaseRemainingSeconds`/`currentRepsRemaining`/`paused`) to resume
/// correctly if the user leaves the active-session screen (via Pause, or
/// just backgrounding/navigating away) and comes back later through the
/// Home widget — nothing here is held only in memory. See
/// designFiles/12_SCREEN_hiit.md "Pausing and resuming."
class HiitSession {
  final int? id;
  final String date; // 'YYYY-MM-DD'
  final String? notes;
  final String startedAt; // ISO datetime
  final String? completedAt;
  final HiitSessionStatus status;
  final bool automatic;

  final int currentSequenceIndex;
  final HiitPhase currentPhase;

  /// Wall-clock time the current phase's timer last (re)started counting —
  /// `null` while [paused] (the countdown is frozen at
  /// [phaseRemainingSeconds] instead of being computed from elapsed time).
  final String? phaseStartedAt;

  /// For a countdown-based phase (time/AMRAP/rest): the remaining seconds
  /// as of [phaseStartedAt] (or the frozen value, while paused). For a
  /// reps-based phase this is unused — see [currentRepsRemaining] instead.
  final double? phaseRemainingSeconds;

  /// For a reps-based work phase: how many reps are left to tap off.
  final int? currentRepsRemaining;

  final bool paused;

  /// Total time spent paused so far, subtracted from the overall elapsed-
  /// workout display the same way `ActiveDayScreen`'s timer would otherwise
  /// over-count a break as training time.
  final double totalPausedSeconds;

  const HiitSession({
    this.id,
    required this.date,
    this.notes,
    required this.startedAt,
    this.completedAt,
    required this.status,
    required this.automatic,
    this.currentSequenceIndex = 0,
    this.currentPhase = HiitPhase.work,
    this.phaseStartedAt,
    this.phaseRemainingSeconds,
    this.currentRepsRemaining,
    this.paused = false,
    this.totalPausedSeconds = 0,
  });

  factory HiitSession.fromMap(Map<String, dynamic> m) => HiitSession(
        id: m['id'] as int?,
        date: m['date'] as String,
        notes: m['notes'] as String?,
        startedAt: m['started_at'] as String,
        completedAt: m['completed_at'] as String?,
        status: HiitSessionStatusKey.fromKey(m['status'] as String),
        automatic: (m['automatic'] as int) == 1,
        currentSequenceIndex: m['current_sequence_index'] as int? ?? 0,
        currentPhase: HiitPhaseKey.fromKey(m['current_phase'] as String?),
        phaseStartedAt: m['phase_started_at'] as String?,
        phaseRemainingSeconds: (m['phase_remaining_seconds'] as num?)?.toDouble(),
        currentRepsRemaining: m['current_reps_remaining'] as int?,
        paused: (m['paused'] as int? ?? 0) == 1,
        totalPausedSeconds: (m['total_paused_seconds'] as num?)?.toDouble() ?? 0,
      );

  Map<String, dynamic> toMap() => {
        'date': date,
        'notes': notes,
        'started_at': startedAt,
        'completed_at': completedAt,
        'status': status.key,
        'automatic': automatic ? 1 : 0,
        'current_sequence_index': currentSequenceIndex,
        'current_phase': currentPhase.key,
        'phase_started_at': phaseStartedAt,
        'phase_remaining_seconds': phaseRemainingSeconds,
        'current_reps_remaining': currentRepsRemaining,
        'paused': paused ? 1 : 0,
        'total_paused_seconds': totalPausedSeconds,
      };

  HiitSession copyWith({
    String? notes,
    bool clearNotes = false,
    String? completedAt,
    HiitSessionStatus? status,
    int? currentSequenceIndex,
    HiitPhase? currentPhase,
    String? phaseStartedAt,
    bool clearPhaseStartedAt = false,
    double? phaseRemainingSeconds,
    bool clearPhaseRemainingSeconds = false,
    int? currentRepsRemaining,
    bool clearCurrentRepsRemaining = false,
    bool? paused,
    double? totalPausedSeconds,
  }) =>
      HiitSession(
        id: id,
        date: date,
        notes: clearNotes ? null : (notes ?? this.notes),
        startedAt: startedAt,
        completedAt: completedAt ?? this.completedAt,
        status: status ?? this.status,
        automatic: automatic,
        currentSequenceIndex: currentSequenceIndex ?? this.currentSequenceIndex,
        currentPhase: currentPhase ?? this.currentPhase,
        phaseStartedAt: clearPhaseStartedAt ? null : (phaseStartedAt ?? this.phaseStartedAt),
        phaseRemainingSeconds:
            clearPhaseRemainingSeconds ? null : (phaseRemainingSeconds ?? this.phaseRemainingSeconds),
        currentRepsRemaining:
            clearCurrentRepsRemaining ? null : (currentRepsRemaining ?? this.currentRepsRemaining),
        paused: paused ?? this.paused,
        totalPausedSeconds: totalPausedSeconds ?? this.totalPausedSeconds,
      );
}
