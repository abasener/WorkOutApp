import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../theme/app_theme.dart';

class ChartPoint {
  final DateTime date;
  final double value;

  /// Rep count this point represents, if any — encoded as dot size (1 rep =
  /// smallest, 21+ reps = largest) so a chart mixing rep ranges (e.g. a
  /// heavy-single day next to a high-rep day) reads as "that one's odd
  /// because it was a different rep range," not just noise. `null` draws the
  /// default fixed-size dot.
  final int? reps;

  /// An alternate series used only to shape the dashed trend line — e.g. a
  /// gender-scaled e1RM estimate, when [value] itself is a raw weight that
  /// isn't comparable point-to-point (different rep counts each session).
  /// `null` fits the trend line on [value] directly (the original behavior).
  /// The fitted curve is shifted to sit centered on the actual [value] data
  /// rather than plotted on its own scale, so it never reads as "off the
  /// chart" — its *shape* reflects this alternate series, its *position*
  /// stays anchored to what's actually plotted.
  final double? trendValue;

  const ChartPoint(this.date, this.value, {this.reps, this.trendValue});
}

/// A `LabeledTrendChart` sized to a fixed width:height aspect ratio (taller
/// than the plain fixed-height default) instead of a hardcoded pixel height.
/// Full width, same as a bare `LabeledTrendChart` — the only difference is
/// how the height is computed. Used for the lift e1RM charts (Home + Lift
/// detail), which read as too compressed at the old fixed height.
class CenteredTrendChart extends StatelessWidget {
  final List<ChartPoint> points;
  final bool showPrediction;
  final Color color;
  final TrendStyle trendStyle;
  final double trendWindowDays;
  final String Function(double)? yLabelFormatter;

  /// Width:height ratio, e.g. 2.0 = twice as wide as it is tall.
  final double aspectRatio;

  const CenteredTrendChart({
    super.key,
    required this.points,
    this.showPrediction = false,
    this.color = AppColors.accent,
    this.trendStyle = TrendStyle.movingAverage,
    this.trendWindowDays = 21,
    this.yLabelFormatter,
    this.aspectRatio = 2.0,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final chartHeight = constraints.maxWidth / aspectRatio;
        return LabeledTrendChart(
          points: points,
          showPrediction: showPrediction,
          color: color,
          trendStyle: trendStyle,
          trendWindowDays: trendWindowDays,
          yLabelFormatter: yLabelFormatter,
          height: chartHeight,
        );
      },
    );
  }
}

/// Which math describes this metric's trend line — see designFiles/07_SMART_TRENDS.md
/// "Chart trend lines" section for the reasoning behind each.
enum TrendStyle {
  /// Trailing moving-average curve (can bend/plateau/shift pace over time).
  /// Right for things that are naturally noisy day-to-day but not expected to
  /// grow indefinitely: sleep, steps, bodyweight. [trendWindowDays] controls
  /// how much smoothing vs. how fast it reacts to a real recent shift.
  movingAverage,

  /// Adaptive-degree polynomial least-squares fit, drawn over historical data
  /// only. Right for lift e1RM: captures "fast early gains, slowing/
  /// plateauing later," including multiple plateaus, without hand-picking a
  /// fixed degree. Degree is chosen by simple model selection: try degree
  /// 2, 3, 4, 5 in order and stop at the lowest one whose R² clears a
  /// threshold (see `_fitBestPolynomial`) — the same idea AIC/BIC or
  /// cross-validation formalize, just via a flat R² cutoff since the data
  /// volume here doesn't warrant more machinery than that. The predicted
  /// segment continues as a straight line at the curve's own tangent slope
  /// at the last data point, rather than extrapolating the raw polynomial
  /// (which is what would risk swinging wildly past the known data —
  /// Runge's phenomenon, worse at higher degrees).
  polynomial,
}

