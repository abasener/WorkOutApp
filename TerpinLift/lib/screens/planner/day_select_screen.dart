import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_body_heatmap/flutter_body_heatmap.dart' show Muscle;
import 'package:share_plus/share_plus.dart';

import '../../data/models/exercise.dart';
import '../../data/models/workout_plan.dart';
import '../../services/app_services.dart';
import '../../services/plan_export_service.dart';
import '../../services/readiness_engine.dart';
import '../../services/workout_plan_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_card.dart';
import '../../widgets/plan_import_review_sheet.dart';
import '../../widgets/readiness_bars.dart';
import 'active_day_screen.dart';

/// Day-first entry point for the Workout Planner (designFiles/
/// 10_WORKOUT_PLANNER.md) — lists the active template's days, most-overdue
/// first. Selecting a day starts a session and opens `ActiveDayScreen`.
/// **Which template is "active"** (multiple can be saved, only one shows
/// here at a time — `AppServices.activeTemplateId`, switched via the
/// AppBar's "Switch plan" action) falls back to `getDefaultTemplate()` when
/// unset, matching this screen's behavior before switching existed. The
/// Workouts tab (past logged history) never filters by this — a session
/// logged under a plan that's no longer active still resolves correctly
/// there (`WorkoutPlanRepository.getAllDaysById()`).
class DaySelectScreen extends StatefulWidget {
  const DaySelectScreen({super.key});

  @override
  State<DaySelectScreen> createState() => _DaySelectScreenState();
}

