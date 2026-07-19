/// One logged effort within a cardio session — distance, duration (seconds),
/// and an optional resistance/incline/added-load number (`load`) generic
/// enough to cover a rower's resistance level, a treadmill incline, or a
/// ruck's pack weight. Pace/distance display always goes through
/// `CardioUnits` together with the owning exercise's `DistanceUnit` — this
/// model just holds canonical numbers, it has no unit context of its own.
class CardioEntry {
  final int? id;
  final int sessionId;
  final int entryNumber;

  /// Canonical distance — meters for a real-distance exercise (miles/km/
  /// meters), or a raw floor count for a `DistanceUnit.floors` exercise
  /// (floors don't convert to/from a real distance). See `CardioUnits`.
  final double? distanceCanonical;

  final int? durationSeconds;
  final double? load;
  final double? rpe;
  final String? entryStartedAt;
  final String? entryCompletedAt;

  const CardioEntry({
    this.id,
    required this.sessionId,
    required this.entryNumber,
    this.distanceCanonical,
    this.durationSeconds,
    this.load,
    this.rpe,
    this.entryStartedAt,
    this.entryCompletedAt,
  });

  factory CardioEntry.fromMap(Map<String, dynamic> m) => CardioEntry(
        id: m['id'] as int?,
        sessionId: m['session_id'] as int,
        entryNumber: m['entry_number'] as int,
        distanceCanonical: (m['distance_canonical'] as num?)?.toDouble(),
        durationSeconds: m['duration_seconds'] as int?,
        load: (m['load'] as num?)?.toDouble(),
        rpe: (m['rpe'] as num?)?.toDouble(),
        entryStartedAt: m['entry_started_at'] as String?,
        entryCompletedAt: m['entry_completed_at'] as String?,
      );

  Map<String, dynamic> toMap() => {
        'session_id': sessionId,
        'entry_number': entryNumber,
        'distance_canonical': distanceCanonical,
        'duration_seconds': durationSeconds,
        'load': load,
        'rpe': rpe,
        'entry_started_at': entryStartedAt,
        'entry_completed_at': entryCompletedAt,
      };
}
