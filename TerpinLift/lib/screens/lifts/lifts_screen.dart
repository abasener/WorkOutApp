import 'package:flutter/material.dart';
import 'package:flutter_body_heatmap/flutter_body_heatmap.dart' show Muscle;

import '../../data/models/exercise.dart';
import '../../data/models/workout_plan.dart';
import '../../data/repositories/lift_repository.dart';
import '../../services/app_services.dart';
import '../../services/readiness_engine.dart';
import '../../services/units.dart';
import '../../services/workout_plan_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_card.dart';
import '../../widgets/readiness_bars.dart';
import '../planner/active_day_screen.dart';
import 'add_exercise_sheet.dart';
import 'edit_lift_session_form.dart';
import 'lift_detail_screen.dart';

class LiftsScreen extends StatefulWidget {
  const LiftsScreen({super.key});

  @override
  State<LiftsScreen> createState() => _LiftsScreenState();
}

enum _LiftSort { alphabetical, mostUsed, pushPull, muscleGroup, type, readiness }

extension on _LiftSort {
  String get label {
    switch (this) {
      case _LiftSort.alphabetical:
        return 'Alphabetical';
      case _LiftSort.mostUsed:
        return 'Most used';
      case _LiftSort.pushPull:
        return 'Push/Pull';
      case _LiftSort.muscleGroup:
        return 'Muscle group';
      case _LiftSort.type:
        return 'Type';
      case _LiftSort.readiness:
        return 'Readiness';
    }
  }
}

// Fixed priority orders — an exercise sorts by the earliest-listed tag it
// carries; exercises with none of the listed tags sort to the end.
const _muscleGroupOrder = [
  ExerciseCategory.legs,
  ExerciseCategory.back,
  ExerciseCategory.chest,
  ExerciseCategory.core,
  ExerciseCategory.arms,
];
const _typeOrder = [
  ExerciseType.compound,
  ExerciseType.machine,
  ExerciseType.cardio,
  ExerciseType.bodyweight,
];

