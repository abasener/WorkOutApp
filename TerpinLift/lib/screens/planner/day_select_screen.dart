import 'package:flutter/material.dart';

import '../../data/models/exercise.dart';
import '../../data/models/workout_plan.dart';
import '../../services/app_services.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_card.dart';
import 'active_day_screen.dart';

/// Day-first entry point for the Workout Planner (designFiles/
/// 10_WORKOUT_PLANNER.md) — lists the active template's days, most-overdue
/// first. Selecting a day starts a session and opens `ActiveDayScreen`.
/// Multi-template switching is phase 3 (Settings); this always shows the
/// one `is_default` template for now.
class DaySelectScreen extends StatefulWidget {
  const DaySelectScreen({super.key});

  @override
  State<DaySelectScreen> createState() => _DaySelectScreenState();
}

class _DaySelectScreenState extends State<DaySelectScreen> {
  bool _loading = true;
  List<WorkoutTemplateDay> _days = [];
  Map<int, PlannedSession> _latestByDay = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final template = await AppServices.workoutPlans.getDefaultTemplate();
    if (template?.id == null) {
      if (!mounted) return;
      setState(() => _loading = false);
      return;
    }
    final days = await AppServices.workoutPlans.getDaysForTemplate(template!.id!);
    final latest = await AppServices.workoutPlans.latestSessionPerDay();
    days.sort((a, b) {
      final da = latest[a.id]?.date;
      final db = latest[b.id]?.date;
      if (da == null && db == null) return a.dayOrder.compareTo(b.dayOrder);
      if (da == null) return -1;
      if (db == null) return 1;
      return db.compareTo(da); // more recent date sorts later -> older first
    });
    if (!mounted) return;
    setState(() {
      _days = days;
      _latestByDay = latest;
      _loading = false;
    });
  }

  String _recencyLabel(WorkoutTemplateDay day) {
    final last = _latestByDay[day.id];
    if (last == null) return 'Never done';
    final days = DateTime.now().difference(DateTime.parse(last.date)).inDays;
    if (days == 0) return 'Done today';
    return '$days ${days == 1 ? 'day' : 'days'} ago';
  }

  Future<void> _selectDay(WorkoutTemplateDay day) async {
    final session = await AppServices.workoutPlans.startSession(day.id!);
    AppServices.signalReload();
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => ActiveDayScreen(session: session, day: day)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Plan a Session')),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.accent))
          : _days.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.edge),
                    child: Text('No plan loaded yet.', style: AppText.smallText),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.all(AppSpacing.edge),
                  children: _days.map((day) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.cardGap),
                      child: AppCard(
                        onTap: () => _selectDay(day),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(day.dayLabel, style: AppText.bodyText),
                                  const SizedBox(height: AppSpacing.micro),
                                  Text(
                                    day.patterns.map((p) => p.label).join(', '),
                                    style: AppText.smallText,
                                  ),
                                  const SizedBox(height: AppSpacing.micro),
                                  Text(_recencyLabel(day), style: AppText.smallText),
                                ],
                              ),
                            ),
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
