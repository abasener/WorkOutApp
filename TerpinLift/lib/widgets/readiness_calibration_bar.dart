import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'readiness_bands.dart';

/// TEMPORARY — a legend strip for eyeballing the Primed for Growth heatmap's
/// color bands against the plain number, requested for on-device
/// calibration. Delete this file and its one call site on Home once the
/// bands feel right; not meant to ship long-term.
class ReadinessCalibrationBar extends StatelessWidget {
  const ReadinessCalibrationBar({super.key});

  static const _bounds = [0.0, 0.3, 0.55, 0.8, 1.0];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('DEBUG — readiness color legend (temporary)', style: AppText.label),
        const SizedBox(height: AppSpacing.small),
        SizedBox(
          height: 28,
          child: Row(
            children: [
              for (var i = 0; i < _bounds.length - 1; i++)
                Expanded(
                  flex: ((_bounds[i + 1] - _bounds[i]) * 1000).round(),
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 1),
                    color: ReadinessBands.colorFor((_bounds[i] + _bounds[i + 1]) / 2),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.micro),
        Row(
          children: [
            for (var i = 0; i < _bounds.length - 1; i++)
              Expanded(
                flex: ((_bounds[i + 1] - _bounds[i]) * 1000).round(),
                child: Text(
                  '${_bounds[i].toStringAsFixed(2)}–${_bounds[i + 1].toStringAsFixed(2)}',
                  textAlign: TextAlign.center,
                  style: AppText.smallText.copyWith(fontSize: 10),
                ),
              ),
          ],
        ),
        Row(
          children: [
            for (var i = 0; i < _bounds.length - 1; i++)
              Expanded(
                flex: ((_bounds[i + 1] - _bounds[i]) * 1000).round(),
                child: Text(
                  ReadinessBands.labelFor((_bounds[i] + _bounds[i + 1]) / 2),
                  textAlign: TextAlign.center,
                  style: AppText.smallText.copyWith(fontSize: 10, fontWeight: FontWeight.bold),
                ),
              ),
          ],
        ),
      ],
    );
  }
}
