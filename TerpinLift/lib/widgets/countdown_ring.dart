import 'dart:math';

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// A large ring gauge doubling as a tappable button — the active-session
/// screen's centerpiece for both a time countdown ("03:15") and a rep
/// counter ("5 left," tap to decrement). Same fill convention as
/// `WeekRings`' small daily rings (arc sweeps clockwise from the top as
/// [progress] goes 0 -> 1), just much bigger and with a button underneath.
/// See designFiles/12_SCREEN_hiit.md.
class CountdownRing extends StatelessWidget {
  final double progress; // 0..1, fraction complete
  final String centerText;
  final String? centerSubtext;
  final VoidCallback? onTap;
  final double size;

  const CountdownRing({
    super.key,
    required this.progress,
    required this.centerText,
    this.centerSubtext,
    this.onTap,
    this.size = 220,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
            size: Size(size, size),
            painter: _CountdownRingPainter(progress: progress.clamp(0.0, 1.0)),
          ),
          Padding(
            padding: const EdgeInsets.all(18),
            child: Material(
              color: Colors.transparent,
              shape: const CircleBorder(),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: onTap,
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        centerText,
                        style: AppText.subHeader.copyWith(fontSize: 40, fontWeight: FontWeight.w700),
                      ),
                      if (centerSubtext != null) ...[
                        const SizedBox(height: AppSpacing.micro),
                        Text(centerSubtext!, style: AppText.smallText),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CountdownRingPainter extends CustomPainter {
  final double progress;
  const _CountdownRingPainter({required this.progress});

  static const _strokeWidth = 12.0;

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

    if (progress > 0) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        -pi / 2,
        2 * pi * progress,
        false,
        Paint()
          ..color = AppColors.accent
          ..style = PaintingStyle.stroke
          ..strokeWidth = _strokeWidth
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(_CountdownRingPainter old) => old.progress != progress;
}
