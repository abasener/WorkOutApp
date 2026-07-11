import 'package:flutter/material.dart';

import '../../data/models/exercise.dart';
import '../../data/models/lift_set.dart';
import '../../data/repositories/lift_repository.dart';
import '../../services/app_services.dart';
import '../../services/units.dart';
import '../../theme/app_theme.dart';
import '../../widgets/date_picker_field.dart';
import '../../widgets/info_tooltip.dart';

class _EditableSet {
  int reps;
  double weightLb;
  double? rpe;
  _EditableSet({required this.reps, required this.weightLb, this.rpe});
}

/// Edit (or delete) an already-logged lift session — reachable via the pencil
/// icon on a session in Lift detail's History and on the Workouts tab.
class EditLiftSessionForm extends StatefulWidget {
  final Exercise exercise;
  final SessionWithSets sessionWithSets;
  const EditLiftSessionForm({
    super.key,
    required this.exercise,
    required this.sessionWithSets,
  });

  @override
  State<EditLiftSessionForm> createState() => _EditLiftSessionFormState();
}

class _EditLiftSessionFormState extends State<EditLiftSessionForm> {
  late DateTime _date = DateTime.parse(widget.sessionWithSets.session.date);
  late final _notesController =
      TextEditingController(text: widget.sessionWithSets.session.notes ?? '');
  late final List<_EditableSet> _sets = widget.sessionWithSets.sets
      .map((s) => _EditableSet(reps: s.reps, weightLb: s.weight, rpe: s.rpe))
      .toList();
  bool _saving = false;

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final dateStr = _date.toIso8601String().substring(0, 10);
    await AppServices.lifts.updateSession(widget.sessionWithSets.session.copyWith(
      date: dateStr,
      notes: _notesController.text.trim().isEmpty ? null : _notesController.text.trim(),
    ));
    await AppServices.lifts.replaceSets(
      widget.sessionWithSets.session.id!,
      _sets
          .map((s) => LiftSet(
                sessionId: 0,
                setNumber: 0,
                reps: s.reps,
                weight: s.weightLb,
                rpe: s.rpe,
              ))
          .toList(),
    );
    AppServices.signalReload();
    if (mounted) Navigator.pop(context);
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceRaised,
        title: Text('Delete this session?', style: AppText.subHeader),
        content: Text(
          'This permanently deletes this logged session and all its sets. This cannot be undone.',
          style: AppText.bodyText,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: AppText.bodyText),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: AppColors.accent)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await AppServices.lifts.deleteSession(widget.sessionWithSets.session.id!);
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
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Edit ${widget.exercise.name}', style: AppText.subHeader),
              const SizedBox(height: AppSpacing.standard),
              DatePickerField(date: _date, onChanged: (d) => setState(() => _date = d)),
              const SizedBox(height: AppSpacing.large),
              ...List.generate(_sets.length, (i) => _buildSetRow(i)),
              const SizedBox(height: AppSpacing.small),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: AppColors.border),
                  foregroundColor: AppColors.textPrimary,
                  minimumSize: const Size(double.infinity, 44),
                ),
                onPressed: () => setState(() => _sets.add(_EditableSet(
                      reps: _sets.isEmpty ? 5 : _sets.last.reps,
                      weightLb: _sets.isEmpty ? 45 : _sets.last.weightLb,
                    ))),
                icon: const Icon(Icons.add),
                label: const Text('Add another set'),
              ),
              const SizedBox(height: AppSpacing.large),
              TextField(
                controller: _notesController,
                style: AppText.bodyText,
                maxLines: 2,
                decoration: const InputDecoration(labelText: 'Notes (optional)'),
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
                  onPressed: _saving ? null : _save,
                  child: _saving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Text('Save'),
                ),
              ),
              const SizedBox(height: AppSpacing.standard),
              SizedBox(
                width: double.infinity,
                height: 44,
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: AppColors.accent),
                    foregroundColor: AppColors.accent,
                  ),
                  onPressed: _saving ? null : _delete,
                  child: const Text('Delete Session'),
                ),
              ),
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
              initialValue: set.rpe?.toString() ?? '',
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: AppText.bodyText,
              decoration: InputDecoration(
                labelText: 'RPE',
                suffixIcon: const InfoTooltip(glossaryKey: 'rpe', title: 'RPE'),
              ),
              onChanged: (v) => set.rpe = double.tryParse(v),
            ),
          ),
        ],
      ),
    );
  }
}
