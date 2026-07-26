import 'package:flutter/material.dart';

import '../services/home_trend_settings.dart';
import '../theme/app_theme.dart';

/// Sensible fixed choices for a history window: `0` is the "Default"
/// sentinel (tracks `HomeTrendSettings.months` live, not a copy of its
/// value at save time), `-1` means "All time" (no cutoff).
const timeFrameOptions = [1, 3, 6, 12, -1, 0];

String timeFrameLabel(int months) {
  if (months == 0) return 'Default (${HomeTrendSettings.months} mo)';
  if (months == -1) return 'All time';
  return '$months month${months == 1 ? '' : 's'}';
}

/// Shared "how far back" picker — used by every per-card settings sheet
/// (Metrics' `MetricCardSettingsSheet`, Home's Strength/Metric Trend edit
/// sheets) plus Settings' own field for the shared global default itself,
/// so there's exactly one dropdown implementation and one options list
/// instead of each screen rolling its own.
class TimeFrameDropdown extends StatelessWidget {
  final int value;
  final ValueChanged<int> onChanged;

  /// `false` for the field that edits `HomeTrendSettings.months` itself
  /// (Settings) — a global default can't defer to itself, so "Default"
  /// isn't a valid choice there. `true` everywhere else (a per-card
  /// override, which *can* defer to the global default).
  final bool includeDefault;

  const TimeFrameDropdown({
    super.key,
    required this.value,
    required this.onChanged,
    this.includeDefault = true,
  });

  @override
  Widget build(BuildContext context) {
    final options = includeDefault
        ? timeFrameOptions
        : timeFrameOptions.where((m) => m != 0);
    return DropdownButtonFormField<int>(
      initialValue: value,
      dropdownColor: AppColors.surfaceRaised,
      style: AppText.bodyText,
      decoration: const InputDecoration(isDense: true),
      items: [
        for (final m in options)
          DropdownMenuItem(value: m, child: Text(timeFrameLabel(m))),
      ],
      onChanged: (v) => onChanged(v ?? (includeDefault ? 0 : 1)),
    );
  }
}
