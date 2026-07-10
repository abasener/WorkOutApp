import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// 0-5 soreness-level picker using flame icons instead of a keyboard/number
/// field — tapping flame N fills 1..N (sets level = N); tapping the
/// currently-filled top flame again clears back to 0. Same fill-to-tap
/// interaction as the cycle flow picker, just flame-shaped. Deliberately
/// coarser than a 1-10 scale — trades some precision for a much nicer,
/// keyboard-free interface.
class FlameLevelPicker extends StatelessWidget {
  final int level; // 0-5
  final ValueChanged<int> onChanged;

  const FlameLevelPicker({super.key, required this.level, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(5, (i) {
        final flameLevel = i + 1;
        final filled = flameLevel <= level;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: GestureDetector(
            onTap: () => onChanged(level == flameLevel ? 0 : flameLevel),
            child: Icon(
              Icons.local_fire_department,
              size: 32,
              color: filled ? AppColors.accent : AppColors.border,
            ),
          ),
        );
      }),
    );
  }
}
