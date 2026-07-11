import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_body_heatmap/flutter_body_heatmap.dart';

import '../../data/models/exercise.dart';
import '../../data/models/metric_entry.dart';
import '../../data/models/workout_plan.dart';
import '../../data/repositories/lift_repository.dart';
import '../../services/app_services.dart';
import '../../services/home_trend_settings.dart';
import '../../services/readiness_engine.dart';
import '../../services/training_composition_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_card.dart';
import '../../widgets/info_tooltip.dart';
import '../../widgets/labeled_trend_chart.dart';
import '../../widgets/muscle_status_row.dart';
import '../../widgets/primed_lifts_row.dart';
import '../../widgets/training_composition_chart.dart';
import '../../widgets/week_rings.dart';
import '../lifts/lift_detail_screen.dart';
import '../planner/active_day_screen.dart';
import '../planner/day_select_screen.dart';
import 'home_trend_picker_sheet.dart';

// Zero-state fallback (no pins yet, no customized selection) caps at this
// many recently-active lifts — see designFiles/02_SCREEN_home.md.
const _defaultTrendLiftCount = 4;

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _loading = true;
  Set<String> _workoutDates = {};
  Map<String, double> _stepsByDate = {};
  List<Exercise> _exercises = [];
  final Map<int, List<SessionWithSets>> _sessionsByExercise = {};
  List<CategoryComposition> _compositions = [];
  Map<Muscle, double> _readiness = {};
  List<CategoryStatus> _categoryStatuses = [];
  List<Exercise> _primedLifts = [];
  PlannedSession? _activeSession;
  WorkoutTemplateDay? _activeDay;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    AppServices.reloadSignal.addListener(_load);
    _load();
    // Only matters while a session is active (the card's elapsed-time
    // display) — harmless no-op rebuild otherwise.
    _ticker = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted && _activeSession != null) setState(() {});
    });
  }

  @override
  void dispose() {
    AppServices.reloadSignal.removeListener(_load);
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final dates = await AppServices.lifts.getAllWorkoutDates();
    final exercises = await AppServices.exercises.getAll();
    final steps = await AppServices.metrics.getByType(MetricType.steps, limit: 14);
    final compositions = await TrainingCompositionService.compute();
    final readiness = await ReadinessEngine.computeMuscleReadiness();
    final categoryStatuses = await ReadinessEngine.computeCategoryStatus();

    final sessionsByExercise = <int, List<SessionWithSets>>{};
    for (final e in exercises) {
      if (e.id == null) continue;
      sessionsByExercise[e.id!] = await AppServices.lifts.getSessionsForExercise(e.id!);
    }

    final primedLifts = ReadinessEngine.suggestPrimedLifts(exercises, readiness);

    final activeSession = await AppServices.workoutPlans.getActiveSession();
    final activeDay = activeSession == null
        ? null
        : await AppServices.workoutPlans.getDay(activeSession.templateDayId);

    if (!mounted) return;
    setState(() {
      _workoutDates = dates.toSet();
      _stepsByDate = {for (final m in steps) m.date: m.value};
      _exercises = exercises;
      _sessionsByExercise
        ..clear()
        ..addAll(sessionsByExercise);
      _compositions = compositions;
      _readiness = readiness;
      _categoryStatuses = categoryStatuses;
      _primedLifts = primedLifts;
      _activeSession = activeSession;
      _activeDay = activeDay;
      _loading = false;
    });
  }

  String get _elapsedLabel {
    final session = _activeSession;
    if (session == null) return '';
    final elapsed = DateTime.now().difference(DateTime.parse(session.startedAt));
    final h = elapsed.inHours;
    final m = elapsed.inMinutes % 60;
    return h > 0 ? '${h}h ${m}m' : '${m}m';
  }

  Widget _buildPlannerCard(BuildContext context) {
    final session = _activeSession;
    final day = _activeDay;
    if (session == null || day == null) {
      return AppCard(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const DaySelectScreen()),
        ),
        child: Row(
          children: [
            const Icon(Icons.event_note_outlined, color: AppColors.textSecondary),
            const SizedBox(width: AppSpacing.standard),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Plan a session', style: AppText.bodyText),
                  const SizedBox(height: AppSpacing.micro),
                  Text('See what\'s ready to train', style: AppText.smallText),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: AppColors.textSecondary),
          ],
        ),
      );
    }

    return AppCard(
      backgroundColor: AppColors.accentDim,
      borderColor: AppColors.accent,
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => ActiveDayScreen(session: session, day: day)),
      ),
      child: Row(
        children: [
          const Icon(Icons.event_note, color: AppColors.accent),
          const SizedBox(width: AppSpacing.standard),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(day.dayLabel, style: AppText.bodyText),
                const SizedBox(height: AppSpacing.micro),
                Text('$_elapsedLabel · tap to resume', style: AppText.smallText),
              ],
            ),
          ),
          const Icon(Icons.chevron_right, color: AppColors.accent),
        ],
      ),
    );
  }

  Future<void> _openTrendPicker(List<Exercise> currentlyShown) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => HomeTrendPickerSheet(
        exercises: _exercises,
        selectedIds: currentlyShown.map((e) => e.id).whereType<int>().toSet(),
        months: HomeTrendSettings.months,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: AppColors.accent));
    }

    final customIds = HomeTrendSettings.exerciseIds;
    List<Exercise> activeLifts;
    if (customIds != null) {
      final byId = {for (final e in _exercises) if (e.id != null) e.id!: e};
      activeLifts = customIds.map((id) => byId[id]).whereType<Exercise>().toList();
    } else {
      // Zero state: no customized selection yet -> pinned lifts (the "usual
      // suspects"), falling back further to recently-active ones if nothing
      // is pinned either (e.g. a very fresh install).
      final pinned = _exercises.where((e) => e.pinned).toList();
      activeLifts = (pinned.isNotEmpty ? pinned : _exercises)
          .where((e) => (_sessionsByExercise[e.id] ?? []).isNotEmpty)
          .take(_defaultTrendLiftCount)
          .toList();
    }

    final now = DateTime.now();
    final months = HomeTrendSettings.months;
    final cutoff = DateTime(now.year, now.month - months, now.day);

    return RefreshIndicator(
      color: AppColors.accent,
      onRefresh: _load,
      child: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            backgroundColor: AppColors.background,
            title: const Text('TerpinLift'),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.edge),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AppCard(child: MuscleStatusRow(statuses: _categoryStatuses)),
                  const SizedBox(height: AppSpacing.standard),
                  _buildPlannerCard(context),
                  const SizedBox(height: AppSpacing.large),
                  Text('This Week', style: AppText.subHeader),
                  const SizedBox(height: AppSpacing.standard),
                  AppCard(
                    child: WeekRings(
                      stepsByDate: _stepsByDate,
                      workoutDates: _workoutDates,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.large),
                  Row(
                    children: [
                      Text('Primed for Growth', style: AppText.subHeader),
                      const InfoTooltip(
                        glossaryKey: 'readiness',
                        title: 'Primed for Growth',
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.standard),
                  AppCard(
                    child: SizedBox(
                      height: 160,
                      child: Row(
                        children: [
                          Expanded(
                            child: AspectRatio(
                              aspectRatio: 724 / 1448,
                              child: BodyHeatmap(
                                side: BodySide.front,
                                data: {
                                  for (final entry in _readiness.entries)
                                    entry.key: MuscleData(intensity: entry.value),
                                },
                                colors: const [AppColors.surfaceRaised, AppColors.good],
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
                                data: {
                                  for (final entry in _readiness.entries)
                                    entry.key: MuscleData(intensity: entry.value),
                                },
                                colors: const [AppColors.surfaceRaised, AppColors.good],
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
                  const SizedBox(height: AppSpacing.standard),
                  PrimedLiftsRow(
                    lifts: _primedLifts,
                    onTap: (e) => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => LiftDetailScreen(exercise: e)),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.large),
                  Text('Training Split', style: AppText.subHeader),
                  const SizedBox(height: AppSpacing.standard),
                  AppCard(
                    child: TrainingCompositionChart(compositions: _compositions),
                  ),
                  const SizedBox(height: AppSpacing.large),
                  Row(
                    children: [
                      Text('Strength Trends', style: AppText.subHeader),
                      GestureDetector(
                        onTap: () => _openTrendPicker(activeLifts),
                        child: const Padding(
                          padding: EdgeInsets.all(AppSpacing.micro),
                          child: Icon(Icons.edit_outlined,
                              size: 16, color: AppColors.textSecondary),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.standard),
                  if (activeLifts.isEmpty)
                    AppCard(
                      child: Text(
                        customIds != null
                            ? 'No lifts selected — tap the pencil above to choose some.'
                            : 'Log your first lift to start seeing trends here.',
                        style: AppText.smallText,
                      ),
                    )
                  else
                    ...activeLifts.map((e) {
                      final sessions = _sessionsByExercise[e.id] ?? [];
                      final points = sessions.reversed
                          .where((s) => DateTime.parse(s.session.date).isAfter(cutoff))
                          .map((s) => ChartPoint(
                              DateTime.parse(s.session.date), s.bestE1rm))
                          .where((p) => p.value > 0)
                          .toList();
                      return Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.cardGap),
                        child: AppCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(e.name, style: AppText.bodyText),
                              const SizedBox(height: AppSpacing.small),
                              CenteredTrendChart(
                                points: points,
                                showPrediction: true,
                                trendStyle: TrendStyle.polynomial,
                              ),
                            ],
                          ),
                        ),
                      );
                    }),
                  const SizedBox(height: AppSpacing.xLarge),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
