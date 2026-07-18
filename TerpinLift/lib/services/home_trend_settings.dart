/// Shared "how far back" setting for every Strength Trend card on Home —
/// which lifts show is now per-card (`HomeLayoutItem.exerciseId`, see
/// `home_layout_settings.dart`), but months of history is one global knob
/// edited from any card's edit sheet.
abstract class HomeTrendSettings {
  static int months = 6;
}
