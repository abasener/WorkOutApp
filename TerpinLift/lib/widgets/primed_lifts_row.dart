import 'package:flutter/material.dart';

import '../data/models/exercise.dart';
import '../theme/app_theme.dart';

/// Up to 5 lift suggestions that together cover the most of what's currently
/// primed (`ReadinessEngine.suggestPrimedLifts`) — a guide, not a
/// prescription: "here's what covers what's primed," never "you should do
/// X." Shown as small tappable chips under the Primed for Growth map.
class PrimedLiftsRow extends StatelessWidget {
  final List<Exercise> lifts;
  final ValueChanged<Exercise> onTap;

  const PrimedLiftsRow({super.key, required this.lifts, required this.onTap});

  @override
  Widget build(BuildContext context) {
    if (lifts.isEmpty) {
      return Text(
        'Nothing particularly primed right now.',
        style: AppText.smallText,
      );
    }
    return Wrap(
      spacing: AppSpacing.small,
      runSpacing: AppSpacing.small,
      children: lifts.map((e) {
        return GestureDetector(
          onTap: () => onTap(e),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.surfaceRaised,
              borderRadius: BorderRadius.circular(AppRadius.pill),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.fitness_center, size: 14, color: AppColors.good),
                const SizedBox(width: AppSpacing.micro),
                Text(e.name, style: AppText.smallText),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}
