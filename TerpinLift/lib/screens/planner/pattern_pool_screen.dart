import 'package:flutter/material.dart';

import '../../data/models/exercise.dart';
import '../../services/app_services.dart';
import '../../services/readiness_engine.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_card.dart';
import '../../widgets/readiness_bars.dart';
import '../lifts/lift_detail_screen.dart';

/// The exercise pool for one [MovementPattern], readiness-sorted (most
/// primed first) so the "which one's actually open/ready" decision is made
/// for you as much as the app can — see designFiles/10_WORKOUT_PLANNER.md.
/// Tapping an exercise jumps to its existing Lift Detail screen; logging
/// still only happens from there (this screen never logs anything itself).
class PatternPoolScreen extends StatefulWidget {
  final MovementPattern pattern;
  const PatternPoolScreen({super.key, required this.pattern});

  @override
  State<PatternPoolScreen> createState() => _PatternPoolScreenState();
}

class _PatternPoolScreenState extends State<PatternPoolScreen> {
  bool _loading = true;
  List<Exercise> _pool = [];
  Map<int, int> _readinessBars = {};

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
    final muscleReadiness = await ReadinessEngine.computeMuscleReadiness();
    final pool = exercises.where((e) => e.patterns.contains(widget.pattern)).toList();
    final bars = {
      for (final e in pool)
        if (e.id != null)
          e.id!: ReadinessEngine.toBars(
              ReadinessEngine.readinessForExercise(e, muscleReadiness)),
    };
    pool.sort((a, b) => (bars[b.id] ?? 0).compareTo(bars[a.id] ?? 0));

    if (!mounted) return;
    setState(() {
      _pool = pool;
      _readinessBars = bars;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: Text(widget.pattern.label)),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.accent))
          : _pool.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.edge),
                    child: Text(
                      'No lifts tagged with this pattern yet — add the tag from a '
                      'lift\'s edit sheet.',
                      style: AppText.smallText,
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.all(AppSpacing.edge),
                  children: _pool.map((e) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.cardGap),
                      child: AppCard(
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => LiftDetailScreen(exercise: e)),
                        ),
                        child: Row(
                          children: [
                            Expanded(child: Text(e.name, style: AppText.bodyText)),
                            ReadinessBars(readiness: _readinessBars[e.id] ?? 0),
                            const SizedBox(width: AppSpacing.micro),
                            const Icon(Icons.chevron_right, color: AppColors.textSecondary),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
    );
  }
}
