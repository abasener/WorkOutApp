import 'package:flutter/material.dart';
import 'package:flutter_body_heatmap/flutter_body_heatmap.dart';

import '../../theme/app_theme.dart';

/// One-time-entry muscle picker for an exercise's [Exercise.targetMuscles] —
/// tap a muscle to toggle it in/out of the selected set (no severity level,
/// unlike the soreness map, since this is just "does this lift hit this
/// muscle," not a repeated log). Shows every muscle the body-heatmap package
/// exposes, not just the app's 5 broad soreness groups, since this is a
/// one-time, precise input rather than a quick daily tap. Returns the final
/// `Set<Muscle>` via `Navigator.pop` when Save is pressed, `null` on cancel —
/// callers decide whether/when to persist it (immediately, for the edit-page
/// button; staged into wizard state, for a new exercise).
class MuscleSelectorSheet extends StatefulWidget {
  final Set<Muscle> initialSelection;
  const MuscleSelectorSheet({super.key, this.initialSelection = const {}});

  @override
  State<MuscleSelectorSheet> createState() => _MuscleSelectorSheetState();
}

class _MuscleSelectorSheetState extends State<MuscleSelectorSheet> {
  late final Set<Muscle> _selected = {...widget.initialSelection};

  void _toggle(Muscle muscle, MuscleSide side) {
    setState(() {
      if (_selected.contains(muscle)) {
        _selected.remove(muscle);
      } else {
        _selected.add(muscle);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final data = <Muscle, MuscleData>{
      for (final m in _selected) m: const MuscleData(intensity: 1.0),
    };

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
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
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Select Muscles', style: AppText.subHeader),
              const SizedBox(height: AppSpacing.small),
              Text('Tap every muscle this movement targets.', style: AppText.smallText),
              const SizedBox(height: AppSpacing.standard),
              // Full width, stacked front-then-back (not side-by-side at half
              // width) — same layout as the soreness map. Small muscles were
              // too easy to mis-tap at half width; this is also what makes
              // this a genuinely muscle-level (not just region-level) picker
              // in practice, not only in theory.
              SizedBox(
                width: double.infinity,
                child: AspectRatio(
                  aspectRatio: 724 / 1448,
                  child: BodyHeatmap(
                    side: BodySide.front,
                    data: data,
                    colors: const [AppColors.surfaceRaised, AppColors.muscleHigh],
                    bodyColor: AppColors.surface,
                    borderColor: AppColors.textSecondary,
                    showBorder: true,
                    onMusclePressed: _toggle,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.standard),
              SizedBox(
                width: double.infinity,
                child: AspectRatio(
                  aspectRatio: 724 / 1448,
                  child: BodyHeatmap(
                    side: BodySide.back,
                    data: data,
                    colors: const [AppColors.surfaceRaised, AppColors.muscleHigh],
                    bodyColor: AppColors.surface,
                    borderColor: AppColors.textSecondary,
                    showBorder: true,
                    onMusclePressed: _toggle,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.standard),
              Text(
                _selected.isEmpty
                    ? 'No muscles selected yet.'
                    : _selected.map((m) => m.name).join(', '),
                style: AppText.smallText,
              ),
              const SizedBox(height: AppSpacing.large),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadius.button)),
                  ),
                  onPressed: () => Navigator.pop(context, _selected),
                  child: const Text('Save'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
