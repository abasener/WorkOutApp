import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Horizontal 5-segment readiness bar — a flatter alternative to
/// `ReadinessBars` (vertical signal-style bars) for tight spaces where
/// vertical height doesn't carry any meaning and just adds visual noise
/// (e.g. a compact stat card). Same 0-5 readiness value, same accent-fill
/// language, just laid out to use width instead of height.
class ReadinessSegmentedBar extends StatelessWidget {
  final int readiness; // 0-5
  const ReadinessSegmentedBar({super.key, required this.readiness});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 8,
      child: Row(
        children: List.generate(5, (i) {
          final filled = i < readiness;
          return Expanded(
            child: Container(
              margin: EdgeInsets.only(right: i < 4 ? 3 : 0),
              decoration: BoxDecoration(
                color: filled ? AppColors.accent : AppColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          );
        }),
      ),
    );
  }
}
