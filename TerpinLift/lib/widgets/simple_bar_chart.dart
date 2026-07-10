import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Small labeled bar chart — used where a full axis-labeled chart is overkill
/// (e.g. period/cycle length variability on the Cycle detail screen).
class SimpleBarChart extends StatelessWidget {
  final List<double> values;
  final Color color;
  final double height;

  const SimpleBarChart({
    super.key,
    required this.values,
    this.color = AppColors.accent,
    this.height = 90,
  });

  @override
  Widget build(BuildContext context) {
    if (values.isEmpty) {
      return SizedBox(
        height: height,
        child: Center(child: Text('No data yet', style: AppText.smallText)),
      );
    }
    final maxV = values.reduce((a, b) => a > b ? a : b).clamp(1.0, double.infinity);
    const labelHeight = 16.0;
    final barAreaHeight = height - labelHeight;

    return SizedBox(
      height: height,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: values.map((v) {
          final barHeight = (v / maxV) * barAreaHeight;
          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(v.round().toString(),
                      style: AppText.smallText.copyWith(fontSize: 9)),
                  const SizedBox(height: 2),
                  Container(
                    height: barHeight,
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}
