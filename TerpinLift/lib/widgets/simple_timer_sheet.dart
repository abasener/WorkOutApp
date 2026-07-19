import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../theme/app_theme.dart';

/// A plain start/pause/reset stopwatch, reachable from the same spot the
/// plate calculator lives on both `LogLiftForm` and `LogCardioForm` — so
/// there's no need to reach for a separate stopwatch app mid-set/mid-run.
/// Deliberately simple: no background survival, no notification, nothing
/// persisted — closing this sheet loses the running time, same as closing
/// any other phone's stopwatch screen. Keeps the screen awake for as long
/// as it's open (`WakelockPlus`) and can optionally beep on an interval,
/// muteable for public settings. See designFiles/11_SCREEN_cardio.md.
class SimpleTimerSheet extends StatefulWidget {
  const SimpleTimerSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const SimpleTimerSheet(),
    );
  }

  @override
  State<SimpleTimerSheet> createState() => _SimpleTimerSheetState();
}

class _SimpleTimerSheetState extends State<SimpleTimerSheet> {
  final _stopwatch = Stopwatch();
  Timer? _ticker;
  bool _beepEnabled = true;
  int _beepEveryMinutes = 5;
  int _lastBeepSecond = -1;
  final _beepMinutesController = TextEditingController(text: '5');

  @override
  void initState() {
    super.initState();
    WakelockPlus.enable();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _beepMinutesController.dispose();
    WakelockPlus.disable();
    super.dispose();
  }

  void _startOrResume() {
    _stopwatch.start();
    _ticker ??= Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final elapsed = _stopwatch.elapsed.inSeconds;
      final interval = _beepEveryMinutes * 60;
      if (_beepEnabled &&
          interval > 0 &&
          elapsed > 0 &&
          elapsed % interval == 0 &&
          elapsed != _lastBeepSecond) {
        _lastBeepSecond = elapsed;
        SystemSound.play(SystemSoundType.alert);
      }
      setState(() {});
    });
    setState(() {});
  }

  void _pause() {
    _stopwatch.stop();
    setState(() {});
  }

  void _reset() {
    _stopwatch.reset();
    _lastBeepSecond = -1;
    setState(() {});
  }

  String get _display {
    final total = _stopwatch.elapsed.inSeconds;
    final h = total ~/ 3600;
    final m = (total % 3600) ~/ 60;
    final s = total % 60;
    final mm = m.toString().padLeft(2, '0');
    final ss = s.toString().padLeft(2, '0');
    return h > 0 ? '$h:$mm:$ss' : '$mm:$ss';
  }

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
            Row(
              children: [
                Text('Timer', style: AppText.subHeader),
                const Spacer(),
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: const Icon(Icons.close, color: AppColors.textSecondary),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.large),
            Center(
              child: Text(
                _display,
                style: AppText.subHeader.copyWith(fontSize: 48, fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(height: AppSpacing.large),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.accent,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(double.infinity, 52),
                      shape:
                          RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.button)),
                    ),
                    onPressed: _stopwatch.isRunning ? _pause : _startOrResume,
                    child: Text(
                      _stopwatch.isRunning
                          ? 'Pause'
                          : (_stopwatch.elapsed == Duration.zero ? 'Start' : 'Resume'),
                    ),
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
                    onPressed: _reset,
                    child: const Text('Reset'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.large),
            Row(
              children: [
                Expanded(child: Text('Beep every', style: AppText.bodyText)),
                SizedBox(
                  width: 56,
                  child: TextFormField(
                    controller: _beepMinutesController,
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    style: AppText.bodyText,
                    onChanged: (v) => _beepEveryMinutes = int.tryParse(v) ?? _beepEveryMinutes,
                  ),
                ),
                const SizedBox(width: AppSpacing.small),
                Text('min', style: AppText.smallText),
                const Spacer(),
                Switch(
                  value: _beepEnabled,
                  activeThumbColor: AppColors.accent,
                  onChanged: (v) => setState(() => _beepEnabled = v),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
