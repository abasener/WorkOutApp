import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// One row in a [MetricHistorySheet] — deliberately not tied to any
/// particular metric's model type, since Steps/Sleep/Weight/Soreness/
/// Workout Duration are all different underlying shapes; the sheet only
/// needs a date, a value (or tags, for soreness), and an optional edit hook.
class MetricHistoryRow {
  final String date;
  final String? valueText;
  final List<String>? tags;

  /// `null` for a metric with nothing to edit here (Workout Duration is
  /// derived, not logged) — the row shows with no pencil icon.
  final VoidCallback? onEdit;

  const MetricHistoryRow({
    required this.date,
    this.valueText,
    this.tags,
    this.onEdit,
  });
}

/// A single-metric "notebook" popup — every logged value, newest first,
/// exact numbers/tags visible at a glance. Deliberately just a popup, not a
/// jump to the Days tab: the Days tab mixes every metric together by date,
/// which is the right view for "what happened today" but the wrong one for
/// "show me every Steps reading I've ever logged." Read-only past the
/// per-row edit hook — no delete here, unlike `CustomMetricHistorySheet`,
/// since these rows lean on each metric's own existing edit flow rather than
/// introducing a new deletion path for real logged history.
class MetricHistorySheet extends StatelessWidget {
  final String title;
  final List<MetricHistoryRow> rows;
  const MetricHistorySheet({super.key, required this.title, required this.rows});

  @override
  Widget build(BuildContext context) {
    final sorted = [...rows]..sort((a, b) => b.date.compareTo(a.date));

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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('$title Log', style: AppText.subHeader),
            const SizedBox(height: AppSpacing.large),
            Flexible(
              child: sorted.isEmpty
                  ? Text('No entries logged yet.', style: AppText.smallText)
                  : ListView.separated(
                      shrinkWrap: true,
                      itemCount: sorted.length,
                      separatorBuilder: (context, i) => const SizedBox(height: AppSpacing.small),
                      itemBuilder: (context, i) {
                        final row = sorted[i];
                        return Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.standard, vertical: AppSpacing.small),
                          decoration: BoxDecoration(
                            border: Border.all(color: AppColors.border),
                            borderRadius: BorderRadius.circular(AppRadius.button),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Wrap(
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  spacing: AppSpacing.small,
                                  runSpacing: AppSpacing.micro,
                                  children: [
                                    Text(row.date, style: AppText.bodyText),
                                    if (row.valueText != null)
                                      Text(row.valueText!, style: AppText.smallText),
                                    ...?row.tags?.map((t) => _Tag(label: t)),
                                  ],
                                ),
                              ),
                              if (row.onEdit != null) ...[
                                const SizedBox(width: AppSpacing.standard),
                                GestureDetector(
                                  onTap: row.onEdit,
                                  child: const Icon(Icons.edit_outlined,
                                      size: 18, color: AppColors.textSecondary),
                                ),
                              ],
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  final String label;
  const _Tag({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: AppColors.border),
      ),
      child: Text(label, style: AppText.smallText.copyWith(fontSize: 11)),
    );
  }
}