/// Shared chart used across Home/Metrics/Lift detail: dots connected by a
/// solid line for actual logged values, plus a light dashed grey trend line
/// (shape depends on [trendStyle] — see that enum). When [showPrediction] is
/// true, the x-axis is widened so the last real data point sits at ~75%
/// across, and the trend continues into the remaining 25% as the
/// "predicted" future. 7 x-axis ticks, 5 y-axis ticks, evenly spaced in
/// time/value rather than snapped to exact data points.
class LabeledTrendChart extends StatelessWidget {
  final List<ChartPoint> points;
  final bool showPrediction;
  final Color color;
  final double height;
  final String Function(double)? yLabelFormatter;
  final TrendStyle trendStyle;

  /// Trailing window, in days, used by [TrendStyle.movingAverage]. Ignored
  /// for [TrendStyle.polynomial].
  final double trendWindowDays;

  const LabeledTrendChart({
    super.key,
    required this.points,
    this.showPrediction = false,
    this.color = AppColors.accent,
    this.height = 160,
    this.yLabelFormatter,
    this.trendStyle = TrendStyle.movingAverage,
    this.trendWindowDays = 21,
  });

  @override
  Widget build(BuildContext context) {
    if (points.length < 2) {
      return SizedBox(
        width: double.infinity,
        height: height,
        child: Center(
          child: Text(
            points.isEmpty ? 'No data yet' : 'Log a bit more to see a trend',
            style: AppText.smallText,
          ),
        ),
      );
    }
    final sorted = [...points]..sort((a, b) => a.date.compareTo(b.date));
    return SizedBox(
      width: double.infinity,
      height: height,
      child: LayoutBuilder(
        builder: (_, constraints) => CustomPaint(
          size: Size(constraints.maxWidth, height),
          painter: _ChartPainter(
            points: sorted,
            showPrediction: showPrediction,
            color: color,
            yLabelFormatter: yLabelFormatter ?? (v) => v.round().toString(),
            trendStyle: trendStyle,
            trendWindowDays: trendWindowDays,
          ),
        ),
      ),
    );
  }
}

class _ChartPainter extends CustomPainter {
  final List<ChartPoint> points;
  final bool showPrediction;
  final Color color;
  final String Function(double) yLabelFormatter;
  final TrendStyle trendStyle;
  final double trendWindowDays;

  _ChartPainter({
    required this.points,
    required this.showPrediction,
    required this.color,
    required this.yLabelFormatter,
    required this.trendStyle,
    required this.trendWindowDays,
  });

  static const _leftPad = 34.0;
  static const _bottomPad = 18.0;
  static const _topPad = 8.0;
  static const _rightPad = 4.0;
  static const _yTicks = 5;
  static const _xTicks = 7;

  /// Fraction of the plot's vertical space the actual logged data should
  /// occupy — the rest splits evenly as empty margin above/below.
  static const _dataFillFraction = 0.6;

