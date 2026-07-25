import 'package:flutter/material.dart';

import '../../data/models/custom_metric.dart';
import '../../services/app_services.dart';
import '../../theme/app_theme.dart';

/// One example preset for classes-kind metrics — a quick-fill shortcut, not
/// a separate concept from typing your own labels (the stored data is just
/// an ordered label list either way).
const _moodPreset = ['😞 Sad', '🙁 Down', '😐 Neutral', '🙂 Good', '😄 Great'];

/// The "metric builder" — add a new custom metric (unlimited, per the user's
/// call). Pick a name and a `kind`: a plain number (e.g. temperature), a
/// 0-5 scale with a chosen icon (flame/star/dot — same shape as muscle
/// soreness), or a named-classes value (type your own labels, or start from
/// the "Mood" preset and tweak it).
class CustomMetricBuilderSheet extends StatefulWidget {
  const CustomMetricBuilderSheet({super.key});

  @override
  State<CustomMetricBuilderSheet> createState() =>
      _CustomMetricBuilderSheetState();
}

class _CustomMetricBuilderSheetState extends State<CustomMetricBuilderSheet> {
  final _nameController = TextEditingController();
  final _goalController = TextEditingController();
  CustomMetricKind _kind = CustomMetricKind.number;
  ScaleIcon _scaleIcon = ScaleIcon.flame;
  final List<TextEditingController> _classControllers = [
    TextEditingController(),
    TextEditingController(),
  ];
  bool _allowMultiplePerDay = false;
  bool _saving = false;

  static const _scaleMax = 5; // fixed, same shape as muscle soreness

  @override
  void dispose() {
    _nameController.dispose();
    _goalController.dispose();
    for (final c in _classControllers) {
      c.dispose();
    }
    super.dispose();
  }

