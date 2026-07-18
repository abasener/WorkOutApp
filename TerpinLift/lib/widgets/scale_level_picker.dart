import 'package:flutter/material.dart';

import '../data/models/custom_metric.dart';
import '../theme/app_theme.dart';

/// Generalized version of `FlameLevelPicker` for custom scale-kind metrics —
/// same fill-to-tap interaction (tap level N fills 1..N; tapping the current
/// top level again clears to 0), but the icon is whichever [icon] the metric
/// was built with, not always a flame.
class ScaleLevelPicker extends StatelessWidget {
  final int level; // 0-max
  final int max;
  final ScaleIcon icon;
  final ValueChanged<int> onChanged;

  const ScaleLevelPicker({
    super.key,
    required this.level,
    required this.max,
    required this.icon,
    required this.onChanged,
  });

  IconData get _filledIcon => switch (icon) {
        ScaleIcon.flame => Icons.local_fire_department,
        ScaleIcon.star => Icons.star,
        ScaleIcon.dot => Icons.circle,
        ScaleIcon.heart => Icons.favorite,
        ScaleIcon.bolt => Icons.bolt,
        ScaleIcon.moon => Icons.bedtime,
        ScaleIcon.drop => Icons.water_drop,
      };

  IconData get _outlinedIcon => switch (icon) {
        ScaleIcon.flame => Icons.local_fire_department_outlined,
        ScaleIcon.star => Icons.star_border,
        ScaleIcon.dot => Icons.circle_outlined,
        ScaleIcon.heart => Icons.favorite_border,
        ScaleIcon.bolt => Icons.bolt_outlined,
        ScaleIcon.moon => Icons.bedtime_outlined,
        ScaleIcon.drop => Icons.water_drop_outlined,
      };

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(max, (i) {
        final thisLevel = i + 1;
        final filled = thisLevel <= level;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: GestureDetector(
            onTap: () => onChanged(level == thisLevel ? 0 : thisLevel),
            child: Icon(
              filled ? _filledIcon : _outlinedIcon,
              size: 32,
              color: AppColors.accent,
            ),
          ),
        );
      }),
    );
  }
}
