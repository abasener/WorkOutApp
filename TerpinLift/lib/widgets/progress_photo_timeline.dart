import 'package:flutter/material.dart';

import '../data/models/progress_photo.dart';
import '../theme/app_theme.dart';

/// A simple date-scaled timeline of dots, one per day that has at least one
/// progress photo — dot size grows with that day's photo count (multiple
/// angles/poses). No y-axis (there's no "value" to plot, just presence over
/// time), unlike the lift/metric trend charts. Tap anywhere to open the full
/// gallery.
class ProgressPhotoTimeline extends StatelessWidget {
  final List<ProgressPhoto> photos;
  const ProgressPhotoTimeline({super.key, required this.photos});

  static double _radius(int count) => (6.0 + (count - 1) * 2.0).clamp(6.0, 14.0);

  @override
  Widget build(BuildContext context) {
    if (photos.isEmpty) {
      return SizedBox(
        height: 56,
        child: Center(child: Text('No photos yet', style: AppText.smallText)),
      );
    }

    final countByDate = <String, int>{};
    for (final p in photos) {
      countByDate[p.date] = (countByDate[p.date] ?? 0) + 1;
    }
    final dates = countByDate.keys.map(DateTime.parse).toList()..sort();
    final first = dates.first;
    final totalDays = dates.last.difference(first).inDays.clamp(1, 1 << 30).toDouble();

    return SizedBox(
      height: 56,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          double xOf(DateTime d) => (d.difference(first).inDays / totalDays) * width;

          return Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                left: 0,
                right: 0,
                top: 27,
                child: Container(height: 2, color: AppColors.border),
              ),
              for (final entry in countByDate.entries)
                Builder(builder: (context) {
                  final r = _radius(entry.value);
                  final x = xOf(DateTime.parse(entry.key)).clamp(r, width - r);
                  return Positioned(
                    left: x - r,
                    top: 28 - r,
                    child: Container(
                      width: r * 2,
                      height: r * 2,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppColors.accent,
                      ),
                    ),
                  );
                }),
            ],
          );
        },
      ),
    );
  }
}