  void _useMoodPreset() {
    setState(() {
      _nameController.text = 'Mood';
      _classControllers
        ..clear()
        ..addAll(_moodPreset.map((l) => TextEditingController(text: l)));
    });
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Name is required.')));
      return;
    }
    List<String>? classLabels;
    if (_kind == CustomMetricKind.classes) {
      classLabels = _classControllers
          .map((c) => c.text.trim())
          .where((s) => s.isNotEmpty)
          .toList();
      if (classLabels.length < 2) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Add at least 2 class labels.')),
        );
        return;
      }
    }
    setState(() => _saving = true);
    await AppServices.customMetrics.insertDefinition(
      CustomMetric(
        name: name,
        kind: _kind,
        scaleMax: _kind == CustomMetricKind.scale ? _scaleMax : null,
        scaleIcon: _kind == CustomMetricKind.scale ? _scaleIcon : null,
        classLabels: classLabels ?? const [],
        created: DateTime.now().toIso8601String(),
        allowMultiplePerDay: _allowMultiplePerDay,
        goal: _kind == CustomMetricKind.number
            ? double.tryParse(_goalController.text.trim())
            : null,
      ),
    );
    AppServices.signalReload();
    if (mounted) Navigator.pop(context);
  }

  Widget _kindChip(CustomMetricKind kind, String label) {
    final selected = _kind == kind;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      // No checkmark — the color/border swap already reads as "selected,"
      // and on the icon chips below a checkmark actively covers the icon.
      showCheckmark: false,
      onSelected: (_) => setState(() => _kind = kind),
      backgroundColor: AppColors.surface,
      selectedColor: AppColors.accentDim,
      labelStyle: TextStyle(
        color: selected ? AppColors.accent : AppColors.textSecondary,
      ),
      side: BorderSide(color: selected ? AppColors.accent : AppColors.border),
    );
  }

  Widget _scaleIconChip(ScaleIcon icon, IconData iconData, String label) {
    final selected = _scaleIcon == icon;
    return ChoiceChip(
      avatar: Icon(
        iconData,
        size: 16,
        color: selected ? AppColors.accent : AppColors.textSecondary,
      ),
      label: Text(label),
      selected: selected,
      showCheckmark: false,
      onSelected: (_) => setState(() => _scaleIcon = icon),
      backgroundColor: AppColors.surface,
      selectedColor: AppColors.accentDim,
      labelStyle: TextStyle(
        color: selected ? AppColors.accent : AppColors.textSecondary,
      ),
      side: BorderSide(color: selected ? AppColors.accent : AppColors.border),
    );
  }

  @override
  Widget build(BuildContext context) {
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
              Text('New Metric', style: AppText.subHeader),
              const SizedBox(height: AppSpacing.large),
              TextField(
                controller: _nameController,
                style: AppText.bodyText,
                decoration: const InputDecoration(labelText: 'Name'),
              ),
              const SizedBox(height: AppSpacing.large),
              Text('Type', style: AppText.label),
              const SizedBox(height: AppSpacing.standard),
              Wrap(
                spacing: AppSpacing.small,
                children: [
                  _kindChip(CustomMetricKind.number, 'Number'),
                  _kindChip(CustomMetricKind.scale, '0-5 Scale'),
                  _kindChip(CustomMetricKind.classes, 'Classes'),
                ],
              ),
              if (_kind == CustomMetricKind.number) ...[
                const SizedBox(height: AppSpacing.large),
                TextField(
                  controller: _goalController,
                  style: AppText.bodyText,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Goal (optional)',
                    hintText: 'e.g. 8',
                  ),
                ),
              ],
              if (_kind == CustomMetricKind.scale) ...[
                const SizedBox(height: AppSpacing.large),
                Text('Icon', style: AppText.label),
                const SizedBox(height: AppSpacing.standard),
                Wrap(
                  spacing: AppSpacing.small,
                  runSpacing: AppSpacing.small,
                  children: [
                    _scaleIconChip(
                      ScaleIcon.flame,
                      Icons.local_fire_department,
                      'Flame',
                    ),
                    _scaleIconChip(ScaleIcon.star, Icons.star, 'Star'),
                    _scaleIconChip(ScaleIcon.dot, Icons.circle, 'Dot'),
                    _scaleIconChip(ScaleIcon.heart, Icons.favorite, 'Heart'),
                    _scaleIconChip(ScaleIcon.bolt, Icons.bolt, 'Bolt'),
                    _scaleIconChip(ScaleIcon.moon, Icons.bedtime, 'Moon'),
                    _scaleIconChip(ScaleIcon.drop, Icons.water_drop, 'Drop'),
                  ],
                ),
              ],
              if (_kind == CustomMetricKind.classes) ...[
                const SizedBox(height: AppSpacing.large),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Classes (worst to best)', style: AppText.label),
                    TextButton(
                      onPressed: _useMoodPreset,
                      child: const Text('Use Mood preset'),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.small),
                ...List.generate(_classControllers.length, (i) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.small),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _classControllers[i],
                            style: AppText.bodyText,
                            decoration: InputDecoration(
                              labelText: 'Class ${i + 1}',
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(
                            Icons.remove_circle_outline,
                            size: 18,
                          ),
                          color: AppColors.textSecondary,
                          onPressed: _classControllers.length <= 2
                              ? null
                              : () => setState(() {
                                  _classControllers[i].dispose();
                                  _classControllers.removeAt(i);
                                }),
                        ),
                      ],
                    ),
                  );
                }),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: AppColors.border),
                    foregroundColor: AppColors.textPrimary,
                    minimumSize: const Size(double.infinity, 40),
                  ),
                  onPressed: () => setState(
                    () => _classControllers.add(TextEditingController()),
                  ),
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Add class'),
                ),
              ],
              const SizedBox(height: AppSpacing.large),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _allowMultiplePerDay,
                onChanged: (v) => setState(() => _allowMultiplePerDay = v),
                activeThumbColor: AppColors.accent,
                title: Text(
                  'Allow multiple entries per day',
                  style: AppText.bodyText,
                ),
                subtitle: Text(
                  _allowMultiplePerDay
                      ? 'Logging again today adds another entry (e.g. checking in more than once).'
                      : 'Logging again today replaces today\'s entry, rather than adding a second one.',
                  style: AppText.smallText,
                ),
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
                  onPressed: _saving ? null : _save,
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
