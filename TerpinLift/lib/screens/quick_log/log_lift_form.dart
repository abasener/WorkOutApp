import 'package:flutter/material.dart';

import '../../data/models/exercise.dart';
import '../../data/models/lift_set.dart';
import '../../services/app_services.dart';
import '../../services/effort_display.dart';
import '../../services/units.dart';
import '../../theme/app_theme.dart';
import '../../widgets/date_picker_field.dart';
import '../../widgets/info_tooltip.dart';

class _PendingSet {
  int reps;
  double weightLb;
  double? rpe;
  _PendingSet({this.reps = 5, this.weightLb = 45});
}

class LogLiftForm extends StatefulWidget {
  final Exercise? preselected;
  const LogLiftForm({super.key, this.preselected});

  @override
  State<LogLiftForm> createState() => _LogLiftFormState();
}

class _LogLiftFormState extends State<LogLiftForm> {
  List<Exercise> _exercises = [];
  Exercise? _selected;
  final List<_PendingSet> _sets = [_PendingSet()];
  bool _saving = false;
  bool _loading = true;
  bool _trackTime = true;
  DateTime _date = DateTime.now();
  final _notesController = TextEditingController();

  /// Wall-clock timestamp captured the moment this form opened — used as the
  /// silent background session timer. No visible countdown/stopwatch UI per
  /// designFiles/00_UX_DESIGN.md; if the sheet is dismissed without submitting,
  /// this is simply discarded (the session is only ever written on submit).
  final DateTime _openedAt = DateTime.now();

  @override
  void initState() {
    super.initState();
    _loadExercises();
  }

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _loadExercises() async {
    final all = await AppServices.exercises.getAll();
    // Only pinned exercises clutter this dropdown much less now that the
    // library is ~75 lifts — anything off the beaten path is reachable via
    // the Lifts list + that lift's own "+" button instead. Always include
    // `preselected` even if unpinned, so opening this form from a specific
    // lift's detail page never shows a dropdown missing its own exercise.
    final pinned = all.where((e) => e.pinned).toList();
    final exercises = widget.preselected != null &&
            !pinned.any((e) => e.id == widget.preselected!.id)
        ? [widget.preselected!, ...pinned]
        : pinned;
    if (!mounted) return;
    setState(() {
      _exercises = exercises;
      _selected = widget.preselected != null &&
              exercises.any((e) => e.id == widget.preselected!.id)
          ? exercises.firstWhere((e) => e.id == widget.preselected!.id)
          : (exercises.isNotEmpty ? exercises.first : null);
      _loading = false;
    });
  }

  Future<void> _submit() async {
    if (_selected?.id == null) return;
    setState(() => _saving = true);
    final dateStr = _date.toIso8601String().substring(0, 10);
    await AppServices.lifts.logSession(
      exerciseId: _selected!.id!,
      date: dateStr,
      sets: _sets
          .map((s) => LiftSet(
                sessionId: 0,
                setNumber: 0,
                reps: s.reps,
                weight: s.weightLb,
                rpe: s.rpe,
              ))
          .toList(),
      startedAt: _trackTime ? _openedAt.toIso8601String() : null,
      completedAt: _trackTime ? DateTime.now().toIso8601String() : null,
      notes: _notesController.text.trim().isEmpty ? null : _notesController.text.trim(),
    );
    AppServices.signalReload();
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        constraints: BoxConstraints(
          minHeight: screenHeight * 0.5,
          maxHeight: screenHeight * 0.85,
        ),
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
        child: _loading
            ? const Center(child: CircularProgressIndicator(color: AppColors.accent))
            : SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Log Lift', style: AppText.subHeader),
                        Row(
                          children: [
                            Text('Track time', style: AppText.smallText),
                            Switch(
                              value: _trackTime,
                              activeThumbColor: AppColors.accent,
                              onChanged: (v) => setState(() => _trackTime = v),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.standard),
                    DatePickerField(
                      date: _date,
                      onChanged: (d) => setState(() => _date = d),
                    ),
                    const SizedBox(height: AppSpacing.standard),
                    if (_exercises.isEmpty)
                      Text(
                          'No pinned lifts yet — pin one from its detail page '
                          '(the push-pin icon), or open it from the Lifts tab '
                          'and log a set directly from there.',
                          style: AppText.smallText)
                    else ...[
                      DropdownButtonFormField<Exercise>(
                        initialValue: _selected,
                        dropdownColor: AppColors.surfaceRaised,
                        decoration: const InputDecoration(labelText: 'Exercise'),
                        items: _exercises
                            .map((e) =>
                                DropdownMenuItem(value: e, child: Text(e.name)))
                            .toList(),
                        onChanged: (v) => setState(() => _selected = v),
                      ),
                      const SizedBox(height: AppSpacing.large),
                      ...List.generate(_sets.length, (i) => _buildSetRow(i)),
                      const SizedBox(height: AppSpacing.small),
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: AppColors.border),
                          foregroundColor: AppColors.textPrimary,
                          minimumSize: const Size(double.infinity, 44),
                        ),
                        onPressed: () => setState(() => _sets.add(_PendingSet(
                              reps: _sets.last.reps,
                              weightLb: _sets.last.weightLb,
                            ))),
                        icon: const Icon(Icons.add),
                        label: const Text('Add another set'),
                      ),
                      const SizedBox(height: AppSpacing.large),
                      TextField(
                        controller: _notesController,
                        style: AppText.bodyText,
                        maxLines: 2,
                        decoration:
                            const InputDecoration(labelText: 'Notes (optional)'),
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
                          onPressed: _saving ? null : _submit,
                          child: _saving
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2, color: Colors.white))
                              : const Text('Done'),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildSetRow(int i) {
    final set = _sets[i];
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.standard),
      child: Row(
        children: [
          Text('Set ${i + 1}', style: AppText.smallText),
          const SizedBox(width: AppSpacing.standard),
          Expanded(
            child: TextFormField(
              key: ValueKey('reps_$i'),
              initialValue: set.reps.toString(),
              keyboardType: TextInputType.number,
              style: AppText.bodyText,
              decoration: const InputDecoration(labelText: 'Reps'),
              onChanged: (v) => set.reps = int.tryParse(v) ?? set.reps,
            ),
          ),
          const SizedBox(width: AppSpacing.small),
          Expanded(
            child: TextFormField(
              key: ValueKey('weight_$i'),
              initialValue: Units.displayValue(set.weightLb).toStringAsFixed(0),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: AppText.bodyText,
              decoration: InputDecoration(labelText: 'Weight (${Units.suffix})'),
              onChanged: (v) {
                final entered = double.tryParse(v);
                if (entered != null) set.weightLb = Units.toLb(entered);
              },
            ),
          ),
          const SizedBox(width: AppSpacing.small),
          Expanded(
            child: TextFormField(
              key: ValueKey('rpe_$i'),
              initialValue:
                  set.rpe != null ? EffortDisplay.toDisplay(set.rpe!).toStringAsFixed(0) : '',
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: AppText.bodyText,
              decoration: InputDecoration(
                labelText: 'Reps left',
                suffixIcon: const InfoTooltip(glossaryKey: 'rpe', title: 'Reps left'),
              ),
              onChanged: (v) {
                final entered = double.tryParse(v);
                set.rpe = entered == null ? null : EffortDisplay.fromDisplay(entered);
              },
            ),
          ),
        ],
      ),
    );
  }
}
