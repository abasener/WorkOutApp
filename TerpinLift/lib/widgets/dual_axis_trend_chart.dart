import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../services/comparison_data_service.dart';
import '../theme/app_theme.dart';

/// One series on a [DualAxisTrendChart], pre-aggregated by
/// `ComparisonDataService.aggregateForCharts` before reaching this widget:
/// one point per day (summed) for an ordinary numeric series, but every raw
/// entry kept as its own point for a non-ordinal categorical series, since a
/// day with two different sore body parts is genuinely two points, not one
/// summed value.
class DualAxisSeries {
  final List<ComparisonEntry> points;
  final Color color;

  /// True only for a non-ordinal categorical series ("Soreness (by body
  /// part)") — draws dots at fixed [categoryLabels] positions instead of a
  /// data-driven numeric range, and skips the *dashed trend* line (no
  /// meaningful trend shape for "which of 5 unordered body parts"). The
  /// solid line still connects every point in date order same as any other
  /// series — deliberately unconventional (multiple points can share an
  /// x-position on a multi-part day) but is what this data calls for.
  final bool isCategorical;
  final List<String> categoryLabels;

  const DualAxisSeries({
    required this.points,
    required this.color,
    this.isCategorical = false,
    this.categoryLabels = const [],
  });
}

/// The top plot on the Metric Comparison screen — two independently-scaled
/// y-axes (left = series A, right = series B) sharing one x-axis/plot area.
/// A deliberate, disclosed exception to this app's usual "never dual-axis"
/// chart convention (`00_UX_DESIGN.md`), chosen directly by the user over
/// normalizing both series to a shared 0-1 axis, specifically so real units
/// stay visible on both sides. See `05_SCREEN_metrics.md` "Metric
/// Comparison" for the full reasoning.
class DualAxisTrendChart extends StatelessWidget {
  final DualAxisSeries seriesA;
  final DualAxisSeries seriesB;
  final double height;

  const DualAxisTrendChart({
    super.key,
    required this.seriesA,
    required this.seriesB,
    this.height = 200,
  });

  @override
  Widget build(BuildContext context) {
    if (seriesA.points.isEmpty && seriesB.points.isEmpty) {
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
          painter: _DualAxisPainter(seriesA: seriesA, seriesB: seriesB),
        ),
      ),
    );
  }
}

class _AxisDomain {
  final double min;
  final double max;
  final String Function(double) format;
  const _AxisDomain(this.min, this.max, this.format);

  double yOf(double v, double top, double plotHeight) =>
      top + plotHeight - ((v - min) / (max - min)) * plotHeight;
}

class _DualAxisPainter extends CustomPainter {
  final DualAxisSeries seriesA;
  final DualAxisSeries seriesB;

  _DualAxisPainter({required this.seriesA, required this.seriesB});

  static const _leftPad = 34.0;
  static const _rightPad = 34.0;
  static const _bottomPad = 18.0;
  static const _topPad = 8.0;
  static const _yTicks = 5;
  static const _xTicks = 7;
  static const _dataFillFraction = 0.6;
  static const _trendWindowDays = 14.0;

  @override
  void paint(Canvas canvas, Size size) {
    final plotWidth = size.width - _leftPad - _rightPad;
    final plotHeight = size.height - _topPad - _bottomPad;
    if (plotWidth <= 0 || plotHeight <= 0) return;

    final allDates = [
      ...seriesA.points.map((p) => p.date),
      ...seriesB.points.map((p) => p.date),
    ]..sort();
    if (allDates.isEmpty) return;
    final firstDate = allDates.first;
    final lastDate = allDates.last;
    final totalSpanDays = lastDate
        .difference(firstDate)
        .inDays
        .toDouble()
        .clamp(1.0, double.infinity);

    double xOf(DateTime d) =>
        _leftPad +
        (d.difference(firstDate).inDays.toDouble() / totalSpanDays) * plotWidth;

    canvas.clipRect(Rect.fromLTWH(0, 0, size.width, size.height));

    // X-axis date labels, evenly spaced across the shared span.
    for (var i = 0; i < _xTicks; i++) {
      final days = totalSpanDays * i / (_xTicks - 1);
      final date = firstDate.add(Duration(days: days.round()));
      final x = _leftPad + (days / totalSpanDays) * plotWidth;
      _drawText(
        canvas,
        DateFormat('M/d').format(date),
        Offset(x - 14, size.height - _bottomPad + 4),
        9,
        AppColors.textSecondary,
      );
    }

    _paintSeries(
      canvas,
      seriesA,
      xOf,
      plotHeight,
      alignLeft: true,
      plotRight: size.width - _rightPad,
    );
    _paintSeries(
      canvas,
      seriesB,
      xOf,
      plotHeight,
      alignLeft: false,
      plotRight: size.width - _rightPad,
    );
  }

