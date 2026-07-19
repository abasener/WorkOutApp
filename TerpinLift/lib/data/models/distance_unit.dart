/// A cardio exercise's chosen distance unit — miles/km/meters are mutually
/// convertible (canonical storage is always meters for these), but floors
/// is deliberately **not** convertible to/from the others (a flight of
/// stairs isn't a distance) and gets no pace tracking. Chosen per exercise
/// (`Exercise.cardioUnit`, e.g. Run in miles, Rowing Machine in meters), not
/// app-wide — see designFiles/11_SCREEN_cardio.md.
enum DistanceUnit { miles, km, meters, floors }

extension DistanceUnitKey on DistanceUnit {
  String get key => name;

  static DistanceUnit? fromKey(String? key) {
    for (final v in DistanceUnit.values) {
      if (v.name == key) return v;
    }
    return null;
  }

  String get label {
    switch (this) {
      case DistanceUnit.miles:
        return 'Miles';
      case DistanceUnit.km:
        return 'Kilometers';
      case DistanceUnit.meters:
        return 'Meters';
      case DistanceUnit.floors:
        return 'Floors';
    }
  }

  String get suffix {
    switch (this) {
      case DistanceUnit.miles:
        return 'mi';
      case DistanceUnit.km:
        return 'km';
      case DistanceUnit.meters:
        return 'm';
      case DistanceUnit.floors:
        return 'floors';
    }
  }

  /// `false` for floors — not part of the mile/km/meter conversion family,
  /// and doesn't support pace.
  bool get isRealDistance => this != DistanceUnit.floors;

  /// Meters per one of this unit. Only meaningful when [isRealDistance].
  double get metersPerUnit {
    switch (this) {
      case DistanceUnit.miles:
        return 1609.34;
      case DistanceUnit.km:
        return 1000;
      case DistanceUnit.meters:
        return 1;
      case DistanceUnit.floors:
        return 1;
    }
  }

  /// Meters per one *pace* unit — separate from [metersPerUnit] because a
  /// straight "seconds per meter" pace is nonsensically tiny (always rounds
  /// to "0:00"). Miles/km paces are conventionally per-mile/per-km (same as
  /// [metersPerUnit]); meters paces use the standard rowing-split
  /// convention of per-500m instead of per-1m.
  double get paceUnitMeters => this == DistanceUnit.meters ? 500 : metersPerUnit;

  /// The "/X" suffix a pace figure prints with — differs from [suffix] only
  /// for meters (see [paceUnitMeters]).
  String get paceSuffix => this == DistanceUnit.meters ? '500m' : suffix;
}
