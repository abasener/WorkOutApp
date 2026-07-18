import 'package:flutter/material.dart';

import '../../data/models/custom_goal.dart';
import '../../services/app_services.dart';
import '../../services/units.dart';
import '../../theme/app_theme.dart';

/// A small log of custom goals for one exercise — add, name, and browse past
/// targets, rather than a single overwritable value. The most recent entry
/// (top of the list) is the one that actually drives the Goal gauge; older
/// ones are just history to look back on. Adds/deletes persist immediately
/// (no separate save step) — the caller should just reload after this sheet
/// closes, same as every other bottom sheet in this app.
class CustomGoalHistorySheet extends StatefulWidget {
  final int exerciseId;
  final bool isBodyweightLift;
  const CustomGoalHistorySheet({
    super.key,
    required this.exerciseId,
    required this.isBodyweightLift,
  });

  @override
  State<CustomGoalHistorySheet> createState() => _CustomGoalHistorySheetState();
}

class _CustomGoalHistorySheetState extends State<CustomGoalHistorySheet> {
  List<CustomGoal> _goals = [];
  bool _loading = true;
  final _labelController = TextEditingController();
  final _valueController = TextEditingController();

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
      widget.exerciseId,
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
      exerciseId: widget.exerciseId,
      label: _labelController.text.trim().isEmpty
          ? null
          : _labelController.text.trim(),
      targetReps: widget.isBodyweightLift ? entered.round() : null,
      targetWeight: widget.isBodyweightLift ? null : Units.toLb(entered),
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

  String _formatTarget(CustomGoal g) => widget.isBodyweightLift
      ? '${g.targetReps} ${g.targetReps == 1 ? 'rep' : 'reps'}'
      : Units.format(g.targetWeight!);

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
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
                      'The newest entry is what drives the gauge — older ones stay here as '
                      'history.',
                      style: AppText.smallText,
                    ),
                    const SizedBox(height: AppSpacing.large),
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
                              labelText: widget.isBodyweightLift
                                  ? 'Reps'
                                  : 'Weight (${Units.suffix})',
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
                    if (_goals.isEmpty)
                      Text('No goals set yet.', style: AppText.smallText)
                    else
                      ..._goals.map(
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
                                        _formatTarget(g),
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
                                GestureDetector(
                                  onTap: () => _delete(g),
                                  child: const Icon(
                                    Icons.delete_outline,
                                    size: 20,
                                    color: AppColors.textSecondary,
                                  ),
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
