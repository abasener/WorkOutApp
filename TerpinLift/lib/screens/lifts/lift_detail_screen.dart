import 'package:flutter/material.dart';
import 'package:flutter_body_heatmap/flutter_body_heatmap.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/models/exercise.dart';
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
import '../../widgets/strength_goal_gauge.dart';
import '../quick_log/log_lift_form.dart';
import 'add_exercise_sheet.dart';
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
    final sessions =
        await AppServices.lifts.getSessionsForExercise(widget.exercise.id!);
    // Re-fetch the exercise itself too, so edits (name/categories/YT link)
    // show up here immediately without needing to re-navigate.
    final exercise = await AppServices.exercises.getById(widget.exercise.id!);
    final muscleReadiness = await ReadinessEngine.computeMuscleReadiness();
    final latestBodyweight = await AppServices.bodyweight.getLatest();
    if (!mounted) return;
    setState(() {
      _sessions = sessions;
      if (exercise != null) _exercise = exercise;
      _muscleReadiness = muscleReadiness;
      _bodyweightLb = latestBodyweight?.weight;
      _loading = false;
    });
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
      builder: (_) => EditLiftSessionForm(exercise: _exercise, sessionWithSets: session),
    );
  }

  static const _compactPadding =
      EdgeInsets.symmetric(horizontal: AppSpacing.cardPad, vertical: AppSpacing.standard);

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
    final isBodyweightLift = _exercise.equipmentTags.contains(ExerciseType.bodyweight);
    final useBodyweightE1rm = isBodyweightLift && _bodyweightLb != null;
    double e1rmValueOf(SessionWithSets s) =>
        useBodyweightE1rm ? s.bodyweightAdjustedBestE1rm(_bodyweightLb!) : s.bestE1rm;

    final prediction = TrendEngine.predictNextE1rm(
      _sessions,
      valueOf: useBodyweightE1rm ? e1rmValueOf : null,
    );
    // Full history here — no 6-month cap, unlike the Home/Metrics dashboards.
    final e1rmPoints = _sessions.reversed
        .map((s) => ChartPoint(DateTime.parse(s.session.date), e1rmValueOf(s)))
        .where((p) => p.value > 0)
        .toList();
    final daysSince = TrendEngine.daysSinceLastTrained(_sessions);
    final intensity = TrendEngine.lastIntensity(_sessions);
    final musclesHit = MuscleMap.musclesFor(_exercise);
    final muscleData = {for (final m in musclesHit) m: const MuscleData(intensity: 1.0)};
    final readinessBars = ReadinessEngine.toBars(
        ReadinessEngine.readinessForExercise(_exercise, _muscleReadiness));
    final overview = MuscleMap.liftOverview[_exercise.name];

    // Predicted Next, converted to a rep range at the load the lift was most
    // recently trained at ("try for this next, at whatever load you're
    // currently using") — a different axis from the Goal gauge below, which
    // is deliberately pinned to plain-bodyweight reps to stay comparable to
    // published standards.
    (double, double, double)? repsPrediction;
    if (useBodyweightE1rm && prediction != null) {
      final recentWithSets = _sessions.where((s) => s.sets.isNotEmpty);
      final lastSession = recentWithSets.isEmpty ? null : recentWithSets.first;
      final lastAddedWeight = (lastSession == null || lastSession.sets.isEmpty)
          ? 0.0
          : lastSession.sets.map((s) => s.weight).reduce((a, b) => a > b ? a : b);
      final refLoad = (_bodyweightLb! + lastAddedWeight).clamp(1.0, double.infinity);
      double toReps(double value) => (30 * (value / refLoad - 1)).clamp(0.0, double.infinity);
      repsPrediction = (toReps(prediction.$1), toReps(prediction.$2), toReps(prediction.$3));
    }

    final sessionsWithE1rm = _sessions.where((s) => e1rmValueOf(s) > 0).toList();
    SessionWithSets? bestSession;
    for (final s in sessionsWithE1rm) {
      if (bestSession == null || e1rmValueOf(s) > e1rmValueOf(bestSession)) bestSession = s;
    }
    // The Epley-projected, decayed estimate — kept as a clearly-separate
    // "Predicted 1RM" number (below), never the gauge's fill/tier position.
    // That used to be the same number, which read as "the app claims I
    // lifted 115 when I only ever did 100x4" — an accidental inflation, not
    // a lie, but confusing without the projection being labeled as such.
    final predicted1Rm = bestSession == null
        ? null
        : StrengthStandards.effectiveBestE1rm(
            e1rmValueOf(bestSession),
            DateTime.parse(bestSession.session.date),
            DateTime.now(),
          );
    // The gauge's actual fill/tier position: the heaviest weight literally
    // logged on any set, ever — never Epley-projected, never decayed (a PR
    // is a historical fact, it doesn't un-happen if you take time off).
    // `null` (not 0) when nothing's logged yet, matching `predicted1Rm`'s
    // null-when-empty so the Goal section's existing gating still applies.
    final allWeights = _sessions.expand((s) => s.sets).map((set) => set.weight).toList();
    final trueMaxWeight =
        allWeights.isEmpty ? null : allWeights.reduce((a, b) => a > b ? a : b);
    final tierTargets = (_bodyweightLb != null && StrengthStandards.hasStandard(_exercise.name))
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
    final repStandardTargets = BodyweightRepStandards.hasStandard(_exercise.name)
        ? BodyweightRepStandards.allTargets(
            exerciseName: _exercise.name,
            gender: UserProfile.gender,
            ageBucket: UserProfile.ageBucket,
          )
        : null;
    SessionWithSets? bestBodyweightRepSession;
    int bestBodyweightReps = 0;
    for (final s in _sessions) {
      for (final set in s.sets) {
        if (set.weight == 0 && set.reps > bestBodyweightReps) {
          bestBodyweightReps = set.reps;
          bestBodyweightRepSession = s;
        }
      }
    }
    final prBestReps = bestBodyweightRepSession == null
        ? null
        : StrengthStandards.effectiveBestE1rm(
            bestBodyweightReps.toDouble(),
            DateTime.parse(bestBodyweightRepSession.session.date),
            DateTime.now(),
          );

    final goalTierTargets = isBodyweightLift ? repStandardTargets : tierTargets;
    final goalCurrentValue = isBodyweightLift ? prBestReps : trueMaxWeight;
    final goalPredictedValue = isBodyweightLift ? null : predicted1Rm;
    String Function(double)? goalFormatValue;
    if (isBodyweightLift) {
      goalFormatValue = (v) => '${v.round()} reps';
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(_exercise.name),
        actions: [
          IconButton(
            icon: Icon(_exercise.pinned ? Icons.push_pin : Icons.push_pin_outlined),
            color: _exercise.pinned ? AppColors.accent : null,
            tooltip: _exercise.pinned ? 'Unpin' : 'Pin — shows in the quick-log dropdown',
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
                          const InfoTooltip(glossaryKey: 'readiness', title: 'Readiness'),
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
          if (prediction != null) ...[
            AppCard(
              padding: _compactPadding,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        repsPrediction != null
                            ? 'Predicted Next Rep Range'
                            : 'Predicted Next e1RM Range',
                        style: AppText.label,
                      ),
                      InfoTooltip(
                        glossaryKey: 'e1rm',
                        title: repsPrediction != null
                            ? 'Predicted Next Rep Range'
                            : 'Predicted Next e1RM Range',
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.standard),
                  RangeIndicator(
                    low: repsPrediction?.$1 ?? prediction.$1,
                    goal: repsPrediction?.$2 ?? prediction.$2,
                    high: repsPrediction?.$3 ?? prediction.$3,
                    formatValue: repsPrediction != null ? (v) => '${v.round()} reps' : null,
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
                                colors: const [AppColors.muscleHigh, AppColors.muscleHigh],
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
                                colors: const [AppColors.muscleHigh, AppColors.muscleHigh],
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
                if (musclesHit.isNotEmpty) const SizedBox(width: AppSpacing.standard),
                Expanded(
                  child: AppCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('Overview', style: AppText.label),
                        const SizedBox(height: AppSpacing.small),
                        if (overview == null)
                          Text('No overview added for this movement yet.',
                              style: AppText.smallText)
                        else
                          ...overview.map((cue) => Padding(
                                padding: const EdgeInsets.only(bottom: AppSpacing.small),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Icon(cue.kind.icon,
                                        size: 14,
                                        color: cue.kind == CueKind.safety
                                            ? AppColors.warn
                                            : AppColors.textSecondary),
                                    const SizedBox(width: AppSpacing.micro),
                                    Expanded(
                                      child: Text(cue.text, style: AppText.smallText),
                                    ),
                                  ],
                                ),
                              )),
                        if (_exercise.youtubeUrl != null &&
                            _exercise.youtubeUrl!.isNotEmpty) ...[
                          const SizedBox(height: AppSpacing.standard),
                          OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: AppColors.border),
                              foregroundColor: AppColors.textPrimary,
                              minimumSize: const Size(double.infinity, 40),
                            ),
                            onPressed: () => launchUrl(Uri.parse(_exercise.youtubeUrl!)),
                            icon: const Icon(Icons.play_circle_outline, size: 18),
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
          Text('e1RM Trend', style: AppText.subHeader),
          const SizedBox(height: AppSpacing.standard),
          AppCard(
            child: CenteredTrendChart(
              points: e1rmPoints,
              showPrediction: true,
              trendStyle: TrendStyle.polynomial,
              yLabelFormatter: (v) => Units.format(v),
            ),
          ),
          if (goalTierTargets != null && goalCurrentValue != null) ...[
            const SizedBox(height: AppSpacing.large),
            Row(
              children: [
                Text('Goal', style: AppText.subHeader),
                InfoTooltip(
                  glossaryKey: isBodyweightLift ? 'strength_goal_bodyweight' : 'strength_goal',
                  title: 'Goal',
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.standard),
            AppCard(
              child: StrengthGoalGauge(
                tierTargets: goalTierTargets,
                currentE1rm: goalCurrentValue,
                predictedValue: goalPredictedValue,
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
            ..._sessions.map((s) => Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.cardGap),
                  child: AppCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(s.session.date, style: AppText.bodyText),
                            GestureDetector(
                              onTap: () => _editSession(s),
                              child: const Icon(Icons.edit_outlined,
                                  size: 18, color: AppColors.textSecondary),
                            ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.small),
                        ...s.sets.map((set) => Padding(
                              padding: const EdgeInsets.symmetric(vertical: 2),
                              child: Text(
                                'Set ${set.setNumber}: ${set.reps} reps @ ${Units.format(set.weight)}'
                                '${set.rpe != null ? ' · ${EffortDisplay.toDisplay(set.rpe!).toStringAsFixed(0)} reps left' : ''}',
                                style: AppText.smallText,
                              ),
                            )),
                        if (s.session.notes != null && s.session.notes!.isNotEmpty) ...[
                          const SizedBox(height: AppSpacing.small),
                          Text(
                            s.session.notes!,
                            style: AppText.smallText.copyWith(fontStyle: FontStyle.italic),
                          ),
                        ],
                      ],
                    ),
                  ),
                )),
          const SizedBox(height: AppSpacing.xLarge),
        ],
      ),
    );
  }
}
