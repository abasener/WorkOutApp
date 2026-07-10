import 'package:flutter/material.dart';
import 'package:flutter_body_heatmap/flutter_body_heatmap.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/models/exercise.dart';
import '../../data/repositories/lift_repository.dart';
import '../../services/app_services.dart';
import '../../services/muscle_map.dart';
import '../../services/trend_engine.dart';
import '../../services/units.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_card.dart';
import '../../widgets/info_tooltip.dart';
import '../../widgets/labeled_trend_chart.dart';
import '../../widgets/range_indicator.dart';
import 'add_exercise_sheet.dart';

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
    if (!mounted) return;
    setState(() {
      _sessions = sessions;
      if (exercise != null) _exercise = exercise;
      _loading = false;
    });
  }

  Future<void> _editExercise() async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => AddExerciseSheet(existing: _exercise),
    );
  }

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
          Wrap(
            spacing: AppSpacing.micro,
            runSpacing: AppSpacing.micro,
            children: _exercise.categories
                .map((c) => Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceRaised,
                        borderRadius: BorderRadius.circular(AppRadius.pill),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Text(c.label,
                          style: AppText.smallText.copyWith(fontSize: 11)),
                    ))
                .toList(),
          ),
          const SizedBox(height: AppSpacing.cardGap),
          if (_exercise.youtubeUrl != null && _exercise.youtubeUrl!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.cardGap),
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: AppColors.border),
                  foregroundColor: AppColors.textPrimary,
                  minimumSize: const Size(double.infinity, 48),
                ),
                onPressed: () => launchUrl(Uri.parse(_exercise.youtubeUrl!)),
                icon: const Icon(Icons.play_circle_outline),
                label: const Text('Watch form video'),
              ),
            ),
          if (musclesHit.isNotEmpty) ...[
            Text('Muscles Worked', style: AppText.subHeader),
            const SizedBox(height: AppSpacing.standard),
            AppCard(
              child: Row(
                children: [
                  Expanded(
                    child: AspectRatio(
                      aspectRatio: 724 / 1448,
                      child: BodyHeatmap(
                        side: BodySide.front,
                        data: muscleData,
                        colors: const [AppColors.accent, AppColors.accent],
                        bodyColor: AppColors.surfaceRaised,
                        borderColor: AppColors.textSecondary,
                        showBorder: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.standard),
                  Expanded(
                    child: AspectRatio(
                      aspectRatio: 724 / 1448,
                      child: BodyHeatmap(
                        side: BodySide.back,
                        data: muscleData,
                        colors: const [AppColors.accent, AppColors.accent],
                        bodyColor: AppColors.surfaceRaised,
                        borderColor: AppColors.textSecondary,
                        showBorder: true,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.large),
          ],
          Row(
            children: [
              Expanded(
                child: AppCard(
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
              const SizedBox(width: AppSpacing.cardGap),
              Expanded(
                child: AppCard(
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
            ],
          ),
          const SizedBox(height: AppSpacing.large),
          if (prediction != null) ...[
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text('Predicted Next e1RM', style: AppText.label),
                      const InfoTooltip(glossaryKey: 'e1rm', title: 'Predicted Next e1RM'),
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
            const SizedBox(height: AppSpacing.large),
          ],
          Text('e1RM Trend', style: AppText.subHeader),
          const SizedBox(height: AppSpacing.standard),
          AppCard(
            child: CenteredTrendChart(
              points: e1rmPoints,
              showPrediction: true,
              trendStyle: TrendStyle.polynomial,
            ),
          ),
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
                        Text(s.session.date, style: AppText.bodyText),
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