class _LiftsScreenState extends State<LiftsScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabController = TabController(length: 2, vsync: this);

  List<Exercise> _exercises = [];
  List<SessionWithSets> _allSessions = [];
  Map<Muscle, double> _muscleReadiness = {};
  List<PlannedSession> _plannedSessions = [];
  Map<int, WorkoutTemplateDay> _daysById = {};
  bool _loading = true;

  final Set<Object> _activeFilters = {}; // ExerciseCategory | ExerciseType
  _LiftSort? _activeSort;
  bool _pinnedOnly = false;
  bool _searchExpanded = false;
  String _searchQuery = '';
  final _searchController = TextEditingController();

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
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final exercises = await AppServices.exercises.getAll();
    final allSessions = await AppServices.lifts.getAllSessions();
    final muscleReadiness = await ReadinessEngine.computeMuscleReadiness();
    final plannedSessions = await AppServices.workoutPlans.getAllSessions();
    final daysById = await AppServices.workoutPlans.getAllDaysById();
    if (!mounted) return;
    setState(() {
      _exercises = exercises;
      _allSessions = allSessions;
      _muscleReadiness = muscleReadiness;
      _plannedSessions = plannedSessions;
      _daysById = daysById;
      _loading = false;
    });
  }

  Future<void> _editPlannedSession(PlannedSession session) async {
    final day = _daysById[session.templateDayId];
    if (day == null) return;
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ActiveDayScreen(session: session, day: day)),
    );
  }

  List<Exercise> get _visibleExercises {
    var list = _pinnedOnly ? _exercises.where((e) => e.pinned).toList() : _exercises;
    list = _activeFilters.isEmpty
        ? list
        : list.where((e) {
            return _activeFilters.any((f) => f is ExerciseCategory
                ? e.categories.contains(f)
                : e.equipmentTags.contains(f as ExerciseType));
          }).toList();

    // Search narrows whatever's already visible after filter/pin, never
    // reaches past it — typing "bench" while a "legs" filter is on should
    // stay empty, not fall back to searching the whole library.
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      list = list.where((e) => e.name.toLowerCase().contains(q)).toList();
    }

    final sort = _activeSort;
    if (sort == null) return list;
    list = [...list];

    final sessionCounts = <int, int>{};
    for (final s in _allSessions) {
      sessionCounts[s.session.exerciseId] = (sessionCounts[s.session.exerciseId] ?? 0) + 1;
    }

    int rank(Exercise e) {
      switch (sort) {
        case _LiftSort.alphabetical:
          return 0; // name-only sort; the tie-break below does the real work
        case _LiftSort.mostUsed:
          // Most sessions first -> negate for ascending sort.
          return -(sessionCounts[e.id] ?? 0);
        case _LiftSort.pushPull:
          if (e.categories.contains(ExerciseCategory.push)) return 0;
          if (e.categories.contains(ExerciseCategory.pull)) return 1;
          return 2;
        case _LiftSort.muscleGroup:
          for (var i = 0; i < _muscleGroupOrder.length; i++) {
            if (e.categories.contains(_muscleGroupOrder[i])) return i;
          }
          return _muscleGroupOrder.length;
        case _LiftSort.type:
          for (var i = 0; i < _typeOrder.length; i++) {
            if (e.equipmentTags.contains(_typeOrder[i])) return i;
          }
          return _typeOrder.length;
        case _LiftSort.readiness:
          // Higher readiness first -> negate for ascending sort.
          return -(ReadinessEngine.readinessForExercise(e, _muscleReadiness) * 1000).round();
      }
    }

    list.sort((a, b) {
      final cmp = rank(a).compareTo(rank(b));
      return cmp != 0 ? cmp : a.name.compareTo(b.name);
    });
    return list;
  }

  Future<void> _openFilterSheet() async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _FilterSheet(
        active: _activeFilters,
        onChanged: (v) => setState(() {}),
      ),
    );
  }

  Future<void> _openSortSheet() async {
    final chosen = await showModalBottomSheet<_LiftSort?>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _SortSheet(active: _activeSort),
    );
    if (chosen == _activeSort) return;
    setState(() => _activeSort = chosen);
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
    final visible = _visibleExercises;
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.edge),
      children: [
        _searchExpanded
            ? Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      autofocus: true,
                      style: AppText.bodyText,
                      decoration: const InputDecoration(
                        hintText: 'Search lifts…',
                        isDense: true,
                      ),
                      onChanged: (v) => setState(() => _searchQuery = v),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.small),
                  IconButton(
                    tooltip: 'Close search',
                    onPressed: () => setState(() {
                      _searchExpanded = false;
                      _searchQuery = '';
                      _searchController.clear();
                    }),
                    icon: const Icon(Icons.close),
                    color: AppColors.textSecondary,
                  ),
                ],
              )
            : Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(
                            color:
                                _activeFilters.isEmpty ? AppColors.border : AppColors.accent),
                        foregroundColor:
                            _activeFilters.isEmpty ? AppColors.textPrimary : AppColors.accent,
                      ),
                      onPressed: _openFilterSheet,
                      icon: const Icon(Icons.filter_list, size: 18),
                      label: Text(_activeFilters.isEmpty
                          ? 'Filter'
                          : 'Filter (${_activeFilters.length})'),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.small),
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(
                            color: _activeSort == null ? AppColors.border : AppColors.accent),
                        foregroundColor:
                            _activeSort == null ? AppColors.textPrimary : AppColors.accent,
                      ),
                      onPressed: _openSortSheet,
                      icon: const Icon(Icons.sort, size: 18),
                      label: Text(_activeSort == null ? 'Sort' : 'Sort: ${_activeSort!.label}'),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.small),
                  IconButton(
                    tooltip: _pinnedOnly ? 'Showing pinned only' : 'Show pinned only',
                    onPressed: () => setState(() => _pinnedOnly = !_pinnedOnly),
                    icon: Icon(_pinnedOnly ? Icons.push_pin : Icons.push_pin_outlined),
                    color: _pinnedOnly ? AppColors.accent : AppColors.textSecondary,
                    style: IconButton.styleFrom(
                      side: BorderSide(color: _pinnedOnly ? AppColors.accent : AppColors.border),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.small),
                  IconButton(
                    tooltip: 'Search',
                    onPressed: () => setState(() => _searchExpanded = true),
                    icon: const Icon(Icons.search),
                    color: AppColors.textSecondary,
                    style: IconButton.styleFrom(
                      side: const BorderSide(color: AppColors.border),
                    ),
                  ),
                ],
              ),
        const SizedBox(height: AppSpacing.cardGap),
        if (visible.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.large),
            child: Center(
              child: Text('No lifts match this filter.', style: AppText.smallText),
            ),
          ),
        ...visible.map((e) {
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
                        Row(
                          children: [
                            Flexible(child: Text(e.name, style: AppText.bodyText)),
                            if (e.pinned) ...[
                              const SizedBox(width: AppSpacing.micro),
                              const Icon(Icons.push_pin, size: 12, color: AppColors.accent),
                            ],
                          ],
                        ),
                        const SizedBox(height: AppSpacing.small),
                        Wrap(
                          spacing: AppSpacing.micro,
                          runSpacing: AppSpacing.micro,
                          children: [
                            ...e.categories.map((c) => _CategoryPill(label: c.label)),
                            ...e.equipmentTags
                                .map((t) => _CategoryPill(label: t.label, muted: true)),
                          ],
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

    final exercisesById = {for (final e in _exercises) if (e.id != null) e.id!: e};

    final byDate = <String, List<SessionWithSets>>{};
    for (final s in _allSessions) {
      byDate.putIfAbsent(s.session.date, () => []).add(s);
    }
    final dates = byDate.keys.toList()..sort((a, b) => b.compareTo(a));

    Widget buildRow(SessionWithSets s) {
      final exercise = _exercises.firstWhere((e) => e.id == s.session.exerciseId,
          orElse: () =>
              Exercise(name: 'Unknown', categories: const [], isSeeded: false, created: ''));
      return Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.cardGap),
        child: _WorkoutRow(
          session: s,
          exerciseName: exercise.name,
          intensityFraction: ((s.avgRpe ?? 0) / 10).clamp(0.0, 1.0),
          onEdit: () => _editSession(s),
          // Tapping the lift itself always goes to that lift's own page —
          // tapping the workout it's grouped under (the header below) is
          // what opens the workout page instead.
          onTap: exercise.id == null
              ? null
              : () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => LiftDetailScreen(exercise: exercise))),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.edge),
      children: [
        for (final date in dates) ...[
          Text(date, style: AppText.subHeader),
          const SizedBox(height: AppSpacing.standard),
          () {
            final sessionsForDate = byDate[date]!;
            final plannedForDate =
                _plannedSessions.where((p) => p.date == date).toList();
            final assignment = WorkoutPlanService.assignToSessions(
                sessionsForDate, plannedForDate, _daysById, exercisesById);

            final ungrouped =
                sessionsForDate.where((s) => !assignment.containsKey(s.session.id)).toList();
            final grouped = <PlannedSession, List<SessionWithSets>>{};
            for (final s in sessionsForDate) {
              final planned = assignment[s.session.id];
              if (planned != null) grouped.putIfAbsent(planned, () => []).add(s);
            }
            final plannedWithLifts = plannedForDate.where(grouped.containsKey).toList();

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final s in ungrouped) buildRow(s),
                for (final planned in plannedWithLifts)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.cardGap),
                    child: Container(
                      padding: const EdgeInsets.all(AppSpacing.small),
                      decoration: BoxDecoration(
                        color: AppColors.accent.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(AppRadius.card),
                        border: const Border(
                          left: BorderSide(color: AppColors.accent, width: 3),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () => _editPlannedSession(planned),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: AppSpacing.micro, vertical: AppSpacing.micro),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      _daysById[planned.templateDayId]?.dayLabel ?? 'Workout',
                                      style: AppText.smallText
                                          .copyWith(fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                  const Icon(Icons.edit_outlined,
                                      size: 18, color: AppColors.textSecondary),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: AppSpacing.micro),
                          for (final s in grouped[planned]!) buildRow(s),
                        ],
                      ),
                    ),
                  ),
              ],
            );
          }(),
          const SizedBox(height: AppSpacing.standard),
        ],
        const SizedBox(height: AppSpacing.xLarge),
      ],
    );
  }
}

