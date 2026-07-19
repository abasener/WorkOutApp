import 'package:flutter/material.dart';
import 'package:flutter_body_heatmap/flutter_body_heatmap.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/models/custom_goal.dart';
import '../../data/models/distance_unit.dart';
import '../../data/models/exercise.dart';
import '../../data/repositories/cardio_repository.dart';
import '../../services/app_services.dart';
import '../../services/cardio_units.dart';
import '../../services/muscle_map.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_card.dart';
import '../../widgets/labeled_trend_chart.dart';
import '../../widgets/single_goal_gauge.dart';
import '../../widgets/tap_icon.dart';
import '../quick_log/log_cardio_form.dart';
import 'add_exercise_sheet.dart';
import 'cardio_goal_history_sheet.dart';
import 'edit_cardio_session_form.dart';

/// Cardio's counterpart to `LiftDetailScreen` — a deliberate fork, not a
/// parametrized shared screen, since reps/weight/e1RM/RPE-based prediction
/// don't have a cardio equivalent worth forcing into the same code. See
/// designFiles/11_SCREEN_cardio.md.
class CardioDetailScreen extends StatefulWidget {
  final Exercise exercise;
  const CardioDetailScreen({super.key, required this.exercise});

  @override
  State<CardioDetailScreen> createState() => _CardioDetailScreenState();
}

class _CardioDetailScreenState extends State<CardioDetailScreen> {
  bool _loading = true;
  List<CardioSessionWithEntries> _sessions = [];
  late Exercise _exercise = widget.exercise;
  List<CustomGoal> _customGoals = [];

  @override
  void initState() {
    super.initState();
    AppServices.reloadSignal.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    AppServices.reloadSignal.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    final sessions = await AppServices.cardio.getSessionsForExercise(
      widget.exercise.id!,
    );
    final exercise = await AppServices.exercises.getById(widget.exercise.id!);
    final customGoals = await AppServices.customGoals.getAllForExercise(
      widget.exercise.id!,
    );
    if (!mounted) return;
    setState(() {
      _sessions = sessions;
      if (exercise != null) _exercise = exercise;
      _customGoals = customGoals;
      _loading = false;
    });
  }

