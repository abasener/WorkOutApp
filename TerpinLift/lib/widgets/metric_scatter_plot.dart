import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// The middle plot on the Metric Comparison screen — x = metric A's value,
/// y = metric B's value, one dot per (`ComparisonDataService.scatterPairs`)
/// pair, real units on both axes (consistent with the dual-axis line chart
/// above it — no normalization here either). A non-ordinal categorical axis
/// (soreness-by-body-part) gets fixed tick positions from [categoryLabelsX]/
/// [categoryLabelsY] instead of a data-driven numeric range.
class MetricScatterPlot extends StatelessWidget {
  final List<(double, double)> pairs;
  final bool isCategoricalX;
  final bool isCategoricalY;
  final List<String> categoryLabelsX;
  final List<String> categoryLabelsY;

  /// Axis tick text is tinted with the same slot color used everywhere else
  /// on this screen (blue for A/x, aqua for B/y) — the dots themselves stay
  /// a neutral color, since a single dot represents one value from *each*
  /// metric and can't sensibly be colored as only one of them.
  final Color xLabelColor;
  final Color yLabelColor;
  final double height;

  const MetricScatterPlot({
    super.key,
    required this.pairs,
    this.isCategoricalX = false,
    this.isCategoricalY = false,
    this.categoryLabelsX = const [],
    this.categoryLabelsY = const [],
    this.xLabelColor = AppColors.textSecondary,
    this.yLabelColor = AppColors.textSecondary,
    this.height = 220,
  });

  @override
  Widget build(BuildContext context) {
    if (pairs.isEmpty) {
      return SizedBox(
        width: double.infinity,
        height: height,
        child: Center(
          child: Text('No overlapping data yet', style: AppText.smallText),
        ),
      );
    }
    return SizedBox(
      width: double.infinity,
      height: height,
      child: LayoutBuilder(
        builder: (_, constraints) => CustomPaint(
          size: Size(constraints.maxWidth, height),
          painter: _ScatterPainter(
            pairs: pairs,
            isCategoricalX: isCategoricalX,
            isCategoricalY: isCategoricalY,
            categoryLabelsX: categoryLabelsX,
            categoryLabelsY: categoryLabelsY,
            xLabelColor: xLabelColor,
            yLabelColor: yLabelColor,
          ),
        ),
      ),
    );
  }
}

class _ScatterPainter extends CustomPainter {
  final List<(double, double)> pairs;
  final bool isCategoricalX;
  final bool isCategoricalY;
  final List<String> categoryLabelsX;
  final List<String> categoryLabelsY;
  final Color xLabelColor;
  final Color yLabelColor;

  _ScatterPainter({
    required this.pairs,
    required this.isCategoricalX,
    required this.isCategoricalY,
    required this.categoryLabelsX,
    required this.categoryLabelsY,
    required this.xLabelColor,
    required this.yLabelColor,
  });

  static const _leftPad = 40.0;
  static const _bottomPad = 22.0;
  static const _topPad = 8.0;
  static const _rightPad = 8.0;
  static const _ticks = 5;
  static const _dataFillFraction = 0.6;
  static const _dotRadius = 5.0;

  @override
  void paint(Canvas canvas, Size size) {
    final plotWidth = size.width - _leftPad - _rightPad;
    final plotHeight = size.height - _topPad - _bottomPad;
    if (plotWidth <= 0 || plotHeight <= 0) return;

    final xs = pairs.map((p) => p.$1).toList();
    final ys = pairs.map((p) => p.$2).toList();
    final (xMin, xMax, xLabels) = _domain(xs, isCategoricalX, categoryLabelsX);
    final (yMin, yMax, yLabels) = _domain(ys, isCategoricalY, categoryLabelsY);

    double xOf(double v) => _leftPad + ((v - xMin) / (xMax - xMin)) * plotWidth;
    double yOf(double v) =>
        _topPad + plotHeight - ((v - yMin) / (yMax - yMin)) * plotHeight;

    canvas.clipRect(Rect.fromLTWH(0, 0, size.width, size.height));

    for (var i = 0; i < _ticks; i++) {
      final xv = xMin + (xMax - xMin) * i / (_ticks - 1);
      final x = xOf(xv);
      canvas.drawLine(
        Offset(x, _topPad),
        Offset(x, size.height - _bottomPad),
        Paint()
          ..color = AppColors.border
          ..strokeWidth = 1,
      );
      _drawText(
        canvas,
        xLabels(xv),
        Offset(x - 12, size.height - _bottomPad + 4),
        9,
        xLabelColor,
      );

      final yv = yMin + (yMax - yMin) * i / (_ticks - 1);
      final y = yOf(yv);
      canvas.drawLine(
        Offset(_leftPad, y),
        Offset(size.width - _rightPad, y),
        Paint()
          ..color = AppColors.border
          ..strokeWidth = 1,
      );
      _drawText(canvas, yLabels(yv), Offset(0, y - 6), 10, yLabelColor);
    }

    for (final pair in pairs) {
      canvas.drawCircle(
        Offset(xOf(pair.$1), yOf(pair.$2)),
        _dotRadius,
        Paint()..color = AppColors.accent.withValues(alpha: 0.75),
      );
    }
  }

  (double, double, String Function(double)) _domain(
    List<double> values,
    bool isCategorical,
    List<String> labels,
  ) {
    if (isCategorical) {
      final count = labels.length;
      return (
        0,
        (count - 1).toDouble(),
        (v) {
          final i = v.round().clamp(0, count - 1);
          return labels.isEmpty ? '' : labels[i];
        },
      );
    }
    var minV = values.reduce((a, b) => a < b ? a : b);
    var maxV = values.reduce((a, b) => a > b ? a : b);
    if ((maxV - minV).abs() < 1e-6) {
      maxV += 1;
      minV -= 1;
    }
    final pad = (maxV - minV) * ((1 / _dataFillFraction - 1) / 2);
    minV -= pad;
    maxV += pad;
    return (minV, maxV, (v) => v.round().toString());
  }

  void _drawText(
    Canvas canvas,
    String text,
    Offset offset,
    double fontSize,
    Color color,
  ) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(color: color, fontSize: fontSize),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(canvas, offset);
  }

  @override
  bool shouldRepaint(_ScatterPainter old) => old.pairs != pairs;
}