/// Multi-select filter: tapping any pill across the three groups counts as
/// an OR-match (any overlap shows the exercise) — grouped as muscle group,
/// then push/pull, then equipment type, per the user's own ordering.
class _FilterSheet extends StatefulWidget {
  final Set<Object> active;
  final ValueChanged<Set<Object>> onChanged;
  const _FilterSheet({required this.active, required this.onChanged});

  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  static const _muscleGroups = [
    ExerciseCategory.legs,
    ExerciseCategory.back,
    ExerciseCategory.chest,
    ExerciseCategory.core,
    ExerciseCategory.arms,
  ];
  static const _pushPull = [ExerciseCategory.push, ExerciseCategory.pull];

  void _toggle(Object tag) {
    setState(() {
      widget.active.contains(tag) ? widget.active.remove(tag) : widget.active.add(tag);
    });
    widget.onChanged(widget.active);
  }

  Widget _section(String title, List<Object> tags, String Function(Object) labelOf) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: AppText.label),
        const SizedBox(height: AppSpacing.standard),
        Wrap(
          spacing: AppSpacing.small,
          runSpacing: AppSpacing.small,
          children: tags.map((t) {
            final selected = widget.active.contains(t);
            return FilterChip(
              label: Text(labelOf(t)),
              selected: selected,
              onSelected: (_) => _toggle(t),
              backgroundColor: AppColors.surface,
              selectedColor: AppColors.accentDim,
              labelStyle: TextStyle(
                  color: selected ? AppColors.accent : AppColors.textSecondary),
              side: BorderSide(color: selected ? AppColors.accent : AppColors.border),
            );
          }).toList(),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
        decoration: const BoxDecoration(
          color: AppColors.surfaceRaised,
          borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.card)),
        ),
        padding: EdgeInsets.fromLTRB(
          AppSpacing.edge,
          AppSpacing.standard,
          AppSpacing.edge,
          AppSpacing.standard + MediaQuery.of(context).padding.bottom,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Filter', style: AppText.subHeader),
                  if (widget.active.isNotEmpty)
                    TextButton(
                      onPressed: () {
                        setState(() => widget.active.clear());
                        widget.onChanged(widget.active);
                      },
                      child: const Text('Clear', style: TextStyle(color: AppColors.accent)),
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.standard),
              _section('Muscle group', _muscleGroups, (t) => (t as ExerciseCategory).label),
              const SizedBox(height: AppSpacing.large),
              _section('Push/Pull', _pushPull, (t) => (t as ExerciseCategory).label),
              const SizedBox(height: AppSpacing.large),
              _section('Type', ExerciseType.values, (t) => (t as ExerciseType).label),
            ],
          ),
        ),
      ),
    );
  }
}

