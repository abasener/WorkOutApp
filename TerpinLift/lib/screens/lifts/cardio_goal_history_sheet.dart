import 'package:flutter/material.dart';

import '../../data/models/custom_goal.dart';
import '../../data/models/distance_unit.dart';
import '../../data/models/exercise.dart';
import '../../services/app_services.dart';
import '../../services/cardio_units.dart';
import '../../theme/app_theme.dart';
import '../../widgets/tap_icon.dart';

enum _CardioGoalType { distance, pace }

/// Cardio's goal log — same "add, name, browse past targets" shape as
/// `CustomGoalHistorySheet`, but with a Distance/Pace type toggle instead
/// of a single implicit axis, since a cardio exercise can have both goals
/// active at once (independent gauges, not one dual-axis plot). Values are
/// entered/shown in [exercise]'s own `cardioUnit` — see
/// designFiles/11_SCREEN_cardio.md.
class CardioGoalHistorySheet extends StatefulWidget {
  final Exercise exercise;
  const CardioGoalHistorySheet({super.key, required this.exercise});

  @override
  State<CardioGoalHistorySheet> createState() => _CardioGoalHistorySheetState();
}

class _CardioGoalHistorySheetState extends State<CardioGoalHistorySheet> {
  List<CustomGoal> _goals = [];
  bool _loading = true;
  _CardioGoalType _addType = _CardioGoalType.distance;
  final _labelController = TextEditingController();
  final _valueController = TextEditingController();

  DistanceUnit get _unit =>
      widget.exercise.cardioUnit ?? CardioUnits.defaultUnit;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _labelController.dispose();
    _valueController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final goals = await AppServices.customGoals.getAllForExercise(
      widget.exercise.id!,
    );
    if (!mounted) return;
    setState(() {
      _goals = goals;
      _loading = false;
    });
  }

  Future<void> _add() async {
    final entered = double.tryParse(_valueController.text);
    if (entered == null) return;
    final goal = CustomGoal(
      exerciseId: widget.exercise.id!,
      label: _labelController.text.trim().isEmpty
          ? null
          : _labelController.text.trim(),
      targetDistance: _addType == _CardioGoalType.distance
          ? CardioUnits.toCanonical(entered, _unit)
          : null,
      // Entered as decimal minutes-per-[unit] (e.g. "8.5" = 8:30/mi, or
      // per-500m for a meters-unit exercise), canonicalized to seconds-per-
      // meter — the same basis `CardioUnits.paceSecondsPerUnit` derives a
      // logged result in, so a goal and an actual result are always
      // directly comparable.
      targetPace: _addType == _CardioGoalType.pace
          ? (entered * 60) / _unit.paceUnitMeters
          : null,
      created: DateTime.now().toIso8601String(),
    );
    await AppServices.customGoals.insert(goal);
    _labelController.clear();
    _valueController.clear();
    await _load();
  }

  Future<void> _delete(CustomGoal goal) async {
    await AppServices.customGoals.delete(goal.id!);
    await _load();
  }

  String _formatTarget(CustomGoal g) => g.targetDistance != null
      ? CardioUnits.formatDistance(g.targetDistance!, _unit)
      : CardioUnits.formatPace(g.targetPace! * _unit.paceUnitMeters, _unit);

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final relevantGoals = _goals
        .where((g) => g.targetDistance != null || g.targetPace != null)
        .toList();
    final paceAvailable = _unit.isRealDistance;
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        constraints: BoxConstraints(
          minHeight: screenHeight * 0.4,
          maxHeight: screenHeight * 0.85,
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
        child: _loading
            ? const Center(
                child: CircularProgressIndicator(color: AppColors.accent),
              )
            : SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Your Goals', style: AppText.subHeader),
                    const SizedBox(height: AppSpacing.micro),
                    Text(
                      'The newest entry of each type drives its gauge. Older ones stay here '
                      'as history.',
                      style: AppText.smallText,
                    ),
                    const SizedBox(height: AppSpacing.large),
                    Row(
                      children: [
                        ChoiceChip(
                          label: const Text('Distance'),
                          selected: _addType == _CardioGoalType.distance,
                          showCheckmark: false,
                          onSelected: (_) => setState(
                            () => _addType = _CardioGoalType.distance,
                          ),
                        ),
                        if (paceAvailable) ...[
                          const SizedBox(width: AppSpacing.small),
                          ChoiceChip(
                            label: const Text('Pace'),
                            selected: _addType == _CardioGoalType.pace,
                            showCheckmark: false,
                            onSelected: (_) =>
                                setState(() => _addType = _CardioGoalType.pace),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: AppSpacing.standard),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          flex: 3,
                          child: TextField(
                            controller: _labelController,
                            style: AppText.bodyText,
                            decoration: const InputDecoration(
                              labelText: 'Label (optional)',
                            ),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.small),
                        Expanded(
                          flex: 2,
                          child: TextField(
                            controller: _valueController,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            style: AppText.bodyText,
                            decoration: InputDecoration(
                              labelText: _addType == _CardioGoalType.distance
                                  ? 'Distance (${_unit.suffix})'
                                  : 'Pace (min/${_unit.paceSuffix})',
                            ),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.small),
                        IconButton(
                          onPressed: _add,
                          icon: const Icon(
                            Icons.add_circle,
                            color: AppColors.accent,
                            size: 32,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.large),
                    if (relevantGoals.isEmpty)
                      Text('No goals set yet.', style: AppText.smallText)
                    else
                      ...relevantGoals.map(
                        (g) => Padding(
                          padding: const EdgeInsets.only(
                            bottom: AppSpacing.small,
                          ),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.standard,
                              vertical: AppSpacing.small,
                            ),
                            decoration: BoxDecoration(
                              border: Border.all(color: AppColors.border),
                              borderRadius: BorderRadius.circular(
                                AppRadius.button,
                              ),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '${g.targetDistance != null ? 'Distance' : 'Pace'}: '
                                        '${_formatTarget(g)}',
                                        style: AppText.bodyText,
                                      ),
                                      Text(
                                        g.label?.isNotEmpty == true
                                            ? g.label!
                                            : g.created.substring(0, 10),
                                        style: AppText.smallText,
                                      ),
                                    ],
                                  ),
                                ),
                                TapIcon(
                                  icon: Icons.delete_outline,
                                  size: 20,
                                  onTap: () => _delete(g),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
      ),
    );
  }
}
