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
///
/// Tapping a muscle only stages a level locally — nothing hits the database
/// until the bottom **Save** button is pressed. Dismissing the sheet any
/// other way (the phone's hardware/gesture back, tapping outside) discards
/// whatever was staged, same as an abort — there used to be no explicit
/// save step, so the only way out was the system back gesture, which
/// silently persisted every tap along the way even though it reads like a
/// cancel action.
class SorenessBodyMapForm extends StatefulWidget {
  final DateTime? initialDate;

  /// Which slot to open to when editing a specific already-logged entry
  /// (from a Days-tab/history row that's tied to one particular AM or PM
  /// log) — lets that row's edit action land exactly on the entry it
  /// represents, rather than defaulting and possibly opening the wrong
  /// slot's (empty) map. Ignored when null: falls back to the usual
  /// time-of-day-when-fresh / AM-when-editing default.
  final SorenessTimeSlot? initialSlot;

  const SorenessBodyMapForm({super.key, this.initialDate, this.initialSlot});

  @override
  State<SorenessBodyMapForm> createState() => _SorenessBodyMapFormState();
}

class _SorenessBodyMapFormState extends State<SorenessBodyMapForm> {
  late DateTime _date = widget.initialDate ?? DateTime.now();
  // Opening fresh (no initialDate) defaults to whichever half of the day it
  // actually is, matching logging in the moment; opening to edit a specific
  // entry uses its known slot; opening to edit a day with no known slot
  // (e.g. a legacy pre-AM/PM entry) falls back to AM — simplest predictable
  // choice, one tap away from PM if that's what has data.
  late SorenessTimeSlot _slot;
  final Map<SorenessRegion, int> _levels = {};
  final Set<SorenessRegion> _dirtyRegions = {};
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _slot =
        widget.initialSlot ??
        (widget.initialDate == null
            ? (DateTime.now().hour < 12
                  ? SorenessTimeSlot.am
                  : SorenessTimeSlot.pm)
            : SorenessTimeSlot.am);
    _loadForDate();
  }

  String get _dateStr => _date.toIso8601String().substring(0, 10);

  /// Loads whatever's logged for the current `(date, slot)` combination only
  /// — switching either one reloads from scratch, discarding any unsaved
  /// local taps, same as changing the date already did before slots existed.
  Future<void> _loadForDate() async {
    setState(() => _loading = true);
    final levels = <SorenessRegion, int>{};
    for (final region in MuscleMap.sorenessRegionGroups.keys) {
      final type = MetricTypeKey.forSorenessRegion(region);
      final entry = await AppServices.metrics.getByTypeDateAndSlot(
        type,
        _dateStr,
        _slot,
      );
      if (entry != null) levels[region] = entry.value.round();
    }
    if (!mounted) return;
    setState(() {
      _levels
        ..clear()
        ..addAll(levels);
      _dirtyRegions.clear();
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
                // "Set", not "Save" — this only stages the level locally,
                // the bottom Save button is what actually persists it.
                child: const Text(
                  'Set',
                  style: TextStyle(color: AppColors.accent),
                ),
              ),
            ],
          ),
        );
      },
    );
    if (level == null) return;
    setState(() {
      _levels[region] = level;
      _dirtyRegions.add(region);
    });
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    for (final region in _dirtyRegions) {
      final type = MetricTypeKey.forSorenessRegion(region);
      // Upsert by (date, slot), not a plain insert -- this is what lets a
      // wrong past log actually be corrected instead of just piling a
      // duplicate row on top of it.
      await AppServices.metrics.upsertSorenessEntry(
        MetricEntry(
          date: _dateStr,
          metricType: type,
          value: (_levels[region] ?? 0).toDouble(),
          loggedAt: DateTime.now().toIso8601String(),
          timeSlot: _slot,
        ),
      );
    }
    AppServices.signalReload();
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final data = <Muscle, MuscleData>{
      for (final entry in _levels.entries)
        for (final muscle
            in MuscleMap.sorenessRegionGroups[entry.key] ?? const <Muscle>[])
          muscle: MuscleData(intensity: entry.value / 5.0),
    };

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        decoration: const BoxDecoration(
          color: AppColors.surfaceRaised,
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppRadius.card),
          ),
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
              Text(
                'Tap a body part to log its soreness',
                style: AppText.smallText,
              ),
              const SizedBox(height: AppSpacing.standard),
              if (_loading)
                const Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(
                    child: CircularProgressIndicator(color: AppColors.accent),
                  ),
                )
              else
                Column(
                  children: [
                    SizedBox(
                      width: double.infinity,
                      child: AspectRatio(
                        aspectRatio: 724 / 1448,
                        child: BodyHeatmap(
                          side: BodySide.front,
                          data: data,
                          colors: const [
                            AppColors.surfaceRaised,
                            AppColors.muscleHigh,
                          ],
                          bodyColor: AppColors.surface,
                          borderColor: AppColors.textSecondary,
                          onMusclePressed: _onMuscleTap,
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
                          colors: const [
                            AppColors.surfaceRaised,
                            AppColors.muscleHigh,
                          ],
                          bodyColor: AppColors.surface,
                          borderColor: AppColors.textSecondary,
                          onMusclePressed: _onMuscleTap,
                        ),
                      ),
                    ),
                  ],
                ),
              const SizedBox(height: AppSpacing.large),
              // Date + AM/PM cluster sits directly above Save on purpose —
              // "what am I about to save, and for when" reads as the last
              // confirmation before committing, not a setup step done once
              // up front.
              Row(
                children: [
                  Expanded(
                    child: DatePickerField(
                      date: _date,
                      onChanged: (d) {
                        setState(() => _date = d);
                        _loadForDate();
                      },
                    ),
                  ),
                  const SizedBox(width: AppSpacing.standard),
                  _TimeSlotToggle(
                    selected: _slot,
                    onChanged: (s) {
                      setState(() => _slot = s);
                      _loadForDate();
                    },
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.standard),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadius.button),
                    ),
                  ),
                  onPressed: _loading || _saving ? null : _save,
                  child: _saving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Save'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// AM/PM picker, same visual pattern as `_UnitToggle` in Settings (a pill
/// container, two tappable halves, accent-highlighted selection) — kept
/// private to this file rather than shared, matching how similarly small
/// per-screen toggles elsewhere in the app aren't factored out either.
class _TimeSlotToggle extends StatelessWidget {
  final SorenessTimeSlot selected;
  final ValueChanged<SorenessTimeSlot> onChanged;
  const _TimeSlotToggle({required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceRaised,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: AppColors.border),
      ),
      padding: const EdgeInsets.all(3),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: SorenessTimeSlot.values.map((s) {
          final isSelected = s == selected;
          return GestureDetector(
            onTap: () => onChanged(s),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: isSelected ? AppColors.accent : Colors.transparent,
                borderRadius: BorderRadius.circular(AppRadius.pill),
              ),
              child: Text(
                s.key,
                style: AppText.smallText.copyWith(
                  color: isSelected ? Colors.white : AppColors.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}
