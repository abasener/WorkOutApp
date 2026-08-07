import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;

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
///
/// **Viewing a completed session also exposes editable start/end times**
/// (2026-07-17) — added after a real workout's recorded duration read far
/// shorter than it actually was. Root cause: the Metrics "Workout Duration"
/// chart used to be built entirely from individual lift-log Track Time
/// windows, which measure how long *that logging form* stayed open, not the
/// real workout length. This screen's own start/complete timestamps
/// (`PlannedSession.startedAt`/`completedAt` — already set correctly by
/// `startSession`/`completeSession`, no lifecycle bug there) are the
/// authoritative whole-workout duration when one exists, and now override
/// the lift-session sum for that date (`TrendEngine.
/// workoutDurationMinutesByDate`) instead of being ignored by it. These
/// fields were already right in most cases; this UI just lets a wrong one
/// get fixed after the fact.
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
  late final _notesController = TextEditingController(
    text: widget.session.notes ?? '',
  );
  Timer? _ticker;
  Duration _elapsed = Duration.zero;

  // Editable start/complete times for a **completed** session — added after
  // the user found a workout's recorded duration read far shorter than it
  // actually was (a lift session's own timer measures how long its log form
  // stayed open, not the real workout length — see `TrendEngine.
  // workoutDurationMinutesByDate`). Only meaningful once `completedAt`
  // exists; kept as plain `DateTime` (not ISO strings) so `showTimePicker`
  // has something to seed from directly.
  late DateTime _editedStart = DateTime.parse(widget.session.startedAt);
  late DateTime? _editedEnd = widget.session.completedAt == null
      ? null
      : DateTime.parse(widget.session.completedAt!);

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
        setState(
          () => _elapsed = DateTime.now().difference(
            DateTime.parse(_session.startedAt),
          ),
        );
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
      _exercisesById = {
        for (final e in exercises)
          if (e.id != null) e.id!: e,
      };
      _loading = false;
    });
  }

  Future<void> _saveNotes(String text) async {
    final updated = _session.copyWith(notes: text);
    await AppServices.workoutPlans.updateSession(updated);
    setState(() => _session = updated);
  }

  Future<void> _pickStart() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_editedStart),
    );
    if (picked == null) return;
    setState(
      () => _editedStart = DateTime(
        _editedStart.year,
        _editedStart.month,
        _editedStart.day,
        picked.hour,
        picked.minute,
      ),
    );
  }

  Future<void> _pickEnd() async {
    final base = _editedEnd ?? _editedStart;
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(base),
    );
    if (picked == null) return;
    setState(
      () => _editedEnd = DateTime(
        base.year,
        base.month,
        base.day,
        picked.hour,
        picked.minute,
      ),
    );
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
          'Anything you\'ve already logged stays in your history. This just '
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
            child: const Text(
              'Abort',
              style: TextStyle(color: AppColors.accent),
            ),
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
    // Times only make sense to edit once the workout's actually complete —
    // an active session's start time is still live-tracked, and it has no
    // end yet.
    final updated = _session.copyWith(
      notes: _notesController.text,
      startedAt: _isActive ? null : _editedStart.toIso8601String(),
      completedAt: _isActive || _editedEnd == null
          ? null
          : _editedEnd!.toIso8601String(),
    );
    await AppServices.workoutPlans.updateSession(updated);
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
          'The lifts you logged stay in your history. This just removes '
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
            child: const Text(
              'Delete',
              style: TextStyle(color: AppColors.accent),
            ),
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

  String _formatTime(DateTime t) => DateFormat('h:mm a').format(t);

  /// Live-recomputed as the user adjusts the start/end pickers, so editing
  /// makes it immediately obvious "which side it cut short" — the whole
  /// point of exposing this at all.
  String get _editedDurationLabel {
    final end = _editedEnd;
    if (end == null) return '';
    final minutes = end.difference(_editedStart).inMinutes;
    if (minutes <= 0) return 'Duration: —';
    final h = minutes ~/ 60;
    final m = minutes % 60;
    return h > 0 ? 'Duration: ${h}h ${m}m' : 'Duration: ${m}m';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: Text(widget.day.dayLabel)),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.accent),
            )
          : ListView(
              padding: const EdgeInsets.all(AppSpacing.edge),
              children: [
                AppCard(
                  child: Row(
                    children: [
                      if (_isActive) ...[
                        const Icon(
                          Icons.timer_outlined,
                          size: 18,
                          color: AppColors.textSecondary,
                        ),
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
                if (!_isActive &&
                    _session.status == PlannedSessionStatus.completed) ...[
                  const SizedBox(height: AppSpacing.large),
                  Row(
                    children: [
                      Text('Start / End Time', style: AppText.label),
                      const Spacer(),
                      if (_editedEnd != null)
                        Text(_editedDurationLabel, style: AppText.smallText),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.small),
                  Text(
                    'Fix these if a workout logged short. A lift log form '
                    'only tracks how long it was open, not the real workout '
                    'length.',
                    style: AppText.smallText,
                  ),
                  const SizedBox(height: AppSpacing.standard),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: AppColors.border),
                            foregroundColor: AppColors.textPrimary,
                          ),
                          onPressed: _pickStart,
                          child: Text('Start: ${_formatTime(_editedStart)}'),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.standard),
                      Expanded(
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: AppColors.border),
                            foregroundColor: AppColors.textPrimary,
                          ),
                          onPressed: _pickEnd,
                          child: Text(
                            _editedEnd == null
                                ? 'End: —'
                                : 'End: ${_formatTime(_editedEnd!)}',
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: AppSpacing.large),
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
    final poolSize = _exercisesById.values
        .where((e) => e.patterns.contains(pattern))
        .length;
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
              matches.isEmpty
                  ? Icons.radio_button_unchecked
                  : Icons.check_circle_outline,
              color: matches.isEmpty ? AppColors.textSecondary : AppColors.good,
              size: 20,
            ),
            const SizedBox(width: AppSpacing.standard),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(pattern.label, style: AppText.bodyText),
                      const SizedBox(width: AppSpacing.micro),
                      // Filled = a "main" pattern (squat/hinge/push/pull) —
                      // where effort should go first when fresh; outline =
                      // accessory/prehab. Reuses the existing main/accessory
                      // split (`MovementPatternLabel.isMain`) rather than a
                      // new rating scale, per the app's no-gamified-score
                      // convention (00_UX_DESIGN.md).
                      Icon(
                        pattern.isMain ? Icons.star : Icons.star_outline,
                        size: 14,
                        color: AppColors.textSecondary,
                      ),
                    ],
                  ),
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