  @override
  void paint(Canvas canvas, Size size) {
    final plotWidth = size.width - _leftPad - _rightPad;
    final plotHeight = size.height - _topPad - _bottomPad;
    if (plotWidth <= 0 || plotHeight <= 0) return;

    final firstDate = points.first.date;
    final lastDate = points.last.date;
    final dataSpanDays =
        lastDate.difference(firstDate).inDays.toDouble().clamp(1.0, double.infinity);
    final totalSpanDays = showPrediction ? dataSpanDays / 0.75 : dataSpanDays;

    double xOfDays(double days) => _leftPad + (days / totalSpanDays) * plotWidth;
    double xOf(DateTime d) => xOfDays(d.difference(firstDate).inDays.toDouble());

    final xs = points.map((p) => p.date.difference(firstDate).inDays.toDouble()).toList();
    final ys = points.map((p) => p.value).toList();
    // Fit the trend line's shape on `trendValue` when provided (e.g. e1RM,
    // comparable across different rep counts), falling back to `value`
    // itself otherwise — see [ChartPoint.trendValue].
    final trendYs = points.map((p) => p.trendValue ?? p.value).toList();
    // The fitted curve is computed on `trendYs`, which can be a totally
    // different axis than the raw `value`s actually being plotted (e.g. an
    // e1RM estimate vs. a raw per-session weight) — shift the whole curve by
    // a constant so it ends up centered on the real data instead of floating
    // off to one side or past the chart's own bounds. A no-op (0) when no
    // point supplies a `trendValue`.
    final shift = points.any((p) => p.trendValue != null)
        ? (ys.reduce((a, b) => a + b) / ys.length) -
            (trendYs.reduce((a, b) => a + b) / trendYs.length)
        : 0.0;

    // Trend curve: a list of (x, y) samples to connect with dashed segments
    // across the historical range, plus one more point at totalSpanDays if
    // showPrediction — computed differently per trendStyle.
    final List<(double, double)> trendCurve;
    final double predictedEndValue;
    switch (trendStyle) {
      case TrendStyle.movingAverage:
        final smoothed = _trailingMovingAverage(xs, trendYs, trendWindowDays);
        trendCurve = [for (var i = 0; i < xs.length; i++) (xs[i], smoothed[i] + shift)];
        final slope = _trailingSlope(xs, smoothed, trendWindowDays);
        predictedEndValue = smoothed.last + slope * (totalSpanDays - xs.last) + shift;
      case TrendStyle.polynomial:
        final coeffs = _fitBestPolynomial(xs, trendYs);
        double curveAt(double x) => _evalPoly(coeffs, x);
        double derivativeAt(double x) => _evalPolyDerivative(coeffs, x);
        const samples = 40;
        trendCurve = [
          for (var i = 0; i <= samples; i++)
            (
              xs.first + (xs.last - xs.first) * i / samples,
              curveAt(xs.first + (xs.last - xs.first) * i / samples) + shift,
            ),
        ];
        final tangentSlope = derivativeAt(xs.last);
        predictedEndValue = curveAt(xs.last) + tangentSlope * (totalSpanDays - xs.last) + shift;
    }

    // Domain is based on the actual logged data only — NOT the trend curve or
    // predicted value — so real data always occupies the center
    // _dataFillFraction of the plot's vertical space (empty margin split
    // evenly above the highest point and below the lowest), rather than
    // getting compressed into a smaller band whenever the trend/prediction
    // happens to reach further than the data.
    var minV = ys.reduce((a, b) => a < b ? a : b);
    var maxV = ys.reduce((a, b) => a > b ? a : b);
    if ((maxV - minV).abs() < 1e-6) {
      maxV += 1;
      minV -= 1;
    }
    final pad = (maxV - minV) * ((1 / _dataFillFraction - 1) / 2);
    minV -= pad;
    maxV += pad;

    double yOf(double v) =>
        _topPad + plotHeight - ((v - minV) / (maxV - minV)) * plotHeight;

    // The trend/prediction can still fall outside this data-defined range
    // (e.g. a rising prediction) — clip so it never bleeds past the chart's
    // own bounds into surrounding UI.
    canvas.clipRect(Rect.fromLTWH(0, 0, size.width, size.height));

    // Y-axis gridlines + labels.
    for (var i = 0; i < _yTicks; i++) {
      final v = minV + (maxV - minV) * i / (_yTicks - 1);
      final y = yOf(v);
      canvas.drawLine(
        Offset(_leftPad, y),
        Offset(size.width - _rightPad, y),
        Paint()
          ..color = AppColors.border
          ..strokeWidth = 1,
      );
      _drawText(canvas, yLabelFormatter(v), Offset(0, y - 6), 10);
    }

    // X-axis labels, evenly spaced across the full (possibly extended) domain.
    for (var i = 0; i < _xTicks; i++) {
      final days = totalSpanDays * i / (_xTicks - 1);
      final date = firstDate.add(Duration(days: days.round()));
      final x = xOfDays(days);
      _drawText(
        canvas,
        DateFormat('M/d').format(date),
        Offset(x - 14, size.height - _bottomPad + 4),
        9,
      );
    }

    // Dashed grey trend curve across the historical range.
    for (var i = 0; i < trendCurve.length - 1; i++) {
      _drawDashedLine(
        canvas,
        Offset(xOfDays(trendCurve[i].$1), yOf(trendCurve[i].$2)),
        Offset(xOfDays(trendCurve[i + 1].$1), yOf(trendCurve[i + 1].$2)),
        AppColors.textFaint,
      );
    }
    // Dashed continuation into the predicted region.
    if (showPrediction) {
      _drawDashedLine(
        canvas,
        Offset(xOfDays(trendCurve.last.$1), yOf(trendCurve.last.$2)),
        Offset(xOfDays(totalSpanDays), yOf(predictedEndValue)),
        AppColors.textFaint,
      );
    }

    // Actual data: solid line + dot per logged point.
    final path = Path();
    for (var i = 0; i < points.length; i++) {
      final x = xOf(points[i].date);
      final y = yOf(points[i].value);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round,
    );
    for (final p in points) {
      canvas.drawCircle(Offset(xOf(p.date), yOf(p.value)), _dotRadius(p.reps), Paint()..color = color);
    }
  }

