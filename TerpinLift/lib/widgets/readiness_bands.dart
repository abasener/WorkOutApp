import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Discrete color/label bands for a 0-1 readiness score — the Primed for
/// Growth heatmap primarily. A plain continuous intensity→green lerp
/// compressed real differences (a middling ~0.5 score still read as "pretty
/// green" — green is perceptually the loudest RGB channel, and a 2-stop
/// gradient has no visual anchor for "half done"), so this steps through a
/// small number of hand-picked colors instead. Thresholds are deliberately
/// round, chosen for visual separation, not derived from anything — this is
/// a display calibration, not a new score.
abstract class ReadinessBands {
  static const _needsRestMax = 0.3;
  static const _recoveringMax = 0.55;
  static const _readyMax = 0.8;

  static Color colorFor(double readiness) {
    if (readiness < _needsRestMax) return AppColors.readinessNeedsRest;
    if (readiness < _recoveringMax) return AppColors.readinessRecovering;
    if (readiness < _readyMax) return AppColors.readinessReady;
    return AppColors.readinessWellRested;
  }

  static const bandBounds = [0.0, _needsRestMax, _recoveringMax, _readyMax, 1.0];

  static String labelFor(double readiness) {
    if (readiness < _needsRestMax) return 'Needs rest';
    if (readiness < _recoveringMax) return 'Recovering';
    if (readiness < _readyMax) return 'Ready';
    return 'Well rested';
  }
}
