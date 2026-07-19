import 'package:flutter/material.dart';
import 'package:flutter_body_heatmap/flutter_body_heatmap.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/models/custom_goal.dart';
import '../../data/models/exercise.dart';
import '../../data/models/lift_set.dart';
import '../../data/repositories/lift_repository.dart';
import '../../services/app_services.dart';
import '../../services/bodyweight_rep_standards.dart';
import '../../services/effort_display.dart';
import '../../services/muscle_map.dart';
import '../../services/readiness_engine.dart';
import '../../services/strength_standards.dart';
import '../../services/trend_engine.dart';
import '../../services/units.dart';
import '../../services/user_profile.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_card.dart';
import '../../widgets/info_tooltip.dart';
import '../../widgets/labeled_trend_chart.dart';
import '../../widgets/range_indicator.dart';
import '../../widgets/readiness_segmented_bar.dart';
import '../../widgets/single_goal_gauge.dart';
import '../../widgets/strength_goal_gauge.dart';
import '../../widgets/tap_icon.dart';
import '../quick_log/log_lift_form.dart';
import 'add_exercise_sheet.dart';
import 'custom_goal_history_sheet.dart';
import 'edit_lift_session_form.dart';

class LiftDetailScreen extends StatefulWidget {
  final Exercise exercise;
  const LiftDetailScreen({super.key, required this.exercise});

  @override
  State<LiftDetailScreen> createState() => _LiftDetailScreenState();
}