class _DaySelectScreenState extends State<DaySelectScreen> {
  bool _loading = true;
  WorkoutTemplate? _template;
  List<WorkoutTemplateDay> _days = [];
  Map<int, PlannedSession> _latestByDay = {};
  List<Exercise> _exercises = [];
  Map<Muscle, double> _muscleReadiness = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final activeId = AppServices.activeTemplateId;
    final template = activeId == null
        ? await AppServices.workoutPlans.getDefaultTemplate()
        : await AppServices.workoutPlans.getTemplate(activeId);
    if (template?.id == null) {
      if (!mounted) return;
      setState(() {
        _template = null;
        _loading = false;
      });
      return;
    }
    final days = await AppServices.workoutPlans.getDaysForTemplate(
      template!.id!,
    );
    final latest = await AppServices.workoutPlans.latestSessionPerDay();
    final exercises = await AppServices.exercises.getAll();
    final muscleReadiness = await ReadinessEngine.computeMuscleReadiness();
    days.sort((a, b) {
      final da = latest[a.id]?.date;
      final db = latest[b.id]?.date;
      if (da == null && db == null) return a.dayOrder.compareTo(b.dayOrder);
      if (da == null) return -1;
      if (db == null) return 1;
      return db.compareTo(da); // more recent date sorts later -> older first
    });
    if (!mounted) return;
    setState(() {
      _template = template;
      _days = days;
      _latestByDay = latest;
      _exercises = exercises;
      _muscleReadiness = muscleReadiness;
      _loading = false;
    });
  }

  Future<void> _switchPlan() async {
    final templates = await AppServices.workoutPlans.getAllTemplates();
    if (!mounted) return;
    final picked = await showModalBottomSheet<WorkoutTemplate>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _PlanPicker(templates: templates, current: _template),
    );
    if (picked?.id == null) return;
    await AppServices.setActiveTemplateId(picked!.id!);
    setState(() => _loading = true);
    await _load();
  }

  // Every saved template, one sheet each, named after it — a friendly,
  // human-editable format (movement pattern names, not ids), distinct from
  // Settings' raw whole-app backup. See plan_export_service.dart.
  Future<void> _exportTemplates() async {
    final path = await PlanExportService.exportWorkoutTemplates();
    if (!mounted) return;
    await SharePlus.instance.share(
      ShareParams(files: [XFile(path)], subject: 'TerrapinLift workout plans'),
    );
  }

  // Same "browse phone/Drive/wherever" native picker Settings' backup
  // import already uses (`SettingsScreen._import`), not a raw path field.
  Future<void> _importTemplates() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.any,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final picked = result.files.single;
    Uint8List? bytes = picked.bytes;
    if (bytes == null && picked.path != null) {
      bytes = await File(picked.path!).readAsBytes();
    }
    if (bytes == null || bytes.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not read that file.')),
      );
      return;
    }

    final parsed = await PlanExportService.parseWorkoutPlanImport(bytes);
    if (!mounted) return;
    final rows = [
      for (final p in parsed)
        ImportReviewRow(
          name: p.name,
          alreadyExists: p.alreadyExists,
          unmatchedNames: p.unmatchedPatternLabels,
        ),
    ];
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => PlanImportReviewSheet(rows: rows),
    );
    if (confirmed != true) return;

    await PlanExportService.commitWorkoutPlanImport([
      for (var i = 0; i < parsed.length; i++)
        WorkoutPlanImportDecision(parsed: parsed[i], skip: rows[i].skip),
    ]);
    if (!mounted) return;
    setState(() => _loading = true);
    await _load();
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Import complete.')));
  }

  String _recencyLabel(WorkoutTemplateDay day) {
    final last = _latestByDay[day.id];
    if (last == null) return 'Never done';
    final days = DateTime.now().difference(DateTime.parse(last.date)).inDays;
    if (days == 0) return 'Done today';
    return '$days ${days == 1 ? 'day' : 'days'} ago';
  }

  Future<void> _selectDay(WorkoutTemplateDay day) async {
    final session = await AppServices.workoutPlans.startSession(day.id!);
    AppServices.signalReload();
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => ActiveDayScreen(session: session, day: day),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Plan a Session'),
        actions: [
          IconButton(
            icon: const Icon(Icons.list_alt_outlined),
            tooltip: 'Switch plan',
            onPressed: _switchPlan,
          ),
          IconButton(
            tooltip: 'Export saved plans',
            icon: const Icon(Icons.upload_outlined),
            onPressed: _exportTemplates,
          ),
          IconButton(
            tooltip: 'Import plans',
            icon: const Icon(Icons.download_outlined),
            onPressed: _importTemplates,
          ),
        ],
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.accent),
            )
          : _days.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.edge),
                child: Text('No plan loaded yet.', style: AppText.smallText),
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(AppSpacing.edge),
              children: _days.map((day) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.cardGap),
                  child: AppCard(
                    onTap: () => _selectDay(day),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(day.dayLabel, style: AppText.bodyText),
                              const SizedBox(height: AppSpacing.micro),
                              Text(
                                day.patterns.map((p) => p.label).join(', '),
                                style: AppText.smallText,
                              ),
                              const SizedBox(height: AppSpacing.micro),
                              Text(
                                _recencyLabel(day),
                                style: AppText.smallText,
                              ),
                            ],
                          ),
                        ),
                        Column(
                          children: [
                            ReadinessBars(
                              readiness: WorkoutPlanService.dayReadinessBars(
                                day.patterns,
                                _exercises,
                                _muscleReadiness,
                              ),
                            ),
                            const SizedBox(height: AppSpacing.micro),
                            const Icon(
                              Icons.chevron_right,
                              color: AppColors.textSecondary,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
    );
  }
}

/// Bottom sheet listing every saved `WorkoutTemplate` — picking one becomes
/// the new active plan (`AppServices.setActiveTemplateId`). If nothing's
/// been saved beyond the seeded default, this just shows that one entry.
class _PlanPicker extends StatelessWidget {
  final List<WorkoutTemplate> templates;
  final WorkoutTemplate? current;

  const _PlanPicker({required this.templates, required this.current});

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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Switch plan', style: AppText.subHeader),
            const SizedBox(height: AppSpacing.standard),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: templates.map((t) {
                  final isSelected = t.id == current?.id;
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(t.name, style: AppText.bodyText),
                    trailing: Icon(
                      isSelected
                          ? Icons.radio_button_checked
                          : Icons.radio_button_unchecked,
                      color: isSelected
                          ? AppColors.accent
                          : AppColors.textSecondary,
                    ),
                    onTap: () => Navigator.pop(context, t),
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
