import 'package:flutter/material.dart';

import '../data/models/exercise.dart';
import '../services/training_composition_service.dart';
import '../theme/app_theme.dart';

/// Colors for the training-composition chart's 5 body-part categories.
///
/// Sourced from the dataviz skill's validated categorical palette (dark-mode
/// steps), taking the first 5 slots in their fixed CVD-safe order — blue,
/// aqua, yellow, green, violet — and deliberately skipping slot 6 (red) so
/// these categories never get visually confused with the app's one reserved
/// red accent used everywhere else. The mapping below is fixed; never
/// reassign colors based on which categories happen to appear on a given day
/// (color follows the entity, not its rank).
abstract class CompositionColors {
  static const Map<ExerciseCategory, Color> byCategory = {
    ExerciseCategory.legs: Color(0xFF3987E5), // blue
    ExerciseCategory.core: Color(0xFF199E70), // aqua
    ExerciseCategory.chest: Color(0xFFC98500), // yellow
    ExerciseCategory.arms: Color(0xFF008300), // green
    ExerciseCategory.back: Color(0xFF9085E9), // violet
  };
}

/// 100%-stacked bar chart: one bar per workout day (indexed consecutively,
/// rest days collapsed out entirely — see designFiles/00_UX_DESIGN.md for why
/// this chart intentionally does NOT use calendar-date spacing like the
/// trend charts), each bar showing that day's training split across body
/// parts, weighted by RPE-sum. Horizontally scrollable so no history cap is
/// needed — bars stay a fixed, readable width regardless of how much history
/// exists.
class TrainingCompositionChart extends StatelessWidget {
  final List<CategoryComposition> compositions;
  final double height;
  final double barWidth;
  final double barGap;

  const TrainingCompositionChart({
    super.key,
    required this.compositions,
    this.height = 160,
    this.barWidth = 14,
    this.barGap = 3,
  });

  @override
  Widget build(BuildContext context) {
    if (compositions.isEmpty) {
      return SizedBox(
        height: height,
        child: Center(
          child: Text('Log a few workouts to see this', style: AppText.smallText),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: height,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            reverse: true, // start scrolled to the most recent day
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (final comp in compositions)
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: barGap / 2),
                    child: SizedBox(
                      width: barWidth,
                      height: height,
                      child: _StackedBar(composition: comp),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.standard),
        _Legend(),
      ],
    );
  }
}

class _StackedBar extends StatelessWidget {
  final CategoryComposition composition;
  const _StackedBar({required this.composition});

  @override
  Widget build(BuildContext context) {
    final segments = _applyVisibilityFloor(composition.proportions)
        .where((entry) => entry.$2 > 0)
        .toList();

    return Column(
      children: [
        for (var i = 0; i < segments.length; i++)
          Expanded(
            flex: (segments[i].$2 * 1000).round().clamp(1, 1000),
            child: Container(
              margin: EdgeInsets.only(
                bottom: i < segments.length - 1 ? 2 : 0, // gap between segments
              ),
              decoration: BoxDecoration(
                color: CompositionColors.byCategory[segments[i].$1],
                borderRadius: i == segments.length - 1
                    ? const BorderRadius.vertical(bottom: Radius.circular(2))
                    : i == 0
                        ? const BorderRadius.vertical(top: Radius.circular(2))
                        : null,
              ),
            ),
          ),
      ],
    );
  }

  /// Any category present at all (proportion > 0) is bumped up to at least
  /// [floor], then everything is renormalized so the bar still sums to 100%.
  /// Without this, a category that's a real but small sliver of the day's
  /// effort (e.g. 0.5%) renders under a pixel tall on a ~160px bar and reads
  /// as "missing" even though the data has it — this is a display-only
  /// adjustment, the underlying stored proportions are untouched.
  static const _floor = 0.03;

  List<(ExerciseCategory, double)> _applyVisibilityFloor(
    Map<ExerciseCategory, double> proportions,
  ) {
    final raised = {
      for (final c in TrainingCompositionService.bodyPartCategories)
        c: (proportions[c] ?? 0) > 0
            ? (proportions[c]!).clamp(_floor, 1.0)
            : 0.0,
    };
    final total = raised.values.fold<double>(0, (a, b) => a + b);
    if (total <= 0) return [];
    return [
      for (final c in TrainingCompositionService.bodyPartCategories)
        (c, raised[c]! / total),
    ];
  }
}

class _Legend extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.standard,
      runSpacing: AppSpacing.micro,
      children: TrainingCompositionService.bodyPartCategories.map((c) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: CompositionColors.byCategory[c],
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: AppSpacing.micro),
            Text(c.label, style: AppText.smallText),
          ],
        );
      }).toList(),
    );
  }
}
