import 'dart:async';

import 'package:flutter/material.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../data/models/exercise.dart';
import '../../data/models/hiit_session.dart';
import '../../data/models/hiit_slot.dart';
import '../../services/app_services.dart';
import '../../services/cardio_units.dart';
import '../../services/units.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_card.dart';
import '../../widgets/countdown_ring.dart';
import 'hiit_report_screen.dart';
import 'hiit_setup_screen.dart';

/// Runs an already-started HIIT routine, one slot at a time — a work phase
/// (the exercise itself) optionally followed by a rest/transition phase,
/// strictly in the order set up. Every bit of live state
/// (`HiitSession.currentSequenceIndex`/`currentPhase`/`phaseStartedAt`/
/// `phaseRemainingSeconds`/`currentRepsRemaining`/`paused`) is persisted as
/// it changes, so leaving this screen (Pause, or just navigating away) and
/// coming back later through Home's HIIT card resumes exactly where it left
/// off. See designFiles/12_SCREEN_hiit.md.
class HiitActiveScreen extends StatefulWidget {
  final int sessionId;
  const HiitActiveScreen({super.key, required this.sessionId});

  @override
  State<HiitActiveScreen> createState() => _HiitActiveScreenState();
}

class _HiitActiveScreenState extends State<HiitActiveScreen>
    with WidgetsBindingObserver {
  bool _loading = true;
  HiitSession? _session;
  List<HiitSlot> _slots = [];
  Map<int, Exercise> _exercisesById = {};
  Timer? _ticker;
  bool _advancing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WakelockPlus.enable();
    _load();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _onTick());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    WakelockPlus.disable();
    _ticker?.cancel();
    super.dispose();
  }

  // Backgrounding the app (Home button, task switcher, the app getting
  // killed) pauses the workout rather than leaving timers silently running
  // against a screen nobody's looking at — matches the same intent as the
  // Pause button, just triggered by leaving instead of tapping it.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      final s = _session;
      if (s != null && !s.paused) _togglePause();
    }
  }

  Future<void> _load() async {
    final session = await AppServices.hiit.getSession(widget.sessionId);
    final slots = await AppServices.hiit.getSlotsForSession(widget.sessionId);
    final exercises = await AppServices.exercises.getAll();
    if (!mounted) return;
    setState(() {
      _session = session;
      _slots = slots;
      _exercisesById = {
        for (final e in exercises)
          if (e.id != null) e.id!: e,
      };
      _loading = false;
    });
  }

  HiitSlot get _currentSlot => _slots[_session!.currentSequenceIndex];
  Exercise? get _currentExercise => _exercisesById[_currentSlot.exerciseId];

  bool _isGroupBoundary(int i) =>
      i < _slots.length - 1 && _slots[i].groupIndex != _slots[i + 1].groupIndex;

  double _secondsSincePhaseStart() {
    final s = _session!;
    if (s.paused || s.phaseStartedAt == null) return 0;
    return DateTime.now()
            .difference(DateTime.parse(s.phaseStartedAt!))
            .inMilliseconds /
        1000.0;
  }

  double _liveRemaining(double total) {
    final baseline = _session!.phaseRemainingSeconds ?? total;
    return (baseline - _secondsSincePhaseStart()).clamp(0, total);
  }

  double _liveElapsed() {
    final baseline = _session!.phaseRemainingSeconds ?? 0;
    return baseline + _secondsSincePhaseStart();
  }

  void _onTick() {
    if (!mounted || _session == null || _loading) return;
    setState(() {});
    final s = _session!;
    if (s.paused || !s.automatic || _advancing) return;
    final slot = _currentSlot;
    double? total;
    if (s.currentPhase == HiitPhase.rest) {
      total = (slot.restAfterSeconds ?? 0).toDouble();
    } else if (slot.targetType == HiitTargetType.amrap ||
        slot.targetType == HiitTargetType.time) {
      total = slot.targetValue;
    }
    if (total != null && _liveRemaining(total) <= 0) _advance();
  }

  Future<void> _recordActuals(HiitSlot slot) async {
    final s = _session!;
    HiitSlot updated;
    switch (slot.targetType) {
      case HiitTargetType.reps:
        updated = slot.copyWith(
          actualReps: slot.targetValue?.round(),
          actualWeight: slot.weight,
        );
      case HiitTargetType.amrap:
        updated = slot.copyWith(
          actualTimeSeconds: slot.targetValue?.round(),
          actualWeight: slot.weight,
          actualReps: s.automatic ? null : (s.currentRepsRemaining ?? 0),
        );
      case HiitTargetType.time:
        updated = slot.copyWith(
          actualTimeSeconds: slot.targetValue?.round(),
          actualLoad: slot.weight,
        );
      case HiitTargetType.distance:
        updated = slot.copyWith(
          actualDistance: slot.targetValue,
          actualTimeSeconds: _liveElapsed().round(),
          actualLoad: slot.weight,
        );
    }
    await AppServices.hiit.updateSlot(updated);
    final idx = _slots.indexWhere((sl) => sl.id == slot.id);
    if (idx != -1) _slots[idx] = updated;
  }

  Future<void> _advance() async {
    if (_advancing) return;
    _advancing = true;
    final s = _session!;
    final slot = _currentSlot;

    if (s.currentPhase == HiitPhase.work) {
      await _recordActuals(slot);
      final restSecs = slot.restAfterSeconds;
      if (restSecs != null && restSecs > 0) {
        final updated = s.copyWith(
          currentPhase: HiitPhase.rest,
          phaseStartedAt: DateTime.now().toIso8601String(),
          phaseRemainingSeconds: restSecs.toDouble(),
          clearCurrentRepsRemaining: true,
        );
        await AppServices.hiit.updateSession(updated);
        if (mounted) setState(() => _session = updated);
        _advancing = false;
        return;
      }
    }

    final nextIndex = s.currentSequenceIndex + 1;
    if (nextIndex >= _slots.length) {
      await _finish();
      _advancing = false;
      return;
    }
    final nextSlot = _slots[nextIndex];
    final isReps = nextSlot.targetType == HiitTargetType.reps;
    final isAmrap = nextSlot.targetType == HiitTargetType.amrap;
    final isDistance = nextSlot.targetType == HiitTargetType.distance;
    final updated = s.copyWith(
      currentSequenceIndex: nextIndex,
      currentPhase: HiitPhase.work,
      phaseStartedAt: isReps ? null : DateTime.now().toIso8601String(),
      clearPhaseStartedAt: isReps,
      phaseRemainingSeconds: isReps
          ? null
          : (isDistance ? 0 : nextSlot.targetValue),
      clearPhaseRemainingSeconds: isReps,
      currentRepsRemaining: isReps
          ? nextSlot.targetValue?.round()
          : (isAmrap ? 0 : null),
      clearCurrentRepsRemaining: !(isReps || isAmrap),
    );
    await AppServices.hiit.updateSession(updated);
    if (mounted) setState(() => _session = updated);
    _advancing = false;
  }

  Future<void> _finish() async {
    final s = _session!;
    final updated = s.copyWith(
      status: HiitSessionStatus.completed,
      completedAt: DateTime.now().toIso8601String(),
    );
    await AppServices.hiit.updateSession(updated);
    AppServices.signalReload();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => HiitReportScreen(sessionId: s.id!)),
    );
  }

  Future<void> _tapRing() async {
    final s = _session!;
    if (s.paused) return;
    final slot = _currentSlot;
    if (s.currentPhase == HiitPhase.rest) {
      if (_liveRemaining((slot.restAfterSeconds ?? 0).toDouble()) <= 0) {
        await _advance();
      }
      return;
    }
    switch (slot.targetType) {
      case HiitTargetType.reps:
        final remaining = s.currentRepsRemaining ?? 0;
        if (remaining <= 0) {
          await _advance();
          return;
        }
        final next = remaining - 1;
        final updated = s.copyWith(currentRepsRemaining: next);
        await AppServices.hiit.updateSession(updated);
        if (mounted) setState(() => _session = updated);
        if (next <= 0 && s.automatic) await _advance();
      case HiitTargetType.amrap:
      case HiitTargetType.time:
        if (_liveRemaining(slot.targetValue ?? 0) <= 0) await _advance();
      case HiitTargetType.distance:
        await _advance();
    }
  }

  Future<void> _incrementAmrapReps() async {
    final s = _session!;
    if (s.paused || s.automatic) return;
    final updated = s.copyWith(
      currentRepsRemaining: (s.currentRepsRemaining ?? 0) + 1,
    );
    await AppServices.hiit.updateSession(updated);
    if (mounted) setState(() => _session = updated);
  }

  Future<void> _togglePause() async {
    final s = _session!;
    HiitSession updated;
    if (s.paused) {
      updated = s.copyWith(
        paused: false,
        phaseStartedAt: DateTime.now().toIso8601String(),
      );
    } else {
      final slot = _currentSlot;
      final remainingSnapshot = s.currentPhase == HiitPhase.rest
          ? _liveRemaining((slot.restAfterSeconds ?? 0).toDouble())
          : (slot.targetType == HiitTargetType.reps
                ? null
                : (slot.targetType == HiitTargetType.distance
                      ? _liveElapsed()
                      : _liveRemaining(slot.targetValue ?? 0)));
      updated = s.copyWith(
        paused: true,
        clearPhaseStartedAt: true,
        phaseRemainingSeconds: remainingSnapshot,
        clearPhaseRemainingSeconds: remainingSnapshot == null,
      );
    }
    await AppServices.hiit.updateSession(updated);
    if (mounted) setState(() => _session = updated);
  }

  Future<void> _abort() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceRaised,
        title: Text('Abort this HIIT workout?', style: AppText.subHeader),
        content: Text(
          "This ends the workout now, nothing gets logged. You'll go back to setup with "
          "the same routine so you can adjust it.",
          style: AppText.bodyText,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: AppText.bodyText),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Abort',
              style: TextStyle(color: AppColors.accent),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final seedSlots = List<HiitSlot>.from(_slots);
    final seedAutomatic = _session!.automatic;
    await AppServices.hiit.deleteSession(_session!.id!);
    AppServices.signalReload();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) =>
            HiitSetupScreen(seedSlots: seedSlots, seedAutomatic: seedAutomatic),
      ),
      (route) => route.isFirst,
    );
  }

  String _formatSeconds(double seconds) {
    final s = seconds.round().clamp(0, 1 << 30);
    final m = s ~/ 60;
    final ss = (s % 60).toString().padLeft(2, '0');
    return '$m:$ss';
  }

  String _slotDetails(HiitSlot slot, Exercise? exercise) {
    final parts = <String>[];
    if (slot.weight != null) {
      final isCardio = slot.exerciseKind == HiitExerciseKind.cardio;
      parts.add(
        isCardio
            ? 'resistance ${slot.weight!.toStringAsFixed(0)}'
            : Units.format(slot.weight!),
      );
    }
    switch (slot.targetType) {
      case HiitTargetType.reps:
        parts.add('${slot.targetValue?.round() ?? 0} reps');
      case HiitTargetType.amrap:
        parts.add('AMRAP');
      case HiitTargetType.time:
        parts.add('${((slot.targetValue ?? 0) / 60).toStringAsFixed(1)} min');
      case HiitTargetType.distance:
        final unit = exercise?.cardioUnit ?? CardioUnits.defaultUnit;
        parts.add(CardioUnits.formatDistance(slot.targetValue ?? 0, unit));
    }
    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    if (_loading || _session == null) {
      return const Scaffold(
        backgroundColor: AppColors.background,
        body: Center(child: CircularProgressIndicator(color: AppColors.accent)),
      );
    }

    final s = _session!;
    final slot = _currentSlot;
    final exercise = _currentExercise;
    final isRest = s.currentPhase == HiitPhase.rest;

    String centerText;
    String? centerSubtext;
    double progress;
    if (isRest) {
      final total = (slot.restAfterSeconds ?? 0).toDouble();
      final remaining = _liveRemaining(total);
      centerText = remaining <= 0 ? 'Next' : _formatSeconds(remaining);
      progress = total <= 0 ? 1 : 1 - (remaining / total);
    } else {
      switch (slot.targetType) {
        case HiitTargetType.reps:
          final remaining = s.currentRepsRemaining ?? 0;
          final total = (slot.targetValue ?? 1).clamp(1, double.infinity);
          centerText = remaining <= 0 ? 'Next' : '$remaining left';
          progress = 1 - (remaining / total);
        case HiitTargetType.amrap:
          final total = slot.targetValue ?? 0;
          final remaining = _liveRemaining(total);
          centerText = remaining <= 0 ? 'Next' : _formatSeconds(remaining);
          centerSubtext = 'AMRAP';
          progress = total <= 0 ? 1 : 1 - (remaining / total);
        case HiitTargetType.time:
          final total = slot.targetValue ?? 0;
          final remaining = _liveRemaining(total);
          centerText = remaining <= 0 ? 'Next' : _formatSeconds(remaining);
          progress = total <= 0 ? 1 : 1 - (remaining / total);
        case HiitTargetType.distance:
          centerText = _formatSeconds(_liveElapsed());
          centerSubtext = 'Tap when done';
          progress = 0;
      }
    }

    final nextSlot = s.currentSequenceIndex + 1 < _slots.length
        ? _slots[s.currentSequenceIndex + 1]
        : null;
    final nextExercise = nextSlot == null
        ? null
        : _exercisesById[nextSlot.exerciseId];

    return PopScope(
      // First back-press (system gesture/button, since the AppBar's own
      // back arrow is hidden unless already paused) pauses instead of
      // leaving — same intent as backgrounding the app. A second press,
      // now that it's paused, actually leaves.
      canPop: s.paused,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (!s.paused) _togglePause();
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          automaticallyImplyLeading: false,
          leading: s.paused
              ? IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () => Navigator.of(context).maybePop(),
                )
              : null,
        ),
        body: Padding(
          padding: const EdgeInsets.all(AppSpacing.edge),
          child: Column(
            children: [
              SizedBox(
                height: 8,
                child: Row(
                  children: [
                    for (var i = 0; i < _slots.length; i++)
                      Expanded(
                        child: Container(
                          height: 8,
                          margin: EdgeInsets.only(
                            right: i == _slots.length - 1
                                ? 0
                                : (_isGroupBoundary(i) ? 6 : 2),
                          ),
                          decoration: BoxDecoration(
                            color: i < s.currentSequenceIndex
                                ? AppColors.accent
                                : i == s.currentSequenceIndex
                                ? AppColors.accent.withValues(alpha: 0.5)
                                : AppColors.border,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.large),
              Text(
                isRest ? 'Transition' : (exercise?.name ?? 'HIIT'),
                style: AppText.bigNumber.copyWith(fontSize: 32),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.small),
              Text(
                isRest
                    ? 'Next: ${nextExercise?.name ?? '—'}'
                    : _slotDetails(slot, exercise),
                style: AppText.bodyText.copyWith(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                ),
                textAlign: TextAlign.center,
              ),
              const Spacer(),
              CountdownRing(
                progress: progress,
                centerText: centerText,
                centerSubtext: centerSubtext,
                onTap: s.paused ? null : _tapRing,
              ),
              if (!isRest &&
                  slot.targetType == HiitTargetType.amrap &&
                  !s.automatic) ...[
                const SizedBox(height: AppSpacing.large),
                AppCard(
                  onTap: s.paused ? null : _incrementAmrapReps,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        '${s.currentRepsRemaining ?? 0} reps done',
                        style: AppText.bodyText,
                      ),
                      const SizedBox(width: AppSpacing.small),
                      const Icon(
                        Icons.add_circle_outline,
                        color: AppColors.accent,
                      ),
                    ],
                  ),
                ),
              ],
              const Spacer(),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: AppColors.accent),
                        foregroundColor: AppColors.accent,
                        minimumSize: const Size(double.infinity, 52),
                      ),
                      onPressed: _abort,
                      child: const Text('Abort'),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.standard),
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: AppColors.border),
                        foregroundColor: AppColors.textPrimary,
                        minimumSize: const Size(double.infinity, 52),
                      ),
                      onPressed: _togglePause,
                      child: Text(s.paused ? 'Resume' : 'Pause'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
