import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../theme/app_theme.dart';

/// One metric's per-day values, already normalized to a metric-specific
/// scale for the calendar's size encoding — see [ComparisonMonthCalendar].
class CalendarSeries {
  /// date string (`yyyy-MM-dd`) -> raw value, before normalization.
  final Map<String, double> valuesByDate;
  final Color color;

  /// True for the one non-ordinal categorical option ("Soreness (by body
  /// part)") — its dot is always drawn at a single fixed "tracked" size,
  /// never size-encoded, same simplification the scatter plot uses.
  final bool isCategorical;

  const CalendarSeries({
    required this.valuesByDate,
    required this.color,
    this.isCategorical = false,
  });
}

/// The bottom plot on the Metric Comparison screen — a month grid (same
/// navigation structure as `CycleDetailScreen._buildCalendar`) where each
/// day cell can show up to two centered, overlapping dots, one per selected
/// metric. A numeric metric's dot is sized by its value normalized 0-1
/// *within the currently visible month* (0 = that metric's smallest value
/// this month, 1 = its largest) so the scale stays meaningful regardless of
/// which time frame is picked upstream; a categorical metric's dot is
/// always the same fixed "tracked" size. Equal-size ties: series A is drawn
/// first/underneath, a few px larger than series B's dot on top, so a
/// visible ring peeks out around it rather than the two exactly overlapping.
class ComparisonMonthCalendar extends StatefulWidget {
  final CalendarSeries seriesA;
  final CalendarSeries seriesB;

  const ComparisonMonthCalendar({
    super.key,
    required this.seriesA,
    required this.seriesB,
  });

  @override
  State<ComparisonMonthCalendar> createState() =>
      _ComparisonMonthCalendarState();
}

class _ComparisonMonthCalendarState extends State<ComparisonMonthCalendar> {
  DateTime _focusedMonth = DateTime(DateTime.now().year, DateTime.now().month);

  static const _weekdayLabels = ['S', 'M', 'T', 'W', 'T', 'F', 'S'];
  static const _minDotSize = 8.0;
  static const _maxDotSize = 22.0;
  static const _categoricalDotSize = 12.0;
  static const _tieBreakBonus = 5.0;

  String _fmt(DateTime d) => d.toIso8601String().substring(0, 10);

  /// This series' values restricted to the visible month, normalized 0-1
  /// against that subset's own min/max (not all-time) — so "1" always means
  /// "the biggest this metric got this month," not some distant history.
  Map<String, double> _normalizedForMonth(CalendarSeries series) {
    final inMonth = series.valuesByDate.entries.where((e) {
      final d = DateTime.parse(e.key);
      return d.year == _focusedMonth.year && d.month == _focusedMonth.month;
    }).toList();
    if (inMonth.isEmpty) return {};
    final minV = inMonth.map((e) => e.value).reduce((a, b) => a < b ? a : b);
    final maxV = inMonth.map((e) => e.value).reduce((a, b) => a > b ? a : b);
    final range = (maxV - minV).abs() < 1e-9 ? 1.0 : (maxV - minV);
    return {
      for (final e in inMonth)
        e.key: ((e.value - minV) / range).clamp(0.0, 1.0),
    };
  }

  double _dotSize(CalendarSeries series, double normalized) {
    if (series.isCategorical) return _categoricalDotSize;
    return _minDotSize + (_maxDotSize - _minDotSize) * normalized;
  }

