import 'package:flutter/material.dart';
import 'package:flutter_body_heatmap/flutter_body_heatmap.dart' show Muscle;

import '../../data/models/exercise.dart';
import '../../data/repositories/lift_repository.dart';
import '../../services/app_services.dart';
import '../../services/readiness_engine.dart';
import '../../services/units.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_card.dart';
import '../../widgets/readiness_bars.dart';
import 'add_exercise_sheet.dart';
import 'edit_lift_session_form.dart';
import 'lift_detail_screen.dart';

class LiftsScreen extends StatefulWidget {
  const LiftsScreen({super.key});

  @override
  State<LiftsScreen> createState() => _LiftsScreenState();
}

class _LiftsScreenState extends State<LiftsScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabController = TabController(length: 2, vsync: this);

  List<Exercise> _exercises = [];
  List<SessionWithSets> _allSessions = [];
  Map<Muscle, double> _muscleReadiness = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    AppServices.reloadSignal.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    AppServices.reloadSignal.removeListener(_load);
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final exercises = await AppServices.exercises.getAll();
    final allSessions = await AppServices.lifts.getAllSessions();
    final muscleReadiness = await ReadinessEngine.computeMuscleReadiness();
    if (!mounted) return;
    setState(() {
      _exercises = exercises;
      _allSessions = allSessions;
      _muscleReadiness = muscleReadiness;
      _loading = false;
    });
  }

  Future<void> _addCustom() async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const AddExerciseSheet(),
    );
  }

  Future<void> _editSession(SessionWithSets session) async {
    final exercise = _exercises.firstWhere((e) => e.id == session.session.exerciseId);
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => EditLiftSessionForm(exercise: exercise, sessionWithSets: session),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: AppColors.accent));
    }
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Lifts'),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppColors.accent,
          labelColor: AppColors.textPrimary,
          unselectedLabelColor: AppColors.textSecondary,
          tabs: const [Tab(text: 'Lifts'), Tab(text: 'Workouts')],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [_buildLiftsTab(), _buildWorkoutsTab()],
      ),
    );
  }

  Widget _buildLiftsTab() {
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.edge),
      children: [
        ..._exercises.map((e) {
          final readiness = ReadinessEngine.toBars(
              ReadinessEngine.readinessForExercise(e, _muscleReadiness));
          return Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.cardGap),
            child: AppCard(
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => LiftDetailScreen(exercise: e)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(e.name, style: AppText.bodyText),
                        const SizedBox(height: AppSpacing.small),
                        Wrap(
                          spacing: AppSpacing.micro,
                          runSpacing: AppSpacing.micro,
                          children:
                              e.categories.map((c) => _CategoryPill(label: c.label)).toList(),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.standard),
                  Column(
                    children: [
                      ReadinessBars(readiness: readiness),
                      const SizedBox(height: AppSpacing.micro),
                      const Icon(Icons.chevron_right, color: AppColors.textSecondary),
                    ],
                  ),
                ],
              ),
            ),
          );
        }),
        const SizedBox(height: AppSpacing.large),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            side: const BorderSide(color: AppColors.accent),
            foregroundColor: AppColors.accent,
            minimumSize: const Size(double.infinity, 52),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.button)),
          ),
          onPressed: _addCustom,
          icon: const Icon(Icons.add),
          label: const Text('Add custom movement'),
        ),
        const SizedBox(height: AppSpacing.xLarge),
      ],
    );
  }

  Widget _buildWorkoutsTab() {
    if (_allSessions.isEmpty) {
      return Center(
        child: Text('No workouts logged yet.', style: AppText.smallText),
      );
    }

    final maxRpeSum = _allSessions
        .map((s) => s.rpeSum)
        .fold<double>(0, (a, b) => a > b ? a : b)
        .clamp(1.0, double.infinity);

    final byDate = <String, List<SessionWithSets>>{};
    for (final s in _allSessions) {
      byDate.putIfAbsent(s.session.date, () => []).add(s);
    }
    final dates = byDate.keys.toList()..sort((a, b) => b.compareTo(a));

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.edge),
      children: [
        for (final date in dates) ...[
          Text(date, style: AppText.subHeader),
          const SizedBox(height: AppSpacing.standard),
          for (final s in byDate[date]!)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.cardGap),
              child: _WorkoutRow(
                session: s,
                exerciseName: _exercises
                    .firstWhere((e) => e.id == s.session.exerciseId,
                        orElse: () => Exercise(
                            name: 'Unknown',
                            categories: const [],
                            isSeeded: false,
                            created: ''))
                    .name,
                intensityFraction: (s.rpeSum / maxRpeSum).clamp(0.0, 1.0),
                onEdit: () => _editSession(s),
              ),
            ),
          const SizedBox(height: AppSpacing.standard),
        ],
        const SizedBox(height: AppSpacing.xLarge),
      ],
    );
  }
}

class _WorkoutRow extends StatelessWidget {
  final SessionWithSets session;
  final String exerciseName;
  final double intensityFraction; // 0-1, relative to hardest logged session
  final VoidCallback onEdit;

  const _WorkoutRow({
    required this.session,
    required this.exerciseName,
    required this.intensityFraction,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final barColor =
        Color.lerp(AppColors.border, AppColors.accent, intensityFraction) ?? AppColors.border;
    final topWeight = session.sets.isEmpty
        ? 0.0
        : session.sets.map((s) => s.weight).reduce((a, b) => a > b ? a : b);

    return AppCard(
      child: Row(
        children: [
          Container(width: 4, height: 40, color: barColor),
          const SizedBox(width: AppSpacing.standard),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(exerciseName, style: AppText.bodyText),
                const SizedBox(height: AppSpacing.micro),
                Text(
                  '${session.sets.length} sets · top ${Units.format(topWeight)}',
                  style: AppText.smallText,
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: onEdit,
            child: const Icon(Icons.edit_outlined, size: 18, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _CategoryPill extends StatelessWidget {
  final String label;
  const _CategoryPill({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.surfaceRaised,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: AppColors.border),
      ),
      child: Text(label, style: AppText.smallText.copyWith(fontSize: 11)),
    );
  }
}
