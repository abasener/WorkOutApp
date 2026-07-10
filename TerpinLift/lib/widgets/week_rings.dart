import 'dart:math';

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Replaces the plain checkmark week strip: each day gets a ring that fills
/// based on % of the 10,000-step goal, with the inside filled in if a
/// workout was logged that day. Meant to read as informative progress
/// rather than a pass/fail checkmark.
class WeekRings extends StatelessWidget {
  final Map<String, double> stepsByDate; // 'YYYY-MM-DD' -> steps
  final Set<String> workoutDates;

  const WeekRings({super.key, required this.stepsByDate, required this.workoutDates});

  static const _stepsGoal = 10000.0;

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final days = List.generate(7, (i) => today.subtract(Duration(days: 6 - i)));
    const labels = ['S', 'M', 'T', 'W', 'T', 'F', 'S'];

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: days.map((d) {
        final key = d.toIso8601String().substring(0, 10);
        final steps = stepsByDate[key] ?? 0;
        final pct = (steps / _stepsGoal).clamp(0.0, 1.0);
        final worked = workoutDates.contains(key);

        return Column(
          children: [
            SizedBox(
              width: 34,
              height: 34,
              child: CustomPaint(painter: _RingPainter(pct: pct, workedOut: worked)),
            ),
            const SizedBox(height: AppSpacing.micro),
            Text(labels[d.weekday % 7], style: AppText.smallText),
          ],
        );
      }).toList(),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double pct;
  final bool workedOut;
  const _RingPainter({required this.pct, required this.workedOut});

  static const _strokeWidth = 4.0;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2 - _strokeWidth / 2 - 1;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      0,
      2 * pi,
      false,
      Paint()
        ..color = AppColors.border
        ..style = PaintingStyle.stroke
        ..strokeWidth = _strokeWidth,
    );

    if (pct > 0) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        -pi / 2,
        2 * pi * pct,
        false,
        Paint()
          ..color = AppColors.accent
          ..style = PaintingStyle.stroke
          ..strokeWidth = _strokeWidth
          ..strokeCap = StrokeCap.round,
      );
    }

    if (workedOut) {
      canvas.drawCircle(
        center,
        radius - _strokeWidth,
        Paint()..color = AppColors.accent.withValues(alpha: 0.35),
      );
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.pct != pct || old.workedOut != workedOut;
}