class _LiftDetailScreenState extends State<LiftDetailScreen> {
  bool _loading = true;
  List<SessionWithSets> _sessions = [];
  late Exercise _exercise = widget.exercise;
  Map<Muscle, double> _muscleReadiness = {};
  double? _bodyweightLb;
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
    final sessions = await AppServices.lifts.getSessionsForExercise(
      widget.exercise.id!,
    );
    // Re-fetch the exercise itself too, so edits (name/categories/YT link)
    // show up here immediately without needing to re-navigate.
    final exercise = await AppServices.exercises.getById(widget.exercise.id!);
    final muscleReadiness = await ReadinessEngine.computeMuscleReadiness();
    final latestBodyweight = await AppServices.bodyweight.getLatest();
    final customGoals = await AppServices.customGoals.getAllForExercise(
      widget.exercise.id!,
    );
    if (!mounted) return;
    setState(() {
      _sessions = sessions;
      if (exercise != null) _exercise = exercise;
      _muscleReadiness = muscleReadiness;
      _bodyweightLb = latestBodyweight?.weight;
      _customGoals = customGoals;
      _loading = false;
    });
  }

  Widget _goalSourceChip(String label, GoalSource source, GoalSource? active) {
    final selected = source == active;
    return GestureDetector(
      onTap: () => _setGoalSource(source),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.accent.withValues(alpha: 0.15)
              : AppColors.surfaceRaised,
          border: Border.all(
            color: selected ? AppColors.accent : AppColors.border,
          ),
          borderRadius: BorderRadius.circular(AppRadius.pill),
        ),
        child: Text(
          label,
          style: AppText.smallText.copyWith(
            color: selected ? AppColors.accent : AppColors.textSecondary,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
          ),
        ),
      ),
    );
  }

  Future<void> _setGoalSource(GoalSource source) async {
    final updated = _exercise.goalSource == source
        ? _exercise.copyWith(clearGoalSource: true)
        : _exercise.copyWith(goalSource: source);
    await AppServices.exercises.update(updated);
    setState(() => _exercise = updated);
    AppServices.signalReload();
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
                  hintText: 'Form cues, reminders, whatever helps.',
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

  Future<void> _openCustomGoalHistory({required bool isBodyweightLift}) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => CustomGoalHistorySheet(
        exerciseId: _exercise.id!,
        isBodyweightLift: isBodyweightLift,
      ),
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
    // The exercise this screen was showing no longer exists — leave it.
    if (deleted == true && mounted) Navigator.pop(context);
  }

  Future<void> _logSet() async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => LogLiftForm(preselected: _exercise),
    );
  }

  Future<void> _togglePinned() async {
    final updated = _exercise.copyWith(pinned: !_exercise.pinned);
    await AppServices.exercises.update(updated);
    setState(() => _exercise = updated);
    AppServices.signalReload();
  }

  Future<void> _editSession(SessionWithSets session) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) =>
          EditLiftSessionForm(exercise: _exercise, sessionWithSets: session),
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

    // Bodyweight-tagged lifts (pull-ups, push-ups, ...) store `weight` as
    // added/assisted load, not total load — Epley breaks down at 0/negative
    // weight, so these use `bodyweightAdjustedBestE1rm` (bodyweight + added
    // load) wherever "e1RM" is computed, and the Goal gauge switches to a
    // rep-count standards table instead of a bodyweight-ratio one. See
    // designFiles/07_SMART_TRENDS.md.
    final isBodyweightLift = _exercise.equipmentTags.contains(
      ExerciseType.bodyweight,
    );
    final useBodyweightE1rm = isBodyweightLift && _bodyweightLb != null;
    double e1rmValueOf(SessionWithSets s) => useBodyweightE1rm
        ? s.bodyweightAdjustedBestE1rm(_bodyweightLb!)
        : s.bestE1rm;
    double Function(LiftSet)? repLoadOf = useBodyweightE1rm
        ? (set) => _bodyweightLb! + set.weight
        : null;

    // "Next Heavy Set" — what to aim for at the rep count this lift is
    // usually gone heavy at, projected from recent history at that same rep
    // count (see `TrendEngine.predictNextAtCharacteristicReps`; no rep-to-1RM
    // conversion involved, so no formula to get wrong the way the old e1RM
    // range did on a near-failure multi-rep set).
    final nextHeavySet = TrendEngine.predictNextAtCharacteristicReps(
      _sessions,
      loadOf: repLoadOf,
    );

    // Trend chart: each session's literal heaviest-set weight (bodyweight-
    // adjusted where relevant) — never a formula estimate — with the rep
    // count on that set encoded as dot size, and a dashed trend line shaped
    // by e1RM (comparable across differing rep counts) but re-centered onto
    // this raw-weight scale. Full history — no 6-month cap, unlike the
    // Home/Metrics dashboards.
    final strengthPoints = _sessions.reversed
        .where((s) => s.sets.isNotEmpty)
        .map((s) {
          double load(LiftSet set) =>
              useBodyweightE1rm ? _bodyweightLb! + set.weight : set.weight;
          final heaviest = s.sets.reduce((a, b) => load(a) >= load(b) ? a : b);
          return ChartPoint(
            DateTime.parse(s.session.date),
            load(heaviest),
            reps: heaviest.reps,
            trendValue: e1rmValueOf(s),
          );
        })
        .where((p) => p.value > 0)
        .toList();

    final daysSince = TrendEngine.daysSinceLastTrained(_sessions);
    final intensity = TrendEngine.lastIntensity(_sessions);
    final musclesHit = MuscleMap.musclesFor(_exercise);
    final muscleData = {
      for (final m in musclesHit) m: const MuscleData(intensity: 1.0),
    };
    final readinessBars = ReadinessEngine.toBars(
      ReadinessEngine.readinessForExercise(_exercise, _muscleReadiness),
    );

    // Goal gauge's "Predicted 1RM" line — most-recent-history only, no decay
    // (see `TrendEngine.predictedOneRepMax`). Not a meaningful concept for
    // the bodyweight-reps variant of this gauge.
    final predicted1Rm = isBodyweightLift
        ? null
        : TrendEngine.predictedOneRepMax(_sessions, gender: UserProfile.gender);

    // The gauge's actual fill/tier position: the heaviest weight literally
    // logged on any set, ever — never Epley-projected, never decayed (a PR
    // is a historical fact, it doesn't un-happen if you take time off).
    // `null` when nothing's logged yet.
    LiftSet? trueMaxSet;
    for (final s in _sessions) {
      for (final set in s.sets) {
        if (trueMaxSet == null || set.weight > trueMaxSet.weight) {
          trueMaxSet = set;
        }
      }
    }
    final trueMaxWeight = trueMaxSet?.weight;
    final trueMaxReps = trueMaxSet?.reps;

    final standardTierTargets =
        (_bodyweightLb != null && StrengthStandards.hasStandard(_exercise.name))
        ? StrengthStandards.allTargets(
            exerciseName: _exercise.name,
            bodyweightLb: _bodyweightLb!,
            gender: UserProfile.gender,
            ageBucket: UserProfile.ageBucket,
          )
        : null;

    // Goal gauge's rep-count side: pinned to plain-bodyweight sets only
    // (added load == 0), since published pull-up/push-up standards assume
    // unassisted, unweighted reps — a weighted or assisted PR isn't
    // comparable to that table.
    final repStandardTargets =
        BodyweightRepStandards.hasStandard(_exercise.name)
        ? BodyweightRepStandards.allTargets(
            exerciseName: _exercise.name,
            gender: UserProfile.gender,
            ageBucket: UserProfile.ageBucket,
          )
        : null;
    int bestBodyweightReps = 0;
    for (final s in _sessions) {
      for (final set in s.sets) {
        if (set.weight == 0 && set.reps > bestBodyweightReps) {
          bestBodyweightReps = set.reps;
        }
      }
    }
    final prBestReps = bestBodyweightReps == 0
        ? null
        : bestBodyweightReps.toDouble();

    final goalStandardTierTargets = isBodyweightLift
        ? repStandardTargets
        : standardTierTargets;
    final goalCurrentValue = isBodyweightLift ? prBestReps : trueMaxWeight;
    final goalPredictedValue = isBodyweightLift ? null : predicted1Rm;
    String Function(double)? goalFormatValue;
    if (isBodyweightLift) {
      goalFormatValue = (v) => '${v.round()} reps';
    }

    // Most recent entry in the goal log decides *whether* the custom-goal
    // path is even available (see `hasCustomGoal` below) — but the gauge
    // itself plots every matching entry as its own tick, not just the
    // newest, so older goals stay visible/nameable on the bar rather than
    // disappearing the moment a new one is added.
    final latestCustomGoal = _customGoals.isEmpty ? null : _customGoals.first;
    final customGoalMarkers = _customGoals
        .where(
          (g) =>
              isBodyweightLift ? g.targetReps != null : g.targetWeight != null,
        )
        .map(
          (g) => GoalMarker(
            value: isBodyweightLift
                ? g.targetReps!.toDouble()
                : g.targetWeight!,
            label: g.label?.isNotEmpty == true
                ? g.label!
                : g.created.substring(0, 10),
          ),
        )
        .toList();
    final hasStandardGoal =
        goalStandardTierTargets != null && goalCurrentValue != null;
    final hasCustomGoal =
        goalCurrentValue != null &&
        latestCustomGoal != null &&
        (isBodyweightLift
            ? latestCustomGoal.targetReps != null
            : latestCustomGoal.targetWeight != null);
    var effectiveGoalSource =
        _exercise.goalSource ??
        (hasStandardGoal
            ? GoalSource.standard
            : (hasCustomGoal ? GoalSource.custom : null));
    if (effectiveGoalSource == GoalSource.standard && !hasStandardGoal) {
      effectiveGoalSource = hasCustomGoal ? GoalSource.custom : null;
    }
    if (effectiveGoalSource == GoalSource.custom && !hasCustomGoal) {
      effectiveGoalSource = hasStandardGoal ? GoalSource.standard : null;
    }

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
            tooltip: 'Log a set',
            onPressed: _logSet,
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
          // Compact stat row — mostly text, doesn't need full card height.
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
                      Text('Last intensity', style: AppText.label),
                      const SizedBox(height: AppSpacing.micro),
                      Text(intensity?.label ?? '—', style: AppText.subHeader),
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
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('Readiness', style: AppText.label),
                          const InfoTooltip(
                            glossaryKey: 'readiness',
                            title: 'Readiness',
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.small),
                      ReadinessSegmentedBar(readiness: readinessBars),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.cardGap),
          if (nextHeavySet != null) ...[
            AppCard(
              padding: _compactPadding,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text('Next Heavy Set', style: AppText.label),
                      const InfoTooltip(
                        glossaryKey: 'next_heavy_set',
                        title: 'Next Heavy Set',
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.micro),
                  Text(
                    'You tend to go heavy for ${nextHeavySet.reps} '
                    '${nextHeavySet.reps == 1 ? 'rep' : 'reps'}. Here\'s a target for next time.',
                    style: AppText.smallText,
                  ),
                  const SizedBox(height: AppSpacing.standard),
                  RangeIndicator(
                    low: nextHeavySet.low,
                    goal: nextHeavySet.goal,
                    high: nextHeavySet.high,
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.cardGap),
          ],
          // Muscle map (left half) + overview/how-to/video (right half).
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
          Text('Heavy Set History', style: AppText.subHeader),
          const SizedBox(height: AppSpacing.standard),
          AppCard(
            child: CenteredTrendChart(
              points: strengthPoints,
              showPrediction: true,
              trendStyle: TrendStyle.polynomial,
              yLabelFormatter: (v) => Units.format(v),
            ),
          ),
          if (effectiveGoalSource != null) ...[
            const SizedBox(height: AppSpacing.large),
            Row(
              children: [
                Text('Goal', style: AppText.subHeader),
                InfoTooltip(
                  glossaryKey: isBodyweightLift
                      ? 'strength_goal_bodyweight'
                      : 'strength_goal',
                  title: 'Goal',
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(
                    Icons.tune,
                    size: 18,
                    color: AppColors.textSecondary,
                  ),
                  tooltip: 'Your goals',
                  onPressed: () => _openCustomGoalHistory(
                    isBodyweightLift: isBodyweightLift,
                  ),
                ),
              ],
            ),
            if (hasStandardGoal && hasCustomGoal) ...[
              const SizedBox(height: AppSpacing.small),
              Row(
                children: [
                  _goalSourceChip(
                    'Standard',
                    GoalSource.standard,
                    effectiveGoalSource,
                  ),
                  const SizedBox(width: AppSpacing.small),
                  _goalSourceChip(
                    'My Goal',
                    GoalSource.custom,
                    effectiveGoalSource,
                  ),
                ],
              ),
            ],
            const SizedBox(height: AppSpacing.standard),
            AppCard(
              child: effectiveGoalSource == GoalSource.custom
                  ? SingleGoalGauge(
                      goals: customGoalMarkers,
                      current: goalCurrentValue!,
                      currentReps: isBodyweightLift ? null : trueMaxReps,
                      predictedValue: goalPredictedValue,
                      formatValue: goalFormatValue,
                    )
                  : StrengthGoalGauge(
                      tierTargets: goalStandardTierTargets!,
                      currentE1rm: goalCurrentValue!,
                      predictedValue: goalPredictedValue,
                      currentReps: isBodyweightLift ? null : trueMaxReps,
                      formatValue: goalFormatValue,
                    ),
            ),
          ],
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
                      ...s.sets.map(
                        (set) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Text(
                            'Set ${set.setNumber}: ${set.reps} reps @ ${Units.format(set.weight)}'
                            '${set.rpe != null ? ' · ${EffortDisplay.toDisplay(set.rpe!).toStringAsFixed(0)} reps left' : ''}',
                            style: AppText.smallText,
                          ),
                        ),
                      ),
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
