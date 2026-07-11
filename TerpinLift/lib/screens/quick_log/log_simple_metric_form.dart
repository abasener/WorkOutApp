import 'package:flutter/material.dart';

import '../../data/models/bodyweight_entry.dart';
import '../../data/models/metric_entry.dart';
import '../../services/app_services.dart';
import '../../services/units.dart';
import '../../theme/app_theme.dart';
import '../../widgets/date_picker_field.dart';

/// Soreness now lives in SorenessBodyMapForm (tap-the-body-map, flame-scale
/// per region) instead of here — see designFiles/00_UX_DESIGN.md.
enum SimpleMetricKind { bodyweight, sleep, steps }

/// Pass [editingId] + [initialValue]/[initialDate]/[initialLoggedAt] to edit
/// an already-logged entry in place instead of inserting a new one — reached
/// from the Metrics "Days" tab when a value was mistyped.
class LogSimpleMetricForm extends StatefulWidget {
  final SimpleMetricKind kind;
  final int? editingId;
  final double? initialValue;
  final DateTime? initialDate;
  final String? initialLoggedAt;

  const LogSimpleMetricForm({
    super.key,
    required this.kind,
    this.editingId,
    this.initialValue,
    this.initialDate,
    this.initialLoggedAt,
  });

  @override
  State<LogSimpleMetricForm> createState() => _LogSimpleMetricFormState();
}

class _LogSimpleMetricFormState extends State<LogSimpleMetricForm> {
  late final _controller = TextEditingController(
    text: widget.initialValue == null
        ? ''
        : (widget.kind == SimpleMetricKind.bodyweight
            ? Units.displayValue(widget.initialValue!)
            : widget.initialValue!)
            .toStringAsFixed(widget.kind == SimpleMetricKind.sleep ? 1 : 0),
  );
  bool _saving = false;
  late DateTime _date = widget.initialDate ?? DateTime.now();

  bool get _isEditing => widget.editingId != null;

  String get _title {
    final prefix = _isEditing ? 'Edit' : 'Log';
    switch (widget.kind) {
      case SimpleMetricKind.bodyweight:
        return '$prefix Weight';
      case SimpleMetricKind.sleep:
        return '$prefix Sleep';
      case SimpleMetricKind.steps:
        return '$prefix Steps';
    }
  }

  String get _label {
    switch (widget.kind) {
      case SimpleMetricKind.bodyweight:
        return 'Weight (${Units.suffix})';
      case SimpleMetricKind.sleep:
        return 'Hours of sleep';
      case SimpleMetricKind.steps:
        return 'Steps';
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final entered = double.tryParse(_controller.text);
    if (entered == null) return;
    setState(() => _saving = true);
    final dateStr = _date.toIso8601String().substring(0, 10);

    if (widget.kind == SimpleMetricKind.bodyweight) {
      // Entered in whatever unit is currently displayed -> convert back to
      // the canonical lb storage, same as the lift-weight field.
      final entry =
          BodyweightEntry(id: widget.editingId, date: dateStr, weight: Units.toLb(entered));
      if (_isEditing) {
        await AppServices.bodyweight.update(entry);
      } else {
        await AppServices.bodyweight.insert(entry);
      }
    } else {
      final type = switch (widget.kind) {
        SimpleMetricKind.sleep => MetricType.sleepHours,
        SimpleMetricKind.steps => MetricType.steps,
        SimpleMetricKind.bodyweight => throw StateError('unreachable'),
      };
      final entry = MetricEntry(
        id: widget.editingId,
        date: dateStr,
        metricType: type,
        value: entered,
        loggedAt: widget.initialLoggedAt ?? DateTime.now().toIso8601String(),
      );
      if (_isEditing) {
        await AppServices.metrics.update(entry);
      } else {
        await AppServices.metrics.insert(entry);
      }
    }
    AppServices.signalReload();
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
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
            Text(_title, style: AppText.subHeader),
            const SizedBox(height: AppSpacing.large),
            DatePickerField(
              date: _date,
              onChanged: (d) => setState(() => _date = d),
            ),
            const SizedBox(height: AppSpacing.standard),
            TextField(
              controller: _controller,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: AppText.bodyText,
              decoration: InputDecoration(labelText: _label),
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
                        child:
                            CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('Save'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
