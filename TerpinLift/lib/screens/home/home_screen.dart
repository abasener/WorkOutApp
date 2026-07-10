import 'package:flutter/material.dart';

import '../../data/models/exercise.dart';
import '../../data/models/metric_entry.dart';
import '../../data/repositories/lift_repository.dart';
import '../../services/app_services.dart';
import '../../services/training_composition_service.dart';
import '../../services/trend_engine.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_card.dart';
import '../../widgets/labeled_trend_chart.dart';
import '../../widgets/status_card.dart';
import '../../widgets/training_composition_chart.dart';
import '../../widgets/week_rings.dart';

const _dashboardHistoryDays = 183; // ~6 months, per designFiles/02_SCREEN_home.md

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
  final List<String> _flags = [];
  List<CategoryComposition> _compositions = [];

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
    final dates = await AppServices.lifts.getAllWorkoutDates();
    final exercises = await AppServices.exercises.getAll();
    final steps = await AppServices.metrics.getByType(MetricType.steps, limit: 14);
    final compositions = await TrainingCompositionService.compute();

    final sessionsByExercise = <int, List<SessionWithSets>>{};
    final flags = <String>[];
    for (final e in exercises) {
      if (e.id == null) continue;
      final sessions = await AppServices.lifts.getSessionsForExercise(e.id!);
      sessionsByExercise[e.id!] = sessions;
      final flag = TrendEngine.recencyFlag(sessions, e.name);
      if (flag != null) flags.add(flag);
    }

    if (!mounted) return;
    setState(() {
      _workoutDates = dates.toSet();
      _stepsByDate = {for (final m in steps) m.date: m.value};
      _exercises = exercises;
      _sessionsByExercise
        ..clear()
        ..addAll(sessionsByExercise);
      _flags
        ..clear()
        ..addAll(flags);
      _compositions = compositions;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: AppColors.accent));
    }

    final activeLifts = _exercises
        .where((e) => (_sessionsByExercise[e.id] ?? []).isNotEmpty)
        .take(4)
        .toList();

    final cutoff = DateTime.now().subtract(const Duration(days: _dashboardHistoryDays));

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
                  Text('This Week', style: AppText.subHeader),
                  const SizedBox(height: AppSpacing.standard),
                  AppCard(
                    child: WeekRings(
                      stepsByDate: _stepsByDate,
                      workoutDates: _workoutDates,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.large),
                  Text('Training Split', style: AppText.subHeader),
                  const SizedBox(height: AppSpacing.standard),
                  AppCard(
                    child: TrainingCompositionChart(compositions: _compositions),
                  ),
                  const SizedBox(height: AppSpacing.large),
                  Text('Strength Trends', style: AppText.subHeader),
                  const SizedBox(height: AppSpacing.standard),
                  if (activeLifts.isEmpty)
                    AppCard(
                      child: Text(
                        'Log your first lift to start seeing trends here.',
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
                  const SizedBox(height: AppSpacing.large),
                  Text('Status', style: AppText.subHeader),
                  const SizedBox(height: AppSpacing.standard),
                  if (_flags.isEmpty)
                    StatusCard.allGood()
                  else
                    ..._flags.map((f) => Padding(
                          padding: const EdgeInsets.only(bottom: AppSpacing.cardGap),
                          child: StatusCard(
                            icon: Icons.fitness_center,
                            text: f,
                            iconColor: AppColors.accent,
                          ),
                        )),
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
