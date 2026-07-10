import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Signal-strength-style readiness indicator: 5 bars of increasing height,
/// filled left-to-right up to the current 0-5 readiness score. Replaces a
/// plain "N/5" text label with something that carries more visual weight at
/// a glance, per user feedback.
class ReadinessBars extends StatelessWidget {
  final int readiness; // 0-5
  const ReadinessBars({super.key, required this.readiness});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 28,
      height: 18,
      child: CustomPaint(painter: _ReadinessPainter(readiness: readiness)),
    );
  }
}

class _ReadinessPainter extends CustomPainter {
  final int readiness;
  const _ReadinessPainter({required this.readiness});

  static const _barCount = 5;

  @override
  void paint(Canvas canvas, Size size) {
    final barWidth = (size.width - (_barCount - 1) * 2) / _barCount;
    for (var i = 0; i < _barCount; i++) {
      final barHeight = size.height * (i + 1) / _barCount;
      final x = i * (barWidth + 2);
      final rect = Rect.fromLTWH(x, size.height - barHeight, barWidth, barHeight);
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(1.5)),
        Paint()..color = i < readiness ? AppColors.accent : AppColors.border,
      );
    }
  }

  @override
  bool shouldRepaint(_ReadinessPainter old) => old.readiness != readiness;
}
