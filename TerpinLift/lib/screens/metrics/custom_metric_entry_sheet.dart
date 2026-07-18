import 'package:flutter/material.dart';

import '../../data/models/custom_metric.dart';
import '../../data/models/custom_metric_entry.dart';
import '../../services/app_services.dart';
import '../../theme/app_theme.dart';
import '../../widgets/date_picker_field.dart';
import '../../widgets/scale_level_picker.dart';

/// Log a new value for a custom metric — the input control matches whatever
/// `kind` the metric was built with (number field / scale-level picker /
/// class chips). Pass [editingEntry] to correct an already-logged value in
/// place instead of adding a new one — reached from the Metrics "Days" tab.
class CustomMetricEntrySheet extends StatefulWidget {
  final CustomMetric metric;
  final CustomMetricEntry? editingEntry;
  const CustomMetricEntrySheet({super.key, required this.metric, this.editingEntry});

  @override
  State<CustomMetricEntrySheet> createState() => _CustomMetricEntrySheetState();
}

class _CustomMetricEntrySheetState extends State<CustomMetricEntrySheet> {
  late DateTime _date = widget.editingEntry == null
      ? DateTime.now()
      : DateTime.parse(widget.editingEntry!.date);
  late double? _value = widget.editingEntry?.value;
  late final _numberController = TextEditingController(
    text: widget.editingEntry == null ? '' : widget.metric.formatValue(widget.editingEntry!.value),
  );
  bool _saving = false;
  bool _hasExistingEntryToday = false;

  bool get _isEditing => widget.editingEntry != null;

  @override
  void initState() {
    super.initState();
    _checkExisting();
  }

  @override
  void dispose() {
    _numberController.dispose();
    super.dispose();
  }

  /// Only relevant for a once-per-day metric — surfaces "this will replace
  /// what's already there" up front, since the whole reason this got built
  /// was the user not realizing a second log wasn't obviously overwriting
  /// (or, for once-per-day metrics, now silently *does* overwrite).
  Future<void> _checkExisting() async {
    if (widget.metric.allowMultiplePerDay) return;
    final entries = await AppServices.customMetrics.getEntries(widget.metric.id!);
    final dateStr = _date.toIso8601String().substring(0, 10);
    if (!mounted) return;
    setState(() => _hasExistingEntryToday = entries
        .any((e) => e.date == dateStr && e.id != widget.editingEntry?.id));
  }

  Future<void> _save() async {
    final value = widget.metric.kind == CustomMetricKind.number
        ? double.tryParse(_numberController.text)
        : _value;
    if (value == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Enter a value first.')));
      return;
    }
    setState(() => _saving = true);
    final entry = CustomMetricEntry(
      customMetricId: widget.metric.id!,
      date: _date.toIso8601String().substring(0, 10),
      value: value,
      loggedAt: DateTime.now().toIso8601String(),
    );
    if (_isEditing) {
      // Delete-then-insert rather than an in-place update — handles a
      // changed date the same way a fresh log would, no separate "did the
      // date change" branch needed.
      await AppServices.customMetrics.deleteEntry(widget.editingEntry!.id!);
      await AppServices.customMetrics.insertEntry(entry);
    } else {
      await AppServices.customMetrics.upsertEntry(widget.metric, entry);
    }
    AppServices.signalReload();
    if (mounted) Navigator.pop(context);
  }

  Widget _input() {
    switch (widget.metric.kind) {
      case CustomMetricKind.number:
        return TextField(
          controller: _numberController,
          keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
          style: AppText.bodyText,
          decoration: InputDecoration(labelText: widget.metric.name),
        );
      case CustomMetricKind.scale:
        return ScaleLevelPicker(
          level: (_value ?? 0).round(),
          max: widget.metric.scaleMax ?? 5,
          icon: widget.metric.scaleIcon ?? ScaleIcon.dot,
          onChanged: (v) => setState(() => _value = v.toDouble()),
        );
      case CustomMetricKind.classes:
        return Wrap(
          spacing: AppSpacing.small,
          runSpacing: AppSpacing.small,
          children: List.generate(widget.metric.classLabels.length, (i) {
            final selected = _value?.round() == i;
            return ChoiceChip(
              label: Text(widget.metric.classLabels[i]),
              selected: selected,
              showCheckmark: false,
              onSelected: (_) => setState(() => _value = i.toDouble()),
              backgroundColor: AppColors.surface,
              selectedColor: AppColors.accentDim,
              labelStyle: TextStyle(
                  color: selected ? AppColors.accent : AppColors.textSecondary),
              side: BorderSide(color: selected ? AppColors.accent : AppColors.border),
            );
          }),
        );
    }
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
            Text(
              _isEditing ? 'Edit ${widget.metric.name}' : 'Log ${widget.metric.name}',
              style: AppText.subHeader,
            ),
            const SizedBox(height: AppSpacing.standard),
            DatePickerField(
              date: _date,
              onChanged: (d) {
                setState(() => _date = d);
                _checkExisting();
              },
            ),
            if (_hasExistingEntryToday) ...[
              const SizedBox(height: AppSpacing.small),
              Text(
                'This will replace the entry already logged for this date.',
                style: AppText.smallText.copyWith(color: AppColors.warn),
              ),
            ],
            const SizedBox(height: AppSpacing.large),
            _input(),
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
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('Save'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
