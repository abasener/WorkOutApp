import 'package:flutter/material.dart';

import '../../data/models/exercise.dart';
import '../../data/repositories/lift_repository.dart';
import '../../services/app_services.dart';
import '../../services/trend_engine.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_card.dart';
import '../../widgets/readiness_bars.dart';
import 'add_exercise_sheet.dart';
import 'lift_detail_screen.dart';

class LiftsScreen extends StatefulWidget {
  const LiftsScreen({super.key});

  @override
  State<LiftsScreen> createState() => _LiftsScreenState();
}

class _LiftsScreenState extends State<LiftsScreen> {
  List<Exercise> _exercises = [];
  final Map<int, List<SessionWithSets>> _sessionsByExercise = {};
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
    super.dispose();
  }

  Future<void> _load() async {
    final exercises = await AppServices.exercises.getAll();
    final sessionsByExercise = <int, List<SessionWithSets>>{};
    for (final e in exercises) {
      if (e.id == null) continue;
      sessionsByExercise[e.id!] = await AppServices.lifts.getSessionsForExercise(e.id!);
    }
    if (!mounted) return;
    setState(() {
      _exercises = exercises;
      _sessionsByExercise
        ..clear()
        ..addAll(sessionsByExercise);
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

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: AppColors.accent));
    }
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Lifts')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.edge),
        children: [
          ..._exercises.map((e) {
            final sessions = _sessionsByExercise[e.id] ?? [];
            final readiness = TrendEngine.readinessScore(sessions);
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
                            children: e.categories
                                .map((c) => _CategoryPill(label: c.label))
                                .toList(),
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
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.button)),
            ),
            onPressed: _addCustom,
            icon: const Icon(Icons.add),
            label: const Text('Add custom movement'),
          ),
          const SizedBox(height: AppSpacing.xLarge),
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