  void _paintSeries(
    Canvas canvas,
    DualAxisSeries series,
    double Function(DateTime) xOf,
    double plotHeight, {
    required bool alignLeft,
    required double plotRight,
  }) {
    if (series.points.isEmpty) return;
    final domain = _domainFor(series);

    // Y-axis labels for this series, on its own side.
    for (var i = 0; i < _yTicks; i++) {
      final v = domain.min + (domain.max - domain.min) * i / (_yTicks - 1);
      final y = domain.yOf(v, _topPad, plotHeight);
      _drawText(
        canvas,
        domain.format(v),
        Offset(alignLeft ? 0 : plotRight + 4, y - 6),
        10,
        series.color,
      );
    }

    // Solid line + dot per real point.
    final path = Path();
    final sorted = [...series.points]..sort((a, b) => a.date.compareTo(b.date));
    for (var i = 0; i < sorted.length; i++) {
      final x = xOf(sorted[i].date);
      final y = domain.yOf(sorted[i].value, _topPad, plotHeight);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = series.color
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round,
    );
    for (final p in sorted) {
      canvas.drawCircle(
        Offset(xOf(p.date), domain.yOf(p.value, _topPad, plotHeight)),
        3.5,
        Paint()..color = series.color,
      );
    }

    // Dashed trend line — skipped entirely for a non-ordinal categorical
    // series, which has no meaningful trend shape to draw.
    if (!series.isCategorical && sorted.length >= 2) {
      final xs = sorted
          .map((p) => p.date.difference(sorted.first.date).inDays.toDouble())
          .toList();
      final ys = sorted.map((p) => p.value).toList();
      final smoothed = _trailingMovingAverage(xs, ys, _trendWindowDays);
      final trendColor = series.color.withValues(alpha: 0.55);
      for (var i = 0; i < smoothed.length - 1; i++) {
        _drawDashedLine(
          canvas,
          Offset(
            xOf(sorted[i].date),
            domain.yOf(smoothed[i], _topPad, plotHeight),
          ),
          Offset(
            xOf(sorted[i + 1].date),
            domain.yOf(smoothed[i + 1], _topPad, plotHeight),
          ),
          trendColor,
        );
      }
    }
  }

  _AxisDomain _domainFor(DualAxisSeries series) {
    if (series.isCategorical) {
      final count = series.categoryLabels.length;
      return _AxisDomain(0, (count - 1).toDouble(), (v) {
        final i = v.round().clamp(0, count - 1);
        return series.categoryLabels.isEmpty ? '' : series.categoryLabels[i];
      });
    }
    var minV = series.points
        .map((p) => p.value)
        .reduce((a, b) => a < b ? a : b);
    var maxV = series.points
        .map((p) => p.value)
        .reduce((a, b) => a > b ? a : b);
    if ((maxV - minV).abs() < 1e-6) {
      maxV += 1;
      minV -= 1;
    }
    final pad = (maxV - minV) * ((1 / _dataFillFraction - 1) / 2);
    minV -= pad;
    maxV += pad;
    return _AxisDomain(minV, maxV, (v) => v.round().toString());
  }

  List<double> _trailingMovingAverage(
    List<double> xs,
    List<double> ys,
    double window,
  ) {
    final result = <double>[];
    for (var i = 0; i < xs.length; i++) {
      final target = xs[i];
      var sum = 0.0;
      var count = 0;
      for (var j = i; j >= 0; j--) {
        if (xs[j] < target - window) break;
        sum += ys[j];
        count++;
      }
      result.add(sum / count);
    }
    return result;
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

  void _drawDashedLine(Canvas canvas, Offset start, Offset end, Color color) {
    const dashLength = 4.0;
    const gapLength = 4.0;
    final totalLength = (end - start).distance;
    if (totalLength == 0) return;
    final direction = (end - start) / totalLength;
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5;
    var traveled = 0.0;
    while (traveled < totalLength) {
      final segStart = start + direction * traveled;
      final segEnd =
          start + direction * (traveled + dashLength).clamp(0, totalLength);
      canvas.drawLine(segStart, segEnd, paint);
      traveled += dashLength + gapLength;
    }
  }

  @override
  bool shouldRepaint(_DualAxisPainter old) =>
      old.seriesA.points != seriesA.points ||
      old.seriesB.points != seriesB.points;
}
