import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../data/profile_manager.dart';
import '../../services/app_services.dart';
import '../../services/backup_service.dart';
import '../../services/units.dart';
import '../../services/user_profile.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_card.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _busy = false;
  late final _birthYearController =
      TextEditingController(text: UserProfile.birthYear?.toString() ?? '');
  late final _stepsGoalController =
      TextEditingController(text: UserProfile.stepsGoal.toString());

  @override
  void dispose() {
    _birthYearController.dispose();
    _stepsGoalController.dispose();
    super.dispose();
  }

  Future<void> _export() async {
    setState(() => _busy = true);
    final path = await BackupService.exportToFile();
    setState(() => _busy = false);
    if (!mounted) return;
    // Opens the OS share sheet (email, Drive, Files, etc.) instead of just
    // writing to the app's private documents folder and reporting a path
    // the user has no normal way to browse to on Android.
    await SharePlus.instance.share(
      ShareParams(files: [XFile(path)], subject: 'TerpinLift export'),
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

  bool get _inDemoMode => AppServices.activeProfile.value == AppProfile.demo;

  Future<void> _wipeData() async {
    final confirmed = await _confirm(
      title: 'Wipe data?',
      message: _inDemoMode
          ? 'This permanently deletes every logged lift, bodyweight entry, '
              'metric, and cycle entry from the demo data set. Your personal '
              'data is untouched. This cannot be undone.'
          : 'This permanently deletes every logged lift, bodyweight entry, '
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

  Future<void> _resetDemoData() async {
    final confirmed = await _confirm(
      title: 'Reset demo data?',
      message: 'This replaces the current demo data set with a fresh ~2 '
          'months of made-up workout, sleep, steps, soreness, bodyweight, '
          'and cycle history. Your personal data is untouched. This cannot '
          'be undone.',
    );
    if (!confirmed) return;
    setState(() => _busy = true);
    await AppServices.resetDemoData();
    setState(() => _busy = false);
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Demo data reset.')));
  }

  Future<void> _setProfile(AppProfile profile) async {
    if (AppServices.activeProfile.value == profile) return;
    final switchingToDemo = profile == AppProfile.demo;
    if (switchingToDemo) {
      final confirmed = await _confirm(
        title: 'Switch to demo data?',
        message: 'Demo mode always starts from a fresh, made-up data set — '
            'your personal data stays exactly as it is and isn\'t shown '
            'while demo mode is on. Switch back to Personal any time to '
            'return to it.',
      );
      if (!confirmed) return;
    }
    setState(() => _busy = true);
    await AppServices.switchProfile(profile);
    setState(() => _busy = false);
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _setUnit(WeightUnit unit) async {
    if (Units.current == unit) return;
    await AppServices.setWeightUnit(unit);
    setState(() {});
  }

  Future<void> _setHideWeight(bool hide) async {
    await AppServices.setHideWeight(hide);
    setState(() {});
  }

  Future<void> _setGender(Gender gender) async {
    if (UserProfile.gender == gender) return;
    await AppServices.setGender(gender);
    setState(() {});
  }

  Future<void> _saveBirthYear(String text) async {
    final year = int.tryParse(text.trim());
    final currentYear = DateTime.now().year;
    if (text.trim().isNotEmpty && (year == null || year < 1900 || year > currentYear)) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Enter a valid birth year.')));
      return;
    }
    await AppServices.setBirthYear(year);
    setState(() {});
  }

  Future<void> _saveStepsGoal(String text) async {
    final goal = int.tryParse(text.trim());
    if (goal == null || goal <= 0) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Enter a valid steps goal.')));
      return;
    }
    await AppServices.setStepsGoal(goal);
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
          Text('Data set', style: AppText.subHeader),
          const SizedBox(height: AppSpacing.standard),
          AppCard(
            backgroundColor: _inDemoMode ? AppColors.accentDim : null,
            borderColor: _inDemoMode ? AppColors.accent : null,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: Text('Active data set', style: AppText.bodyText)),
                    ValueListenableBuilder<AppProfile>(
                      valueListenable: AppServices.activeProfile,
                      builder: (context, profile, child) =>
                          _ProfileToggle(selected: profile, onChanged: _busy ? (_) {} : _setProfile),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.small),
                Text(
                  _inDemoMode
                      ? 'Demo mode is on — everything you see is made-up '
                          'data. Your personal data is untouched and comes '
                          'back exactly as it was when you switch back.'
                      : 'Personal is your real logged history. Switch to '
                          'Demo any time to try things out on a disposable, '
                          'always-fresh made-up data set instead.',
                  style: AppText.smallText,
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.large),
          Text('Profile', style: AppText.subHeader),
          const SizedBox(height: AppSpacing.standard),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: Text('Gender', style: AppText.bodyText)),
                    _GenderToggle(selected: UserProfile.gender, onChanged: _setGender),
                  ],
                ),
                const SizedBox(height: AppSpacing.standard),
                Row(
                  children: [
                    Expanded(child: Text('Birth year', style: AppText.bodyText)),
                    SizedBox(
                      width: 90,
                      child: TextField(
                        controller: _birthYearController,
                        keyboardType: TextInputType.number,
                        textAlign: TextAlign.center,
                        style: AppText.bodyText,
                        decoration: const InputDecoration(hintText: 'e.g. 1998'),
                        onSubmitted: _saveBirthYear,
                        onTapOutside: (_) => _saveBirthYear(_birthYearController.text),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.small),
                Text(
                  'Used for bodyweight-ratio strength-standard goals — age and '
                  'gender both affect realistic targets, not shown anywhere else.',
                  style: AppText.smallText,
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.large),
          Text('Units', style: AppText.subHeader),
          const SizedBox(height: AppSpacing.standard),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: Text('Weight unit', style: AppText.bodyText)),
                    _UnitToggle(
                      selected: Units.current,
                      onChanged: _setUnit,
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.standard),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Hide my weight', style: AppText.bodyText),
                          const SizedBox(height: AppSpacing.micro),
                          Text(
                            'Masks your bodyweight as "---" everywhere it\'s '
                            'displayed — trends and progress still show, just not '
                            'the raw number. Lift weights (squat, bench, etc.) are '
                            'never affected. Entry/edit screens are unaffected.',
                            style: AppText.smallText,
                          ),
                        ],
                      ),
                    ),
                    Switch(
                      value: Units.hideWeight,
                      activeThumbColor: AppColors.accent,
                      onChanged: _setHideWeight,
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.large),
          Text('Goals', style: AppText.subHeader),
          const SizedBox(height: AppSpacing.standard),
          AppCard(
            child: Row(
              children: [
                Expanded(child: Text('Steps goal', style: AppText.bodyText)),
                SizedBox(
                  width: 90,
                  child: TextField(
                    controller: _stepsGoalController,
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    style: AppText.bodyText,
                    decoration: const InputDecoration(hintText: 'e.g. 10000'),
                    onSubmitted: _saveStepsGoal,
                    onTapOutside: (_) => _saveStepsGoal(_stepsGoalController.text),
                  ),
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
                Text('Reset demo data', style: AppText.bodyText),
                const SizedBox(height: AppSpacing.micro),
                Text(
                  _inDemoMode
                      ? 'Replaces the current demo set with a fresh ~2 '
                          'months of made-up lift, sleep, steps, soreness, '
                          'bodyweight, and cycle history. Your personal data '
                          'is a separate file and is never touched by this.'
                      : 'Switch to Demo (above) to use this — it regenerates '
                          'a fresh made-up data set, entirely separate from '
                          'your personal data.',
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
                    onPressed: _busy || !_inDemoMode ? null : _resetDemoData,
                    child: const Text('Reset Demo Data'),
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

class _ProfileToggle extends StatelessWidget {
  final AppProfile selected;
  final ValueChanged<AppProfile> onChanged;
  const _ProfileToggle({required this.selected, required this.onChanged});

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
        children: AppProfile.values.map((p) {
          final isSelected = p == selected;
          return GestureDetector(
            onTap: () => onChanged(p),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              decoration: BoxDecoration(
                color: isSelected ? AppColors.accent : Colors.transparent,
                borderRadius: BorderRadius.circular(AppRadius.pill),
              ),
              child: Text(
                p == AppProfile.personal ? 'Personal' : 'Demo',
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

class _GenderToggle extends StatelessWidget {
  final Gender selected;
  final ValueChanged<Gender> onChanged;
  const _GenderToggle({required this.selected, required this.onChanged});

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
        children: Gender.values.map((g) {
          final isSelected = g == selected;
          return GestureDetector(
            onTap: () => onChanged(g),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              decoration: BoxDecoration(
                color: isSelected ? AppColors.accent : Colors.transparent,
                borderRadius: BorderRadius.circular(AppRadius.pill),
              ),
              child: Text(
                g.label,
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
