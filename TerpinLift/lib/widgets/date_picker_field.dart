import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../theme/app_theme.dart';

/// Compact "Today ▾" style control used on every quick-log form so entries
/// default to today but can be backdated (e.g. logging yesterday's steps, or
/// waiting until a day is over to log its step count). Capped at today —
/// can't log something that hasn't happened yet.
class DatePickerField extends StatelessWidget {
  final DateTime date;
  final ValueChanged<DateTime> onChanged;

  const DatePickerField({super.key, required this.date, required this.onChanged});

  static bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  Future<void> _pick(BuildContext context) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: date,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked != null) onChanged(picked);
  }

  @override
  Widget build(BuildContext context) {
    final isToday = _isSameDay(date, DateTime.now());
    return InkWell(
      onTap: () => _pick(context),
      borderRadius: BorderRadius.circular(AppRadius.button),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.button),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.calendar_today_outlined,
                size: 16, color: AppColors.textSecondary),
            const SizedBox(width: AppSpacing.small),
            Text(
              isToday ? 'Today' : DateFormat('MMM d, yyyy').format(date),
              style: AppText.bodyText,
            ),
          ],
        ),
      ),
    );
  }
}
