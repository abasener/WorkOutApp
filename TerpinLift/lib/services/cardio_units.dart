import '../data/models/distance_unit.dart';

/// Per-exercise cardio unit math — distance conversion, duration, and pace
/// formatting, all keyed off a specific exercise's chosen `DistanceUnit`
/// rather than the app-wide lb/kg toggle. A run tracked in miles and a row
/// tracked in meters can coexist; entering one particular effort in a
/// different unit than the exercise's own (a sprint logged in meters on an
/// otherwise-miles Run) still converts to that exercise's one canonical
/// number. See designFiles/11_SCREEN_cardio.md.
abstract class CardioUnits {
  static const defaultUnit = DistanceUnit.miles;

  /// Converts a value entered in [unit] to canonical storage — meters for a
  /// real-distance unit, or the raw count unchanged for floors (which
  /// doesn't convert to/from anything).
  static double toCanonical(double value, DistanceUnit unit) =>
      unit.isRealDistance ? value * unit.metersPerUnit : value;

  /// Inverse of [toCanonical] — canonical storage -> a value in [unit].
  static double fromCanonical(double canonical, DistanceUnit unit) =>
      unit.isRealDistance ? canonical / unit.metersPerUnit : canonical;

  static String formatDistance(double canonical, DistanceUnit unit) =>
      '${fromCanonical(canonical, unit).toStringAsFixed(unit == DistanceUnit.floors ? 0 : 2)} '
      '${unit.suffix}';

  /// [seconds] -> `"12:34"` under an hour, `"1:05:12"` at or past one.
  static String formatDuration(int seconds) {
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    final s = seconds % 60;
    final ss = s.toString().padLeft(2, '0');
    if (h > 0) return '$h:${m.toString().padLeft(2, '0')}:$ss';
    return '$m:$ss';
  }

  /// Seconds per one *pace* unit (e.g. seconds per mile, or per 500m for a
  /// meters-unit exercise — see `DistanceUnit.paceUnitMeters`) — the
  /// canonical pace figure used both for display and for comparing against
  /// a logged goal. `null` if distance/duration is missing or non-positive,
  /// or the unit is floors (pace isn't tracked for floors).
  static double? paceSecondsPerUnit(
    double? canonicalDistance,
    int? durationSeconds,
    DistanceUnit unit,
  ) {
    if (!unit.isRealDistance) return null;
    if (canonicalDistance == null || canonicalDistance <= 0) return null;
    if (durationSeconds == null || durationSeconds <= 0) return null;
    final secondsPerMeter = durationSeconds / canonicalDistance;
    return secondsPerMeter * unit.paceUnitMeters;
  }

  static String formatPace(double secondsPerUnit, DistanceUnit unit) {
    final mins = (secondsPerUnit / 60).floor();
    final secs = (secondsPerUnit % 60).round();
    return '$mins:${secs.toString().padLeft(2, '0')}/${unit.paceSuffix}';
  }
}
