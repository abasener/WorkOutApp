import 'package:flutter/material.dart';

import '../services/units.dart';
import '../theme/app_theme.dart';

/// Error-bar style range plot for a prediction: a line spanning low-to-high
/// with a tick at each end and a bigger dot at the expected/goal value, each
/// with its own numeric label directly beneath it — not evenly spaced text,
/// actually aligned under its point, so an asymmetric range (goal off-center)
/// still reads correctly if low/high error ever stop being equal on each
/// side. The whisker span itself sits inset from the full width with padding
/// on both ends, so the plot has breathing room rather than touching the
/// card's edges. Always shown — no tap-to-expand for this one, per user
/// feedback that the collapsed number alone didn't convey the range.
class RangeIndicator extends StatelessWidget {
  final double low;
  final double goal;
  final double high;

  /// Defaults to unit-aware weight formatting; pass an override (e.g. a
  /// rep-count formatter) for exercises where the plotted values aren't lb.
  final String Function(double)? formatValue;

  const RangeIndicator({
    super.key,
    required this.low,
    required this.goal,
    required this.high,
    this.formatValue,
  });

  /// Fraction of the low-high span added as empty margin on each side.
  static const _breathingRoom = 0.2;

  @override
  Widget build(BuildContext context) {
    final format = formatValue ?? Units.format;
    final span = (high - low).abs() < 1e-9 ? 1.0 : (high - low);
    final pad = span * _breathingRoom;
    final domainMin = low - pad;
    final domainMax = high + pad;
    final domainSpan = domainMax - domainMin;

    double xFraction(double v) => (v - domainMin) / domainSpan;

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        double xOf(double v) => xFraction(v) * width;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: 40,
              child: CustomPaint(
                size: Size(width, 40),
                painter: _WhiskerPainter(
                  xLow: xOf(low),
                  xGoal: xOf(goal),
                  xHigh: xOf(high),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.small),
            SizedBox(
              height: 18,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  _alignedLabel(xOf(low), format(low), AppText.smallText),
                  _alignedLabel(xOf(goal), format(goal), AppText.subHeader),
                  _alignedLabel(xOf(high), format(high), AppText.smallText),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  /// Centers [text] under pixel position [x] via a fixed-width box straddling
  /// it, rather than assuming the three labels are evenly spaced.
  Widget _alignedLabel(double x, String text, TextStyle style) {
    const labelWidth = 64.0;
    return Positioned(
      left: x - labelWidth / 2,
      width: labelWidth,
      child: Text(text, style: style, textAlign: TextAlign.center),
    );
  }
}

class _WhiskerPainter extends CustomPainter {
  final double xLow;
  final double xGoal;
  final double xHigh;
  const _WhiskerPainter({required this.xLow, required this.xGoal, required this.xHigh});

  @override
  void paint(Canvas canvas, Size size) {
    final midY = size.height / 2;

    final linePaint = Paint()
      ..color = AppColors.textSecondary
      ..strokeWidth = 2;
    canvas.drawLine(Offset(xLow, midY), Offset(xHigh, midY), linePaint);

    // Whisker caps at low/high.
    canvas.drawLine(Offset(xLow, midY - 10), Offset(xLow, midY + 10), linePaint);
    canvas.drawLine(Offset(xHigh, midY - 10), Offset(xHigh, midY + 10), linePaint);

    // Goal marker — the expected/mean value.
    canvas.drawCircle(Offset(xGoal, midY), 8, Paint()..color = AppColors.accent);
  }

  @override
  bool shouldRepaint(_WhiskerPainter old) =>
      old.xLow != xLow || old.xGoal != xGoal || old.xHigh != xHigh;
}
