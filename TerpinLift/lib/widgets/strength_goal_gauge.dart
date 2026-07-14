import 'package:flutter/material.dart';

import '../services/strength_standards.dart';
import '../services/units.dart';
import '../theme/app_theme.dart';
import 'info_tooltip.dart';

/// Long-arc "main goal" gauge: a filled progress track from 0 up to the
/// current **true max** (the heaviest you've actually lifted — never
/// inflated by the Epley formula), with tick marks at each of the 5
/// strength-tier thresholds (bodyweight-ratio standards, gender+age
/// adjusted — see `StrengthStandards`). Deliberately separate from the
/// near-term "Predicted Next e1RM Range" box — that's "try for this next,"
/// this is "here's the long-term target you're working toward."
class StrengthGoalGauge extends StatelessWidget {
  final Map<StrengthTier, double> tierTargets;
  final double currentE1rm;

  /// The decayed, Epley-projected 1RM estimate — shown as a second,
  /// clearly-separate number below the gauge so it never gets mistaken for
  /// something the user actually lifted. `null` skips that line entirely
  /// (e.g. the bodyweight-reps variant of this gauge, where "predicted"
  /// isn't a meaningful concept the same way).
  final double? predictedValue;

  /// Defaults to unit-aware weight formatting; pass an override (e.g. a
  /// rep-count formatter) for bodyweight exercises where the gauge tracks
  /// reps instead of lb.
  final String Function(double)? formatValue;

  const StrengthGoalGauge({
    super.key,
    required this.tierTargets,
    required this.currentE1rm,
    this.predictedValue,
    this.formatValue,
  });

  @override
  Widget build(BuildContext context) {
    final format = formatValue ?? Units.format;
    final currentTier = StrengthStandards.currentTier(currentE1rm, tierTargets);
    final domainMax = tierTargets[StrengthTier.elite]! * 1.05;

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        double xOf(double v) => (v.clamp(0, domainMax) / domainMax) * width;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: 14,
              child: Stack(
                clipBehavior: Clip.none,
                children: StrengthTier.values.map((tier) {
                  const labelWidth = 48.0;
                  return Positioned(
                    left: (xOf(tierTargets[tier]!) - labelWidth / 2)
                        .clamp(0.0, width - labelWidth),
                    width: labelWidth,
                    child: Text(
                      format(tierTargets[tier]!),
                      textAlign: TextAlign.center,
                      style: AppText.smallText.copyWith(
                        fontSize: 10,
                        color: tier == currentTier ? AppColors.accent : AppColors.textSecondary,
                        fontWeight: tier == currentTier ? FontWeight.w700 : FontWeight.w400,
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 2),
            SizedBox(
              height: 22,
              child: CustomPaint(
                size: Size(width, 22),
                painter: _GaugePainter(
                  fillX: xOf(currentE1rm),
                  tickXs: StrengthTier.values.map((t) => xOf(tierTargets[t]!)).toList(),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.small),
            SizedBox(
              height: 16,
              child: Stack(
                clipBehavior: Clip.none,
                children: StrengthTier.values.map((tier) {
                  const labelWidth = 40.0;
                  return Positioned(
                    left: (xOf(tierTargets[tier]!) - labelWidth / 2)
                        .clamp(0.0, width - labelWidth),
                    width: labelWidth,
                    child: Text(
                      tier.shortLabel,
                      textAlign: TextAlign.center,
                      style: AppText.smallText.copyWith(
                        fontSize: 10,
                        color: tier == currentTier ? AppColors.accent : AppColors.textSecondary,
                        fontWeight: tier == currentTier ? FontWeight.w700 : FontWeight.w400,
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: AppSpacing.standard),
            Text(
              'True max: ${format(currentE1rm)}',
              style: AppText.smallText,
            ),
            if (predictedValue != null) ...[
              const SizedBox(height: AppSpacing.micro),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Predicted 1RM: ${format(predictedValue!)}',
                    style: AppText.smallText,
                  ),
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

class _GaugePainter extends CustomPainter {
  final double fillX;
  final List<double> tickXs;
  const _GaugePainter({required this.fillX, required this.tickXs});

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

    // Current-position marker.
    canvas.drawCircle(Offset(fillX, trackY), 6, Paint()..color = AppColors.accent);
  }

  @override
  bool shouldRepaint(_GaugePainter old) => old.fillX != fillX || old.tickXs != tickXs;
}
