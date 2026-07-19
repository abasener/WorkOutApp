import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import 'log_cardio_form.dart';
import 'log_lift_form.dart';
import 'log_simple_metric_form.dart';
import 'soreness_body_map_form.dart';

/// Entry point opened from the bottom-nav FAB. Picker for what to log right
/// now, per designFiles/04_SCREEN_quick_log.md.
class QuickLogSheet extends StatelessWidget {
  const QuickLogSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const QuickLogSheet(),
    );
  }

  void _open(BuildContext context, Widget form) {
    Navigator.pop(context);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => form,
    );
  }

  @override
  Widget build(BuildContext context) {
    final items = <(IconData, String, Widget Function())>[
      (Icons.fitness_center, 'Lift', () => const LogLiftForm()),
      (Icons.directions_run, 'Cardio', () => const LogCardioForm()),
      (Icons.monitor_weight_outlined, 'Weight',
          () => const LogSimpleMetricForm(kind: SimpleMetricKind.bodyweight)),
      (Icons.bedtime_outlined, 'Sleep',
          () => const LogSimpleMetricForm(kind: SimpleMetricKind.sleep)),
      (Icons.directions_walk, 'Steps',
          () => const LogSimpleMetricForm(kind: SimpleMetricKind.steps)),
      (Icons.self_improvement, 'Soreness', () => const SorenessBodyMapForm()),
    ];

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surfaceRaised,
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.card)),
      ),
      padding: EdgeInsets.fromLTRB(
        AppSpacing.edge,
        AppSpacing.standard,
        AppSpacing.edge,
        AppSpacing.standard + MediaQuery.of(context).padding.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Quick Log', style: AppText.subHeader),
          const SizedBox(height: AppSpacing.large),
          GridView.count(
            crossAxisCount: 3,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: AppSpacing.standard,
            crossAxisSpacing: AppSpacing.standard,
            childAspectRatio: 1,
            children: items.map((item) {
              final (icon, label, formBuilder) = item;
              return InkWell(
                borderRadius: BorderRadius.circular(AppRadius.card),
                onTap: () => _open(context, formBuilder()),
                child: Container(
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    border: Border.all(color: AppColors.border),
                    borderRadius: BorderRadius.circular(AppRadius.card),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(icon, color: AppColors.accent, size: 28),
                      const SizedBox(height: AppSpacing.small),
                      Text(label, style: AppText.smallText),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}
