import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// A small glyph (edit pencil, delete, history) that still needs a real tap
/// target — a bare `Icon` wrapped directly in `GestureDetector` ends up with
/// a tap area equal to the icon's own pixel size (often 16-20px), well under
/// Android's ~40-48dp guidance. This pads the invisible hit area out to a
/// consistent circle without changing how big the glyph looks, and gets a
/// ripple for free via `InkResponse`.
class TapIcon extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final double size;
  final Color? color;
  final double tapRadius;
  final String? tooltip;

  const TapIcon({
    super.key,
    required this.icon,
    required this.onTap,
    this.size = 18,
    this.color,
    this.tapRadius = 20,
    this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    final button = InkResponse(
      onTap: onTap,
      radius: tapRadius,
      child: Padding(
        padding: EdgeInsets.all(tapRadius - size / 2),
        child: Icon(icon, size: size, color: color ?? AppColors.textSecondary),
      ),
    );
    return tooltip == null ? button : Tooltip(message: tooltip!, child: button);
  }
}
