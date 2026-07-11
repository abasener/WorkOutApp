import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/models/exercise.dart';
import '../../data/models/workout_plan.dart';
import '../../data/repositories/lift_repository.dart';
import '../../services/app_services.dart';
import '../../services/workout_plan_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_card.dart';
import 'pattern_pool_screen.dart';

/// The "movement set" page (user-facing: part of a "session") — the meat of
/// the Workout Planner. Shows the active day's pattern slots, what's
/// already been done for each (derived live, see `WorkoutPlanService`), an
/// optional elapsed timer, a soft progress bar, notes, and Abort/Complete.
/// See designFiles/10_WORKOUT_PLANNER.md.
class ActiveDayScreen extends StatefulWidget {
  final PlannedSession session;
  final WorkoutTemplateDay day;

  const ActiveDayScreen({super.key, required this.session, required this.day});

  @override
  State<ActiveDayScreen> createState() => _ActiveDayScreenState();
}

class _ActiveDayScreenState extends State<ActiveDayScreen> {
  late PlannedSession _session = widget.session;
  bool _loading = true;
  List<SessionWithSets> _allSessions = [];
  Map<int, Exercise> _exercisesById = {};
  late final _notesController = TextEditingController(text: widget.session.notes ?? '');
  Timer? _ticker;
  Duration _elapsed = Duration.zero;

  bool get _isActive => _session.status == PlannedSessionStatus.active;

  @override
  void initState() {
    super.initState();
    AppServices.reloadSignal.addListener(_load);
    _load();
    if (_isActive) {
      _elapsed = DateTime.now().difference(DateTime.parse(_session.startedAt));
      _ticker = Timer.periodic(const Duration(seconds: 30), (_) {
        if (!mounted) return;
        setState(() => _elapsed = DateTime.now().difference(DateTime.parse(_session.startedAt)));
      });
    }
  }

  @override
  void dispose() {
    AppServices.reloadSignal.removeListener(_load);
    _ticker?.cancel();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final exercises = await AppServices.exercises.getAll();
    final sessions = await AppServices.lifts.getAllSessions();
    if (!mounted) return;
    setState(() {
      _allSessions = sessions;
      _exercisesById = {for (final e in exercises) if (e.id != null) e.id!: e};
      _loading = false;
    });
  }

  Future<void> _saveNotes(String text) async {
    final updated = _session.copyWith(notes: text);
    await AppServices.workoutPlans.updateSession(updated);
    setState(() => _session = updated);
  }

  Future<void> _openSlot(MovementPattern pattern) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => PatternPoolScreen(pattern: pattern)),
    );
  }

  Future<void> _abort() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceRaised,
        title: Text('Abort this session?', style: AppText.subHeader),
        content: Text(
          'Anything you\'ve already logged stays in your history — this just '
          'clears the active session.',
          style: AppText.bodyText,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: AppText.bodyText),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Abort', style: TextStyle(color: AppColors.accent)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await AppServices.workoutPlans.abortSession(_session.id!);
    AppServices.signalReload();
    if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
  }

  Future<void> _complete() async {
    await AppServices.workoutPlans.completeSession(_session.id!);
    AppServices.signalReload();
    if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
  }

  Future<void> _saveChanges() async {
    await _saveNotes(_notesController.text);
    AppServices.signalReload();
    if (mounted) Navigator.pop(context);
  }

  Future<void> _deleteWorkout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceRaised,
        title: Text('Delete this workout?', style: AppText.subHeader),
        content: Text(
          'The lifts you logged stay in your history — this just removes '
          'the day grouping around them.',
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
    await AppServices.workoutPlans.deleteSession(_session.id!);
    AppServices.signalReload();
    if (mounted) Navigator.pop(context);
  }

  String get _elapsedLabel {
    final h = _elapsed.inHours;
    final m = _elapsed.inMinutes % 60;
    return h > 0 ? '${h}h ${m}m' : '${m}m';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: Text(widget.day.dayLabel)),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.accent))
          : ListView(
              padding: const EdgeInsets.all(AppSpacing.edge),
              children: [
                AppCard(
                  child: Row(
                    children: [
                      if (_isActive) ...[
                        const Icon(Icons.timer_outlined,
                            size: 18, color: AppColors.textSecondary),
                        const SizedBox(width: AppSpacing.micro),
                        Text(_elapsedLabel, style: AppText.smallText),
                        const Spacer(),
                      ],
                      Text(
                        '${(_progressFraction() * 100).round()}% covered',
                        style: AppText.smallText,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.small),
                ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                  child: LinearProgressIndicator(
                    value: _progressFraction(),
                    minHeight: 6,
                    backgroundColor: AppColors.border,
                    // Soft/muted, deliberately not the accent red — this
                    // isn't a requirement bar, just a glance-able cue.
                    color: AppColors.good,
                  ),
                ),
                const SizedBox(height: AppSpacing.large),
                ...widget.day.patterns.map(_slotCard),
                const SizedBox(height: AppSpacing.large),
                Text('Notes', style: AppText.label),
                const SizedBox(height: AppSpacing.small),
                TextField(
                  controller: _notesController,
                  style: AppText.bodyText,
                  maxLines: 3,
                  decoration: const InputDecoration(hintText: 'Optional'),
                  onTapOutside: (_) => _saveNotes(_notesController.text),
                  onSubmitted: _saveNotes,
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
                    onPressed: _isActive ? _complete : _saveChanges,
                    child: Text(_isActive ? 'Complete' : 'Save changes'),
                  ),
                ),
                const SizedBox(height: AppSpacing.standard),
                SizedBox(
                  width: double.infinity,
                  height: 44,
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: AppColors.border),
                      foregroundColor: AppColors.textSecondary,
                    ),
                    onPressed: _isActive ? _abort : _deleteWorkout,
                    child: Text(_isActive ? 'Abort' : 'Delete workout'),
                  ),
                ),
                const SizedBox(height: AppSpacing.xLarge),
              ],
            ),
    );
  }

  double _progressFraction() => WorkoutPlanService.progressFraction(
        _session.date,
        widget.day.patterns,
        _allSessions,
        _exercisesById,
      );

  Widget _slotCard(MovementPattern pattern) {
    final matches = WorkoutPlanService.matchedSessions(
      _session.date,
      pattern,
      _allSessions,
      _exercisesById,
    );
    final poolSize = _exercisesById.values.where((e) => e.patterns.contains(pattern)).length;
    final doneNames = matches
        .map((s) => _exercisesById[s.session.exerciseId]?.name)
        .whereType<String>()
        .toSet()
        .join(', ');

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.cardGap),
      child: AppCard(
        onTap: () => _openSlot(pattern),
        child: Row(
          children: [
            Icon(
              matches.isEmpty ? Icons.radio_button_unchecked : Icons.check_circle_outline,
              color: matches.isEmpty ? AppColors.textSecondary : AppColors.good,
              size: 20,
            ),
            const SizedBox(width: AppSpacing.standard),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(pattern.label, style: AppText.bodyText),
                  const SizedBox(height: AppSpacing.micro),
                  Text(
                    matches.isEmpty ? '$poolSize lifts' : doneNames,
                    style: AppText.smallText,
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: AppColors.textSecondary),
          ],
        ),
      ),
    );
  }
}
