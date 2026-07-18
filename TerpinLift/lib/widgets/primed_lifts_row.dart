import 'dart:async';

import 'package:flutter/material.dart';

import '../data/models/exercise.dart';
import '../theme/app_theme.dart';

/// Up to 4 lift suggestions that together cover the most/best-primed
/// muscles, none of which are also sore/weak/needing rest
/// (`ReadinessEngine.suggestPrimedLifts`) — a guide, not a prescription:
/// "here's what covers what's primed," never "you should do X." Shown as a
/// single continuously-scrolling line of chips right under the Primed for
/// Growth map, news-ticker style, so it never wraps to a second line no
/// matter how many/how long the lift names are.
class PrimedLiftsRow extends StatefulWidget {
  final List<Exercise> lifts;
  final ValueChanged<Exercise> onTap;

  const PrimedLiftsRow({super.key, required this.lifts, required this.onTap});

  @override
  State<PrimedLiftsRow> createState() => _PrimedLiftsRowState();
}

class _PrimedLiftsRowState extends State<PrimedLiftsRow> {
  final _scrollController = ScrollController();
  final _setKey = GlobalKey();
  Timer? _timer;
  double? _setWidth;

  static const _pixelsPerTick = 0.5;
  static const _tickInterval = Duration(milliseconds: 16);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _measureAndStart());
  }

  @override
  void didUpdateWidget(covariant PrimedLiftsRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.lifts != widget.lifts) {
      _timer?.cancel();
      _setWidth = null;
      WidgetsBinding.instance.addPostFrameCallback((_) => _measureAndStart());
    }
  }

  void _measureAndStart() {
    if (!mounted) return;
    final box = _setKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;
    _setWidth = box.size.width;
    _timer?.cancel();
    if (widget.lifts.length <= 1) return; // nothing worth scrolling
    _timer = Timer.periodic(_tickInterval, (_) {
      final width = _setWidth;
      if (width == null || !_scrollController.hasClients) return;
      var next = _scrollController.offset + _pixelsPerTick;
      if (next >= width) next -= width;
      _scrollController.jumpTo(next);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  Widget _chip(Exercise e) {
    return GestureDetector(
      onTap: () => widget.onTap(e),
      child: Container(
        margin: const EdgeInsets.only(right: AppSpacing.small),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.surfaceRaised,
          borderRadius: BorderRadius.circular(AppRadius.pill),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.fitness_center, size: 14, color: AppColors.good),
            const SizedBox(width: AppSpacing.micro),
            Text(e.name, style: AppText.smallText),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.lifts.isEmpty) {
      return Text(
        'Nothing particularly primed right now.',
        style: AppText.smallText,
      );
    }
    // The chip set is duplicated so the loop reads as continuous — once the
    // first copy has scrolled fully past, the second copy is sitting in
    // exactly its place, and the tick timer wraps the offset back by one
    // set-width (measured from the first copy) rather than jumping to 0.
    return ClipRect(
      child: SizedBox(
        height: 36,
        child: SingleChildScrollView(
          controller: _scrollController,
          scrollDirection: Axis.horizontal,
          physics: const NeverScrollableScrollPhysics(),
          child: Row(
            children: [
              Row(key: _setKey, children: widget.lifts.map(_chip).toList()),
              Row(children: widget.lifts.map(_chip).toList()),
            ],
          ),
        ),
      ),
    );
  }
}
