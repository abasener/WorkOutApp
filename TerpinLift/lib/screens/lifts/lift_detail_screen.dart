import 'package:flutter/material.dart';
import 'package:flutter_body_heatmap/flutter_body_heatmap.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/models/exercise.dart';
import '../../data/repositories/lift_repository.dart';
import '../../services/app_services.dart';
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

    final prediction = TrendEngine.predictNextE1rm(_sessions);
    // Full history here — no 6-month cap, unlike the Home/Metrics dashboards.
    final e1rmPoints = _sessions.reversed
        .map((s) => ChartPoint(DateTime.parse(s.session.date), s.bestE1rm))
        .where((p) => p.value > 0)
        .toList();
    final daysSince = TrendEngine.daysSinceLastTrained(_sessions);
    final intensity = TrendEngine.lastIntensity(_sessions);
    final musclesHit = MuscleMap.musclesFor(_exercise);
    final muscleData = {for (final m in musclesHit) m: const MuscleData(intensity: 1.0)};
    final readinessBars = ReadinessEngine.toBars(
        ReadinessEngine.readinessForExercise(_exercise, _muscleReadiness));
    final overview = MuscleMap.liftOverview[_exercise.name];

    final sessionsWithE1rm = _sessions.where((s) => s.bestE1rm > 0).toList();
    SessionWithSets? bestSession;
    for (final s in sessionsWithE1rm) {
      if (bestSession == null || s.bestE1rm > bestSession.bestE1rm) bestSession = s;
    }
    final prBestE1rm = bestSession == null
        ? null
        : StrengthStandards.effectiveBestE1rm(
            bestSession.bestE1rm,
            DateTime.parse(bestSession.session.date),
            DateTime.now(),
          );
    final tierTargets = (_bodyweightLb != null && StrengthStandards.hasStandard(_exercise.name))
        ? StrengthStandards.allTargets(
            exerciseName: _exercise.name,
            bodyweightLb: _bodyweightLb!,
            gender: UserProfile.gender,
            ageBucket: UserProfile.ageBucket,
          )
        : null;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(_exercise.name),
        actions: [
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
                      Text('Predicted Next e1RM Range', style: AppText.label),
                      const InfoTooltip(glossaryKey: 'e1rm', title: 'Predicted Next e1RM Range'),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.standard),
                  RangeIndicator(
                    low: prediction.$1,
                    goal: prediction.$2,
                    high: prediction.$3,
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
            ),
          ),
          if (tierTargets != null && prBestE1rm != null) ...[
            const SizedBox(height: AppSpacing.large),
            Row(
              children: [
                Text('Goal', style: AppText.subHeader),
                const InfoTooltip(glossaryKey: 'strength_goal', title: 'Goal'),
              ],
            ),
            const SizedBox(height: AppSpacing.standard),
            AppCard(
              child: StrengthGoalGauge(
                tierTargets: tierTargets,
                currentE1rm: prBestE1rm,
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
                                '${set.rpe != null ? ' · RPE ${set.rpe!.toStringAsFixed(1)}' : ''}',
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
