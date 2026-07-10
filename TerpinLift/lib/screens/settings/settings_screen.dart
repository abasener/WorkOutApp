import 'package:flutter/material.dart';

import '../../services/app_services.dart';
import '../../services/backup_service.dart';
import '../../services/test_data_service.dart';
import '../../services/units.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_card.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _busy = false;

  Future<void> _export() async {
    setState(() => _busy = true);
    final path = await BackupService.exportToFile();
    setState(() => _busy = false);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Exported to $path')),
    );
  }

  Future<void> _import() async {
    setState(() => _busy = true);
    final ok = await BackupService.importFromFile();
    setState(() => _busy = false);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok
            ? 'Import complete.'
            : 'No export file found — export first, or copy one into the app\'s documents folder.'),
      ),
    );
  }

  Future<bool> _confirm({required String title, required String message}) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surfaceRaised,
        title: Text(title, style: AppText.subHeader),
        content: Text(message, style: AppText.bodyText),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel', style: AppText.bodyText),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirm', style: TextStyle(color: AppColors.accent)),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  Future<void> _wipeData() async {
    final confirmed = await _confirm(
      title: 'Wipe data?',
      message: 'This permanently deletes every logged lift, bodyweight entry, '
          'metric, and cycle entry. Your exercise list stays intact. This '
          'cannot be undone.',
    );
    if (!confirmed) return;
    setState(() => _busy = true);
    await AppServices.db.wipeLoggedData();
    AppServices.signalReload();
    setState(() => _busy = false);
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('All logged data wiped.')));
  }

  Future<void> _loadTestData() async {
    final confirmed = await _confirm(
      title: 'Load test data?',
      message: 'This deletes ALL existing data (including your exercise list) '
          'and replaces it with ~2 months of made-up but reasonable workout, '
          'sleep, steps, soreness, bodyweight, and cycle history. This cannot '
          'be undone.',
    );
    if (!confirmed) return;
    setState(() => _busy = true);
    await TestDataService.load();
    setState(() => _busy = false);
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Test data loaded.')));
  }

  Future<void> _setUnit(WeightUnit unit) async {
    if (Units.current == unit) return;
    await AppServices.setWeightUnit(unit);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.edge),
        children: [
          Text('Units', style: AppText.subHeader),
          const SizedBox(height: AppSpacing.standard),
          AppCard(
            child: Row(
              children: [
                Expanded(child: Text('Weight unit', style: AppText.bodyText)),
                _UnitToggle(
                  selected: Units.current,
                  onChanged: _setUnit,
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.large),
          Text('Data', style: AppText.subHeader),
          const SizedBox(height: AppSpacing.standard),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Export data', style: AppText.bodyText),
                const SizedBox(height: AppSpacing.micro),
                Text(
                  'Writes a JSON snapshot of everything logged to the app\'s '
                  'documents folder.',
                  style: AppText.smallText,
                ),
                const SizedBox(height: AppSpacing.standard),
                SizedBox(
                  height: 44,
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: AppColors.accent),
                      foregroundColor: AppColors.accent,
                    ),
                    onPressed: _busy ? null : _export,
                    child: const Text('Export'),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.cardGap),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Import data', style: AppText.bodyText),
                const SizedBox(height: AppSpacing.micro),
                Text(
                  'Restores from the exported JSON file. Intended for a fresh '
                  'install, not merging with existing data.',
                  style: AppText.smallText,
                ),
                const SizedBox(height: AppSpacing.standard),
                SizedBox(
                  height: 44,
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: AppColors.border),
                      foregroundColor: AppColors.textPrimary,
                    ),
                    onPressed: _busy ? null : _import,
                    child: const Text('Import'),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.large),
          Text('Development / Testing', style: AppText.subHeader),
          const SizedBox(height: AppSpacing.standard),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Wipe data', style: AppText.bodyText),
                const SizedBox(height: AppSpacing.micro),
                Text(
                  'Deletes every logged lift, bodyweight, metric, and cycle '
                  'entry. Exercise list is kept.',
                  style: AppText.smallText,
                ),
                const SizedBox(height: AppSpacing.standard),
                SizedBox(
                  height: 44,
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: AppColors.accent),
                      foregroundColor: AppColors.accent,
                    ),
                    onPressed: _busy ? null : _wipeData,
                    child: const Text('Wipe Data'),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.cardGap),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Load test data', style: AppText.bodyText),
                const SizedBox(height: AppSpacing.micro),
                Text(
                  'Wipes everything and fills in ~2 months of made-up lift, '
                  'sleep, steps, soreness, bodyweight, and cycle history so '
                  'trends/predictions can be reviewed with real-looking data.',
                  style: AppText.smallText,
                ),
                const SizedBox(height: AppSpacing.standard),
                SizedBox(
                  height: 44,
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: AppColors.accent),
                      foregroundColor: AppColors.accent,
                    ),
                    onPressed: _busy ? null : _loadTestData,
                    child: const Text('Load Test Data'),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.large),
          Text('About', style: AppText.subHeader),
          const SizedBox(height: AppSpacing.standard),
          AppCard(
            child: Text(
              'TerpinLift — personal strength + recovery tracker.\n'
              'Cycle tracking is kept in a plain "Cycle" card on Metrics, '
              'not a locked/hidden tab, in this version.',
              style: AppText.smallText,
            ),
          ),
          const SizedBox(height: AppSpacing.xLarge),
        ],
      ),
    );
  }
}

class _UnitToggle extends StatelessWidget {
  final WeightUnit selected;
  final ValueChanged<WeightUnit> onChanged;
  const _UnitToggle({required this.selected, required this.onChanged});

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
        children: WeightUnit.values.map((u) {
          final isSelected = u == selected;
          return GestureDetector(
            onTap: () => onChanged(u),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              decoration: BoxDecoration(
                color: isSelected ? AppColors.accent : Colors.transparent,
                borderRadius: BorderRadius.circular(AppRadius.pill),
              ),
              child: Text(
                u.key.toUpperCase(),
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