  @override
  Widget build(BuildContext context) {
    final normA = _normalizedForMonth(widget.seriesA);
    final normB = _normalizedForMonth(widget.seriesB);

    final firstOfMonth = DateTime(_focusedMonth.year, _focusedMonth.month);
    final daysInMonth = DateTime(
      _focusedMonth.year,
      _focusedMonth.month + 1,
      0,
    ).day;
    final leadingBlanks = firstOfMonth.weekday % 7; // Sunday = 0

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            IconButton(
              icon: const Icon(
                Icons.chevron_left,
                color: AppColors.textSecondary,
              ),
              onPressed: () => setState(
                () => _focusedMonth = DateTime(
                  _focusedMonth.year,
                  _focusedMonth.month - 1,
                ),
              ),
            ),
            Text(
              DateFormat('MMMM yyyy').format(_focusedMonth),
              style: AppText.subHeader,
            ),
            IconButton(
              icon: const Icon(
                Icons.chevron_right,
                color: AppColors.textSecondary,
              ),
              onPressed: () => setState(
                () => _focusedMonth = DateTime(
                  _focusedMonth.year,
                  _focusedMonth.month + 1,
                ),
              ),
            ),
          ],
        ),
        Row(
          children: _weekdayLabels
              .map(
                (l) => Expanded(
                  child: Center(child: Text(l, style: AppText.label)),
                ),
              )
              .toList(),
        ),
        const SizedBox(height: AppSpacing.small),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          // Cells default to square (aspect ratio 1.0), which is enough
          // room for the cycle calendar's single small flow dot but not
          // this one's taller two-dot zone — narrower portrait cells then
          // overflow by a couple px on the bottom. Slightly taller-than-wide
          // cells give this content the room it actually needs regardless
          // of orientation (landscape cells were already tall enough,
          // that's why the bug only showed up in portrait).
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 7,
            childAspectRatio: 0.8,
          ),
          itemCount: leadingBlanks + daysInMonth,
          itemBuilder: (context, index) {
            if (index < leadingBlanks) return const SizedBox.shrink();
            final day = DateTime(
              _focusedMonth.year,
              _focusedMonth.month,
              index - leadingBlanks + 1,
            );
            final dateStr = _fmt(day);
            final isToday = dateStr == _fmt(DateTime.now());
            final a = normA[dateStr];
            final b = normB[dateStr];

            return Container(
              margin: const EdgeInsets.all(1),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    '${day.day}',
                    style: AppText.smallText.copyWith(
                      color: isToday ? AppColors.accent : AppColors.textPrimary,
                      fontWeight: isToday ? FontWeight.w700 : FontWeight.w400,
                    ),
                  ),
                  const SizedBox(height: 2),
                  SizedBox(
                    height: _maxDotSize + _tieBreakBonus,
                    child: _buildDots(a, b),
                  ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildDots(double? a, double? b) {
    if (a == null && b == null) return const SizedBox.shrink();
    final sizeA = a == null ? null : _dotSize(widget.seriesA, a);
    final sizeB = b == null ? null : _dotSize(widget.seriesB, b);

    if (sizeA == null) return _dot(sizeB!, widget.seriesB.color);
    if (sizeB == null) return _dot(sizeA, widget.seriesA.color);

    // Whichever dot is naturally smaller goes on top (otherwise the bigger
    // one — often the fixed-size categorical dot — can fully swallow a
    // smaller one with no ring visible at all, which is what made some
    // demo-data days look "just one color" here). The back (bigger) dot is
    // bumped up to at least front+_tieBreakBonus so a ring is guaranteed
    // even when the two sizes started out nearly equal; a genuinely bigger
    // back dot keeps its own natural size, no extra inflation needed. On an
    // exact tie there's no real "bigger" one to prefer, so A stays the back
    // dot as an arbitrary but consistent default.
    final aIsBack = sizeA >= sizeB;
    final frontSize = aIsBack ? sizeB : sizeA;
    final frontColor = aIsBack ? widget.seriesB.color : widget.seriesA.color;
    final naturalBackSize = aIsBack ? sizeA : sizeB;
    final backColor = aIsBack ? widget.seriesA.color : widget.seriesB.color;
    final backSize = naturalBackSize < frontSize + _tieBreakBonus
        ? frontSize + _tieBreakBonus
        : naturalBackSize;

    return Stack(
      alignment: Alignment.center,
      children: [_dot(backSize, backColor), _dot(frontSize, frontColor)],
    );
  }

  Widget _dot(double size, Color color) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}
