import 'package:flutter/material.dart';

import '../services/units.dart';
import '../theme/app_theme.dart';
import 'info_tooltip.dart';

/// One entry in a [SingleGoalGauge] — a custom-goal-log row reduced to just
/// what the gauge needs to plot it.
class GoalMarker {
  final double value;
  final String label;
  const GoalMarker({required this.value, required this.label});
}

/// A multi-target sibling to [StrengthGoalGauge] — same track/fill visual,
/// but ticks at every entry in the user's own custom-goal log instead of the
/// 5 published tiers. Used when a lift's Goal is set to `GoalSource.custom`
/// (either because there's no published standard for it, or the user
/// explicitly chose to override one that exists). The domain scales to fit
/// every goal (largest sets the ceiling), same as the standard gauge scales
/// to Elite — so old goals stay visible on the bar, not just the newest one.
class SingleGoalGauge extends StatelessWidget {
  /// Every logged goal for this exercise — plotted in ascending value order
  /// regardless of the order passed in.
  final List<GoalMarker> goals;
  final double current;

  /// Rep count the [current] max was achieved at, shown alongside it
  /// ("True max: 100lb, 4 reps"). `null` skips the rep count (e.g. the
  /// bodyweight-reps variant, where `current` already *is* a rep count).
  final int? currentReps;

  /// The Epley-projected 1RM estimate — shown as a second, clearly-separate
  /// line below True max, same as [StrengthGoalGauge]. `null` skips it (the
  /// bodyweight-reps variant, where "predicted" isn't as meaningful).
  final double? predictedValue;

  final String Function(double)? formatValue;

  /// When true, a *smaller* value is the achievement (e.g. pace — faster is
  /// a lower minutes-per-mile number) instead of the default "bigger is
  /// better." The fill/tick positions mirror across the axis so progress
  /// still visually reads as filling left-to-right; the printed numbers
  /// never change. See `CardioDetailScreen`'s Pace gauge.
  final bool lowerIsBetter;

  /// Label prefixing the current-value line — "True max" for lifts,
  /// something like "Best pace" for cardio.
  final String currentLabel;

  const SingleGoalGauge({
    super.key,
    required this.goals,
    required this.current,
    this.currentReps,
    this.predictedValue,
    this.formatValue,
    this.lowerIsBetter = false,
    this.currentLabel = 'True max',
  });

  @override
  Widget build(BuildContext context) {
    final format = formatValue ?? Units.format;
    final sorted = [...goals]..sort((a, b) => a.value.compareTo(b.value));
    final domainMax = sorted.last.value * 1.05;
    // The most impressive goal actually reached — bolded/accented the same
    // way StrengthGoalGauge highlights the current tier, so an old goal
    // you've since blown past still reads as "done," not just another grey
    // tick. "Most impressive" is the largest value for a normal gauge, the
    // smallest (hardest-to-hit) value when `lowerIsBetter`.
    var reachedIndex = -1;
    if (lowerIsBetter) {
      for (var i = sorted.length - 1; i >= 0; i--) {
        if (current <= sorted[i].value) {
          reachedIndex = i;
        } else {
          break;
        }
      }
    } else {
      for (var i = 0; i < sorted.length; i++) {
        if (current >= sorted[i].value) {
          reachedIndex = i;
        } else {
          break;
        }
      }
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        double xOf(double v) {
          final clamped = v.clamp(0, domainMax);
          return lowerIsBetter
              ? ((domainMax - clamped) / domainMax) * width
              : (clamped / domainMax) * width;
        }

        const labelWidth = 56.0;

        Widget labelRow(String Function(GoalMarker) textOf) => SizedBox(
              height: 14,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  for (var i = 0; i < sorted.length; i++)
                    Positioned(
                      left: (xOf(sorted[i].value) - labelWidth / 2)
                          .clamp(0.0, width - labelWidth),
                      width: labelWidth,
                      child: Text(
                        textOf(sorted[i]),
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.smallText.copyWith(
                          fontSize: 10,
                          color: i == reachedIndex
                              ? AppColors.accent
                              : AppColors.textSecondary,
                          fontWeight: i == reachedIndex ? FontWeight.w700 : FontWeight.w400,
                        ),
                      ),
                    ),
                ],
              ),
            );

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            labelRow((g) => format(g.value)),
            const SizedBox(height: 2),
            SizedBox(
              height: 22,
              child: CustomPaint(
                size: Size(width, 22),
                painter: _SingleGaugePainter(
                  fillX: xOf(current),
                  tickXs: sorted.map((g) => xOf(g.value)).toList(),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.small),
            labelRow((g) => g.label),
            const SizedBox(height: AppSpacing.standard),
            Text(
              currentReps != null
                  ? '$currentLabel: ${format(current)}, $currentReps ${currentReps == 1 ? 'rep' : 'reps'}'
                  : '$currentLabel: ${format(current)}',
              style: AppText.smallText,
            ),
            if (predictedValue != null) ...[
              const SizedBox(height: AppSpacing.micro),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Predicted 1RM: ${format(predictedValue!)}', style: AppText.smallText),
                  const InfoTooltip(glossaryKey: 'predicted_1rm', title: 'Predicted 1RM'),
                ],
              ),
            ],
          ],
        );
      },
    );
  }
}

class _SingleGaugePainter extends CustomPainter {
  final double fillX;
  final List<double> tickXs;
  const _SingleGaugePainter({required this.fillX, required this.tickXs});

  @override
  void paint(Canvas canvas, Size size) {
    final trackY = size.height / 2;
    final trackRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, trackY - 3, size.width, 6),
      const Radius.circular(3),
    );
    canvas.drawRRect(trackRect, Paint()..color = AppColors.border);

    if (fillX > 0) {
      final fillRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(0, trackY - 3, fillX.clamp(0, size.width), 6),
        const Radius.circular(3),
      );
      canvas.drawRRect(fillRect, Paint()..color = AppColors.accent);
    }

    final tickPaint = Paint()
      ..color = AppColors.textSecondary
      ..strokeWidth = 2;
    for (final x in tickXs) {
      canvas.drawLine(Offset(x, trackY - 8), Offset(x, trackY + 8), tickPaint);
    }

    canvas.drawCircle(Offset(fillX, trackY), 6, Paint()..color = AppColors.accent);
  }

  @override
  bool shouldRepaint(_SingleGaugePainter old) =>
      old.fillX != fillX || old.tickXs != tickXs;
}
