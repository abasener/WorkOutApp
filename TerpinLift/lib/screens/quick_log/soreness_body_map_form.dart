import 'package:flutter/material.dart';
import 'package:flutter_body_heatmap/flutter_body_heatmap.dart';

import '../../data/models/metric_entry.dart';
import '../../services/app_services.dart';
import '../../services/muscle_map.dart';
import '../../theme/app_theme.dart';
import '../../widgets/date_picker_field.dart';
import '../../widgets/flame_level_picker.dart';

/// Tap-to-log soreness: tap a body region on the heatmap, pick a 0-5 flame
/// level for that sub-region (e.g. quads/hamstrings/glutes, not just one
/// "legs" bucket), save. See designFiles/05_SCREEN_metrics.md "Soreness
/// sub-splitting" for why this is finer than the original 5 broad
/// categories, and designFiles/00_UX_DESIGN.md for the original body-map
/// interaction reasoning (coarser scale, no keyboard).
class SorenessBodyMapForm extends StatefulWidget {
  final DateTime? initialDate;
  const SorenessBodyMapForm({super.key, this.initialDate});

  @override
  State<SorenessBodyMapForm> createState() => _SorenessBodyMapFormState();
}

class _SorenessBodyMapFormState extends State<SorenessBodyMapForm> {
  late DateTime _date = widget.initialDate ?? DateTime.now();
  final Map<SorenessRegion, int> _levels = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadForDate();
  }

  String get _dateStr => _date.toIso8601String().substring(0, 10);

  Future<void> _loadForDate() async {
    setState(() => _loading = true);
    final levels = <SorenessRegion, int>{};
    for (final region in MuscleMap.sorenessRegionGroups.keys) {
      final type = MetricTypeKey.forSorenessRegion(region);
      final entries = await AppServices.metrics.getByTypeAndDate(type, _dateStr);
      if (entries.isNotEmpty) levels[region] = entries.first.value.round();
    }
    if (!mounted) return;
    setState(() {
      _levels
        ..clear()
        ..addAll(levels);
      _loading = false;
    });
  }

  Future<void> _onMuscleTap(Muscle muscle, MuscleSide side) async {
    final region = MuscleMap.regionForMuscle(muscle);
    if (region == null) return; // untracked region (neck/head/hair/hands)

    final level = await showDialog<int>(
      context: context,
      builder: (ctx) {
        var selected = _levels[region] ?? 0;
        return StatefulBuilder(
          builder: (ctx, setDialogState) => AlertDialog(
            backgroundColor: AppColors.surfaceRaised,
            title: Text(region.label, style: AppText.subHeader),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Soreness', style: AppText.smallText),
                const SizedBox(height: AppSpacing.large),
                FlameLevelPicker(
                  level: selected,
                  onChanged: (v) => setDialogState(() => selected = v),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text('Cancel', style: AppText.bodyText),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, selected),
                child: const Text('Save', style: TextStyle(color: AppColors.accent)),
              ),
            ],
          ),
        );
      },
    );
    if (level == null) return;

    final type = MetricTypeKey.forSorenessRegion(region);
    await AppServices.metrics.insert(MetricEntry(
      date: _dateStr,
      metricType: type,
      value: level.toDouble(),
      loggedAt: DateTime.now().toIso8601String(),
    ));
    AppServices.signalReload();
    if (!mounted) return;
    setState(() => _levels[region] = level);
  }

  @override
  Widget build(BuildContext context) {
    final data = <Muscle, MuscleData>{
      for (final entry in _levels.entries)
        for (final muscle in MuscleMap.sorenessRegionGroups[entry.key] ?? const <Muscle>[])
          muscle: MuscleData(intensity: entry.value / 5.0),
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
              Text('Log Soreness', style: AppText.subHeader),
              const SizedBox(height: AppSpacing.standard),
              DatePickerField(
                date: _date,
                onChanged: (d) {
                  setState(() => _date = d);
                  _loadForDate();
                },
              ),
              const SizedBox(height: AppSpacing.standard),
              Text('Tap a body part to log its soreness', style: AppText.smallText),
              const SizedBox(height: AppSpacing.standard),
              if (_loading)
                const Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(child: CircularProgressIndicator(color: AppColors.accent)),
                )
              else
                Row(
                  children: [
                    Expanded(
                      child: AspectRatio(
                        aspectRatio: 724 / 1448,
                        child: BodyHeatmap(
                          side: BodySide.front,
                          data: data,
                          colors: const [AppColors.surfaceRaised, AppColors.muscleHigh],
                          bodyColor: AppColors.surface,
                          borderColor: AppColors.textSecondary,
                          onMusclePressed: _onMuscleTap,
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.standard),
                    Expanded(
                      child: AspectRatio(
                        aspectRatio: 724 / 1448,
                        child: BodyHeatmap(
                          side: BodySide.back,
                          data: data,
                          colors: const [AppColors.surfaceRaised, AppColors.muscleHigh],
                          bodyColor: AppColors.surface,
                          borderColor: AppColors.textSecondary,
                          onMusclePressed: _onMuscleTap,
                        ),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}