  /// Dot radius encoding rep count — 1 rep is the smallest dot, 21+ reps the
  /// largest, so a chart mixing rep ranges reads as "that point's low
  /// because it was a high-rep day," not just an unexplained outlier.
  /// `null` (no rep count on this point) draws the original fixed size.
  static const _minDotRadius = 3.0;
  static const _maxDotRadius = 9.0;
  double _dotRadius(int? reps) {
    if (reps == null) return 3.5;
    final t = ((reps - 1) / 20).clamp(0.0, 1.0);
    return _minDotRadius + (_maxDotRadius - _minDotRadius) * t;
  }

  /// Trailing moving average: at each point i, the mean of all points whose
  /// x falls within [x_i - window, x_i]. Naturally uses a smaller effective
  /// window near the start of the series where less history exists yet.
  List<double> _trailingMovingAverage(List<double> xs, List<double> ys, double window) {
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

  /// Slope of the smoothed series over its own trailing window — this is
  /// what the predicted segment extrapolates, so a currently-flat metric
  /// predicts flat and a currently-shifting one predicts continued movement
  /// at roughly its recent pace.
  double _trailingSlope(List<double> xs, List<double> smoothed, double window) {
    final lastX = xs.last;
    var refIdx = 0;
    for (var i = 0; i < xs.length; i++) {
      if (xs[i] <= lastX - window) refIdx = i;
    }
    final dx = (lastX - xs[refIdx]).clamp(1.0, double.infinity);
    return (smoothed.last - smoothed[refIdx]) / dx;
  }

  /// Model selection: try polynomial degrees 2..5 in order, stop at the
  /// lowest degree whose R² clears [_r2Threshold]. Degree is also capped by
  /// how much data exists (at least ~4 points per coefficient) so a short
  /// history can't produce an overfit high-degree squiggle — falls back to
  /// the best-fitting degree tried if none clear the threshold.
  static const _r2Threshold = 0.92;
  static const _maxDegree = 5;
  static const _minDegree = 2;
  static const _pointsPerCoeff = 4;

  List<double> _fitBestPolynomial(List<double> xs, List<double> ys) {
    final n = xs.length;
    final meanY = ys.reduce((a, b) => a + b) / n;
    final ssTot = ys.map((y) => (y - meanY) * (y - meanY)).reduce((a, b) => a + b);

    final degreeCap = ((n / _pointsPerCoeff) - 1).floor().clamp(1, _maxDegree);
    if (degreeCap < _minDegree) {
      // Not enough data for even a quadratic — fall back to a straight line.
      return _fitPolynomial(xs, ys, 1) ?? [meanY];
    }

    List<double>? best;
    var bestR2 = double.negativeInfinity;
    for (var degree = _minDegree; degree <= degreeCap; degree++) {
      final coeffs = _fitPolynomial(xs, ys, degree);
      if (coeffs == null) continue; // degenerate system, skip this degree
      final ssRes = List.generate(n, (i) => ys[i] - _evalPoly(coeffs, xs[i]))
          .map((e) => e * e)
          .reduce((a, b) => a + b);
      final r2 = ssTot < 1e-9 ? 1.0 : 1 - ssRes / ssTot;
      if (r2 > bestR2) {
        bestR2 = r2;
        best = coeffs;
      }
      if (r2 >= _r2Threshold) return coeffs; // lowest degree clearing the bar
    }
    return best ?? [meanY];
  }

  /// Least-squares polynomial fit y = c0 + c1*x + ... + cd*x^d via the
  /// normal equations, solved as a (d+1)x(d+1) linear system.
  List<double>? _fitPolynomial(List<double> xs, List<double> ys, int degree) {
    final size = degree + 1;
    // powerSums[k] = sum of x_i^k, for k up to 2*degree.
    final powerSums = List<double>.filled(2 * degree + 1, 0);
    for (final x in xs) {
      var p = 1.0;
      for (var k = 0; k <= 2 * degree; k++) {
        powerSums[k] += p;
        p *= x;
      }
    }
    // rhs[k] = sum of y_i * x_i^k, for k up to degree.
    final rhs = List<double>.filled(size, 0);
    for (var i = 0; i < xs.length; i++) {
      var p = 1.0;
      for (var k = 0; k < size; k++) {
        rhs[k] += ys[i] * p;
        p *= xs[i];
      }
    }
    final augmented = [
      for (var row = 0; row < size; row++)
        [for (var col = 0; col < size; col++) powerSums[row + col], rhs[row]],
    ];
    return _solveLinearSystem(augmented);
  }

  /// Gaussian elimination with partial pivoting for an NxN+1 augmented matrix.
  List<double>? _solveLinearSystem(List<List<double>> m) {
    final size = m.length;
    final a = [for (final row in m) [...row]];
    for (var col = 0; col < size; col++) {
      var pivot = col;
      for (var row = col + 1; row < size; row++) {
        if (a[row][col].abs() > a[pivot][col].abs()) pivot = row;
      }
      if (a[pivot][col].abs() < 1e-9) return null;
      final tmp = a[col];
      a[col] = a[pivot];
      a[pivot] = tmp;
      for (var row = 0; row < size; row++) {
        if (row == col) continue;
        final factor = a[row][col] / a[col][col];
        for (var k = col; k <= size; k++) {
          a[row][k] -= factor * a[col][k];
        }
      }
    }
    return [for (var i = 0; i < size; i++) a[i][size] / a[i][i]];
  }

  double _evalPoly(List<double> coeffs, double x) {
    var result = 0.0;
    var p = 1.0;
    for (final c in coeffs) {
      result += c * p;
      p *= x;
    }
    return result;
  }

  double _evalPolyDerivative(List<double> coeffs, double x) {
    var result = 0.0;
    var p = 1.0;
    for (var i = 1; i < coeffs.length; i++) {
      result += i * coeffs[i] * p;
      p *= x;
    }
    return result;
  }

  void _drawText(Canvas canvas, String text, Offset offset, double fontSize) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(color: AppColors.textSecondary, fontSize: fontSize),
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
      final segEnd = start + direction * (traveled + dashLength).clamp(0, totalLength);
      canvas.drawLine(segStart, segEnd, paint);
      traveled += dashLength + gapLength;
    }
  }

  @override
  bool shouldRepaint(_ChartPainter old) =>
      old.points != points ||
      old.showPrediction != showPrediction ||
      old.color != color ||
      old.trendStyle != trendStyle ||
      old.trendWindowDays != trendWindowDays;
}
