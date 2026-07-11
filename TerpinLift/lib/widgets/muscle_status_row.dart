import 'package:flutter/material.dart';

import '../data/models/exercise.dart';
import '../services/readiness_engine.dart';
import '../theme/app_theme.dart';

/// One icon per broad muscle category, replacing the old plain-text Home
/// Status flags. Icon shape carries *which* status (bed = resting, weight =
/// ready, warning = overreaching); color carries urgency — resting is
/// deliberately muted/grey (it's the normal, expected state, nothing to act
/// on), ready and overreaching are colored (both worth noticing, in
/// opposite directions). Tapping a chip explains the specific category.
class MuscleStatusRow extends StatelessWidget {
  final List<CategoryStatus> statuses;
  const MuscleStatusRow({super.key, required this.statuses});

  static const _categoryLabels = {
    ExerciseCategory.legs: 'Legs',
    ExerciseCategory.back: 'Back',
    ExerciseCategory.chest: 'Chest',
    ExerciseCategory.core: 'Core',
    ExerciseCategory.arms: 'Arms',
  };

  IconData _iconFor(MuscleGroupStatus status) {
    switch (status) {
      case MuscleGroupStatus.ready:
        return Icons.fitness_center;
      case MuscleGroupStatus.resting:
        return Icons.bed;
      case MuscleGroupStatus.overreaching:
        return Icons.warning_amber_rounded;
    }
  }

  Color _colorFor(MuscleGroupStatus status) {
    switch (status) {
      case MuscleGroupStatus.ready:
        return AppColors.good;
      case MuscleGroupStatus.resting:
        return AppColors.textSecondary;
      case MuscleGroupStatus.overreaching:
        return AppColors.warn;
    }
  }

  String _explanationFor(ExerciseCategory category, MuscleGroupStatus status) {
    final label = _categoryLabels[category] ?? category.label;
    switch (status) {
      case MuscleGroupStatus.ready:
        return '$label looks recovered — a solid candidate to train today.';
      case MuscleGroupStatus.resting:
        return '$label was trained recently and is still inside its typical '
            'recovery window — nothing wrong, just give it more time.';
      case MuscleGroupStatus.overreaching:
        return "$label's effort has been creeping up while its numbers dip — "
            'a sign of pushing this one specifically too hard lately. Doesn\'t '
            'mean rest everything, just ease up on this group for a bit.';
    }
  }

  void _showExplanation(BuildContext context, CategoryStatus s) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.edge,
          AppSpacing.standard,
          AppSpacing.edge,
          AppSpacing.large,
        ),
        decoration: const BoxDecoration(
          color: AppColors.surfaceRaised,
          borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.card)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(_iconFor(s.status), color: _colorFor(s.status), size: 22),
                const SizedBox(width: AppSpacing.small),
                Text(_categoryLabels[s.category] ?? s.category.label, style: AppText.subHeader),
              ],
            ),
            const SizedBox(height: AppSpacing.small),
            Text(_explanationFor(s.category, s.status), style: AppText.bodyText),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: statuses.map((s) {
        return GestureDetector(
          onTap: () => _showExplanation(context, s),
          child: Column(
            children: [
              Icon(_iconFor(s.status), color: _colorFor(s.status), size: 26),
              const SizedBox(height: AppSpacing.micro),
              Text(
                _categoryLabels[s.category] ?? s.category.label,
                style: AppText.smallText.copyWith(fontSize: 11),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}