class _SortSheet extends StatelessWidget {
  final _LiftSort? active;
  const _SortSheet({required this.active});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: AppColors.surfaceRaised,
          borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.card)),
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
            Text('Sort by', style: AppText.subHeader),
            const SizedBox(height: AppSpacing.standard),
            for (final sort in _LiftSort.values)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(sort.label, style: AppText.bodyText),
                trailing: sort == active
                    ? const Icon(Icons.check, color: AppColors.accent)
                    : null,
                onTap: () => Navigator.pop(context, sort == active ? null : sort),
              ),
          ],
        ),
      ),
    );
  }
}

class _WorkoutRow extends StatelessWidget {
  final SessionWithSets session;
  final String exerciseName;
  final double intensityFraction; // 0-1, this session's average logged RPE / 10
  final VoidCallback onEdit;
  /// When set (a row inside a grouped workout section), tapping the row body
  /// opens that workout's page instead of doing nothing — the pencil icon
  /// still always edits just this one session's sets.
  final VoidCallback? onTap;

  const _WorkoutRow({
    required this.session,
    required this.exerciseName,
    required this.intensityFraction,
    required this.onEdit,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final barColor =
        Color.lerp(AppColors.border, AppColors.accent, intensityFraction) ?? AppColors.border;
    final topWeight = session.sets.isEmpty
        ? 0.0
        : session.sets.map((s) => s.weight).reduce((a, b) => a > b ? a : b);

    return AppCard(
      onTap: onTap,
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
  final bool muted;
  const _CategoryPill({required this.label, this.muted = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: muted ? Colors.transparent : AppColors.surfaceRaised,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: AppColors.border),
      ),
      child: Text(
        label,
        style: AppText.smallText.copyWith(
          fontSize: 11,
          color: muted ? AppColors.textSecondary : null,
        ),
      ),
    );
  }
}
