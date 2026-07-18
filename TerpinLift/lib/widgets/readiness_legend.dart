import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'readiness_bands.dart';

/// A small color strip explaining the Primed for Growth map's color bands —
/// lives in the "i" info sheet (`InfoTooltip`'s `footer`), not on Home
/// itself, so the map's own card stays uncluttered. Same bands/colors as
/// `ReadinessBands`, just the labels — no raw numeric thresholds, those
/// aren't meaningful to a reader who isn't calibrating the formula.
class ReadinessLegend extends StatelessWidget {
  const ReadinessLegend({super.key});

  @override
  Widget build(BuildContext context) {
    final bounds = ReadinessBands.bandBounds;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Map colors', style: AppText.label),
        const SizedBox(height: AppSpacing.small),
        SizedBox(
          height: 10,
          child: Row(
            children: [
              for (var i = 0; i < bounds.length - 1; i++)
                Expanded(
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 1),
                    decoration: BoxDecoration(
                      color: ReadinessBands.colorFor((bounds[i] + bounds[i + 1]) / 2),
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.micro),
        Row(
          children: [
            for (var i = 0; i < bounds.length - 1; i++)
              Expanded(
                child: Text(
                  ReadinessBands.labelFor((bounds[i] + bounds[i + 1]) / 2),
                  textAlign: TextAlign.center,
                  style: AppText.smallText,
                ),
              ),
          ],
        ),
      ],
    );
  }
}
