/// Home screen's "Strength Trends" section — which lifts to chart and how
/// far back. `exerciseIds == null` means "not customized yet," in which case
/// the Home screen falls back to pinned exercises (capped to a handful) —
/// once the user picks specific lifts via the edit-pencil sheet, that exact
/// list is used until they change it again, even if pins change later.
abstract class HomeTrendSettings {
  static List<int>? exerciseIds;
  static int months = 6;
}
