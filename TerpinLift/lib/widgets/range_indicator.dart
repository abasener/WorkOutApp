import 'package:flutter/material.dart';

import '../services/units.dart';
import '../theme/app_theme.dart';

/// Error-bar style range plot for a prediction: a line spanning low-to-high
/// with a tick at each end and a bigger dot at the expected/goal value in the
/// middle, numeric labels under all three points. Always shown — no
/// tap-to-expand for this one, per user feedback that the collapsed number
/// alone didn't convey the range.
class RangeIndicator extends StatelessWidget {
  final double low;
  final double goal;
  final double high;

  const RangeIndicator({
    super.key,
    required this.low,
    required this.goal,
    required this.high,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 44,
          child: LayoutBuilder(
            builder: (_, constraints) => CustomPaint(
              size: Size(constraints.maxWidth, 44),
              painter: _WhiskerPainter(low: low, goal: goal, high: high),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.small),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(Units.format(low), style: AppText.smallText),
            Text(Units.format(goal), style: AppText.subHeader),
            Text(Units.format(high), style: AppText.smallText),
          ],
        ),
      ],
    );
  }
}

class _WhiskerPainter extends CustomPainter {
  final double low;
  final double goal;
  final double high;
  const _WhiskerPainter({required this.low, required this.goal, required this.high});

  @override
  void paint(Canvas canvas, Size size) {
    final range = (high - low).abs() < 1e-9 ? 1.0 : (high - low);
    double xOf(double v) => (v - low) / range * size.width;
    final midY = size.height / 2;

    final linePaint = Paint()
      ..color = AppColors.textSecondary
      ..strokeWidth = 2;
    canvas.drawLine(Offset(xOf(low), midY), Offset(xOf(high), midY), linePaint);

    // Whisker caps at low/high.
    canvas.drawLine(Offset(xOf(low), midY - 10), Offset(xOf(low), midY + 10), linePaint);
    canvas.drawLine(Offset(xOf(high), midY - 10), Offset(xOf(high), midY + 10), linePaint);

    // Goal marker — the expected/mean value.
    canvas.drawCircle(Offset(xOf(goal), midY), 8, Paint()..color = AppColors.accent);
  }

  @override
  bool shouldRepaint(_WhiskerPainter old) =>
      old.low != low || old.goal != goal || old.high != high;
}