  Future<void> _editNotes() async {
    final controller = TextEditingController(text: _exercise.notes ?? '');
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Container(
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
              Text('Your Notes', style: AppText.subHeader),
              const SizedBox(height: AppSpacing.standard),
              TextField(
                controller: controller,
                style: AppText.bodyText,
                maxLines: 6,
                minLines: 3,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'Route notes, gear, whatever helps.',
                ),
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
                      borderRadius: BorderRadius.circular(AppRadius.button),
                    ),
                  ),
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Save'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (saved != true) return;
    final text = controller.text.trim();
    final updated = text.isEmpty
        ? _exercise.copyWith(clearNotes: true)
        : _exercise.copyWith(notes: text);
    await AppServices.exercises.update(updated);
    if (!mounted) return;
    setState(() => _exercise = updated);
    AppServices.signalReload();
  }

  Future<void> _openGoalHistory() async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => CardioGoalHistorySheet(exercise: _exercise),
    );
    await _load();
    AppServices.signalReload();
  }

  Future<void> _editExercise() async {
    final deleted = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => AddExerciseSheet(existing: _exercise),
    );
    if (deleted == true && mounted) Navigator.pop(context);
  }

  Future<void> _logEffort() async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => LogCardioForm(preselected: _exercise),
    );
  }

  Future<void> _togglePinned() async {
    final updated = _exercise.copyWith(pinned: !_exercise.pinned);
    await AppServices.exercises.update(updated);
    setState(() => _exercise = updated);
    AppServices.signalReload();
  }

  Future<void> _editSession(CardioSessionWithEntries session) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => EditCardioSessionForm(
        exercise: _exercise,
        sessionWithEntries: session,
      ),
    );
  }

  static const _compactPadding = EdgeInsets.symmetric(
    horizontal: AppSpacing.cardPad,
    vertical: AppSpacing.standard,
  );

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: AppColors.background,
        body: Center(child: CircularProgressIndicator(color: AppColors.accent)),
      );
    }

    final daysSince = _sessions.isEmpty
        ? null
        : DateTime.now()
              .difference(DateTime.parse(_sessions.first.session.date))
              .inDays;
    final lastSession = _sessions.isEmpty ? null : _sessions.first;
    final musclesHit = MuscleMap.musclesFor(_exercise);
    final muscleData = {
      for (final m in musclesHit) m: const MuscleData(intensity: 1.0),
    };
    final unit = _exercise.cardioUnit ?? CardioUnits.defaultUnit;

    double? lastSessionPace = lastSession == null
        ? null
        : CardioUnits.paceSecondsPerUnit(
            lastSession.totalDistanceCanonical,
            lastSession.totalDurationSeconds,
            unit,
          );

    // Distance History — each session's literal total distance (never
    // averaged), dot size encoded by that session's heaviest logged
    // resistance/load, same "encode a secondary fact as dot size" spirit as
    // the lift trend chart's rep-count dots. Full history, no 6-month cap.
    final distancePoints = _sessions.reversed
        .where((s) => s.totalDistanceCanonical > 0)
        .map(
          (s) => ChartPoint(
            DateTime.parse(s.session.date),
            s.totalDistanceCanonical,
            reps: s.maxLoad?.round(),
          ),
        )
        .toList();

    double bestDistanceCanonical = 0;
    double? bestPaceSecondsPerUnit; // smallest (fastest) across sessions
    for (final s in _sessions) {
      if (s.totalDistanceCanonical > bestDistanceCanonical) {
        bestDistanceCanonical = s.totalDistanceCanonical;
      }
      final pace = CardioUnits.paceSecondsPerUnit(
        s.totalDistanceCanonical,
        s.totalDurationSeconds,
        unit,
      );
      if (pace != null &&
          (bestPaceSecondsPerUnit == null || pace < bestPaceSecondsPerUnit)) {
        bestPaceSecondsPerUnit = pace;
      }
    }

    final distanceGoals = _customGoals
        .where((g) => g.targetDistance != null)
        .toList();
    final paceGoals = _customGoals.where((g) => g.targetPace != null).toList();
    final hasDistanceGoal =
        distanceGoals.isNotEmpty && bestDistanceCanonical > 0;
    final hasPaceGoal =
        unit.isRealDistance &&
        paceGoals.isNotEmpty &&
        bestPaceSecondsPerUnit != null;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(_exercise.name),
        actions: [
          IconButton(
            icon: Icon(
              _exercise.pinned ? Icons.push_pin : Icons.push_pin_outlined,
            ),
            color: _exercise.pinned ? AppColors.accent : null,
            tooltip: _exercise.pinned
                ? 'Unpin'
                : 'Pin (shows in the quick-log dropdown)',
            onPressed: _togglePinned,
          ),
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Log an effort',
            onPressed: _logEffort,
          ),
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'Edit movement',
            onPressed: _editExercise,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.edge),
        children: [
          Row(
            children: [
              Expanded(
                child: AppCard(
                  padding: _compactPadding,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Last trained', style: AppText.label),
                      const SizedBox(height: AppSpacing.micro),
                      Text(
                        daysSince == null
                            ? '—'
                            : daysSince == 0
                            ? 'Today'
                            : '$daysSince ${daysSince == 1 ? 'day' : 'days'} ago',
                        style: AppText.subHeader,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.small),
              Expanded(
                child: AppCard(
                  padding: _compactPadding,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Last distance', style: AppText.label),
                      const SizedBox(height: AppSpacing.micro),
                      Text(
                        lastSession == null ||
                                lastSession.totalDistanceCanonical <= 0
                            ? '—'
                            : CardioUnits.formatDistance(
                                lastSession.totalDistanceCanonical,
                                unit,
                              ),
                        style: AppText.subHeader,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.small),
              Expanded(
                child: AppCard(
                  padding: _compactPadding,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Last pace', style: AppText.label),
                      const SizedBox(height: AppSpacing.micro),
                      Text(
                        lastSessionPace == null
                            ? '—'
                            : CardioUnits.formatPace(lastSessionPace, unit),
                        style: AppText.subHeader,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.cardGap),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (musclesHit.isNotEmpty)
                  Expanded(
                    child: AppCard(
                      child: Row(
                        children: [
                          Expanded(
                            child: AspectRatio(
                              aspectRatio: 724 / 1448,
                              child: BodyHeatmap(
                                side: BodySide.front,
                                data: muscleData,
                                colors: const [
                                  AppColors.muscleHigh,
                                  AppColors.muscleHigh,
                                ],
                                bodyColor: AppColors.surfaceRaised,
                                borderColor: AppColors.textSecondary,
                                showBorder: true,
                              ),
                            ),
                          ),
                          Expanded(
                            child: AspectRatio(
                              aspectRatio: 724 / 1448,
                              child: BodyHeatmap(
                                side: BodySide.back,
                                data: muscleData,
                                colors: const [
                                  AppColors.muscleHigh,
                                  AppColors.muscleHigh,
                                ],
                                bodyColor: AppColors.surfaceRaised,
                                borderColor: AppColors.textSecondary,
                                showBorder: true,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                if (musclesHit.isNotEmpty)
                  const SizedBox(width: AppSpacing.standard),
                Expanded(
                  child: AppCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            Text('Notes', style: AppText.label),
                            const Spacer(),
                            TapIcon(
                              icon: Icons.edit_outlined,
                              size: 16,
                              onTap: _editNotes,
                            ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.small),
                        Text(
                          _exercise.notes?.isNotEmpty == true
                              ? _exercise.notes!
                              : 'No notes yet. Tap the pencil to add your own.',
                          style: AppText.smallText,
                        ),
                        if (_exercise.youtubeUrl != null &&
                            _exercise.youtubeUrl!.isNotEmpty) ...[
                          const SizedBox(height: AppSpacing.standard),
                          OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: AppColors.border),
                              foregroundColor: AppColors.textPrimary,
                              minimumSize: const Size(double.infinity, 40),
                            ),
                            onPressed: () =>
                                launchUrl(Uri.parse(_exercise.youtubeUrl!)),
                            icon: const Icon(
                              Icons.play_circle_outline,
                              size: 18,
                            ),
                            label: const Text('Watch form video'),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.large),
          Text('Distance History', style: AppText.subHeader),
          const SizedBox(height: AppSpacing.standard),
          AppCard(
            child: CenteredTrendChart(
              points: distancePoints,
              yLabelFormatter: (v) => CardioUnits.formatDistance(v, unit),
            ),
          ),
          if (hasDistanceGoal || hasPaceGoal) ...[
            const SizedBox(height: AppSpacing.large),
            Row(
              children: [
                Text('Goals', style: AppText.subHeader),
                const Spacer(),
                IconButton(
                  icon: const Icon(
                    Icons.tune,
                    size: 18,
                    color: AppColors.textSecondary,
                  ),
                  tooltip: 'Your goals',
                  onPressed: _openGoalHistory,
                ),
              ],
            ),
            if (hasDistanceGoal) ...[
              const SizedBox(height: AppSpacing.standard),
              Text('Distance', style: AppText.label),
              const SizedBox(height: AppSpacing.small),
              AppCard(
                child: SingleGoalGauge(
                  goals: distanceGoals
                      .map(
                        (g) => GoalMarker(
                          value: g.targetDistance!,
                          label: g.label?.isNotEmpty == true
                              ? g.label!
                              : g.created.substring(0, 10),
                        ),
                      )
                      .toList(),
                  current: bestDistanceCanonical,
                  currentLabel: 'Best distance',
                  formatValue: (v) => CardioUnits.formatDistance(v, unit),
                ),
              ),
            ],
            if (hasPaceGoal) ...[
              const SizedBox(height: AppSpacing.standard),
              Text('Pace', style: AppText.label),
              const SizedBox(height: AppSpacing.small),
              AppCard(
                child: SingleGoalGauge(
                  goals: paceGoals
                      .map(
                        (g) => GoalMarker(
                          value: g.targetPace! * unit.paceUnitMeters,
                          label: g.label?.isNotEmpty == true
                              ? g.label!
                              : g.created.substring(0, 10),
                        ),
                      )
                      .toList(),
                  current: bestPaceSecondsPerUnit,
                  currentLabel: 'Best pace',
                  lowerIsBetter: true,
                  formatValue: (v) => CardioUnits.formatPace(v, unit),
                ),
              ),
            ],
          ] else
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.standard),
              child: GestureDetector(
                onTap: _openGoalHistory,
                child: Text(
                  'Set a distance or pace goal →',
                  style: AppText.smallText,
                ),
              ),
            ),
          const SizedBox(height: AppSpacing.large),
          Text('History', style: AppText.subHeader),
          const SizedBox(height: AppSpacing.standard),
          if (_sessions.isEmpty)
            Text('No sessions logged yet.', style: AppText.smallText)
          else
            ..._sessions.map(
              (s) => Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.cardGap),
                child: AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(s.session.date, style: AppText.bodyText),
                          TapIcon(
                            icon: Icons.edit_outlined,
                            onTap: () => _editSession(s),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.small),
                      ...s.entries.map((e) {
                        final parts = <String>[];
                        if (e.distanceCanonical != null) {
                          parts.add(
                            CardioUnits.formatDistance(
                              e.distanceCanonical!,
                              unit,
                            ),
                          );
                        }
                        if (e.durationSeconds != null) {
                          parts.add(
                            'in ${CardioUnits.formatDuration(e.durationSeconds!)}',
                          );
                        }
                        final entryPace = CardioUnits.paceSecondsPerUnit(
                          e.distanceCanonical,
                          e.durationSeconds,
                          unit,
                        );
                        if (entryPace != null) {
                          parts.add(
                            '(${CardioUnits.formatPace(entryPace, unit)})',
                          );
                        }
                        if (e.load != null) {
                          parts.add(
                            '· resistance ${e.load!.toStringAsFixed(0)}',
                          );
                        }
                        if (e.rpe != null) {
                          parts.add('· effort ${e.rpe!.toStringAsFixed(0)}/10');
                        }
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Text(
                            parts.isEmpty
                                ? 'Effort ${e.entryNumber}'
                                : parts.join(' '),
                            style: AppText.smallText,
                          ),
                        );
                      }),
                      if (s.session.notes != null &&
                          s.session.notes!.isNotEmpty) ...[
                        const SizedBox(height: AppSpacing.small),
                        Text(
                          s.session.notes!,
                          style: AppText.smallText.copyWith(
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          const SizedBox(height: AppSpacing.xLarge),
        ],
      ),
    );
  }
}
