import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// One sheet's row in the shared import review bottom sheet — a thin,
/// kind-agnostic view built by the caller from either
/// `ParsedHiitRoutine`/`ParsedWorkoutTemplate` (`plan_export_service.dart`)
/// so this widget doesn't need to know which kind it's reviewing.
///
/// Whether a sheet becomes an Add or a Replace isn't a user choice — it's
/// just a fact about whether something by that name already exists. The
/// only real choice here is whether to apply that (the default) or skip
/// this sheet entirely. [skip] is mutated in place as the user toggles it,
/// then read back by the caller after the sheet returns `true`.
class ImportReviewRow {
  final String name;
  final bool alreadyExists;
  final List<String> unmatchedNames;
  bool skip = false;

  ImportReviewRow({
    required this.name,
    required this.alreadyExists,
    required this.unmatchedNames,
  });

  String get action => alreadyExists ? 'Replace' : 'Add';
}

/// Shared "here's what will change" confirmation step for both HIIT-routine
/// and Workout-Plan-template import (designFiles/10_WORKOUT_PLANNER.md /
/// 12_SCREEN_hiit.md) — nothing commits to the database until this sheet's
/// Confirm is pressed. Returns `true` (each [rows] entry's `.skip` reflects
/// the final choice) or `null`/`false` if cancelled.
class PlanImportReviewSheet extends StatefulWidget {
  final List<ImportReviewRow> rows;

  const PlanImportReviewSheet({super.key, required this.rows});

  @override
  State<PlanImportReviewSheet> createState() => _PlanImportReviewSheetState();
}

class _PlanImportReviewSheetState extends State<PlanImportReviewSheet> {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        decoration: const BoxDecoration(
          color: AppColors.surfaceRaised,
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppRadius.card),
          ),
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
            Text('Review import', style: AppText.subHeader),
            const SizedBox(height: AppSpacing.small),
            Text(
              widget.rows.isEmpty
                  ? "Nothing recognizable in that file — check it's the "
                        'right export.'
                  : 'Confirm below to apply these changes.',
              style: AppText.smallText,
            ),
            const SizedBox(height: AppSpacing.standard),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: widget.rows.length,
                separatorBuilder: (_, _) =>
                    const SizedBox(height: AppSpacing.standard),
                itemBuilder: (context, i) => _rowCard(widget.rows[i]),
              ),
            ),
            const SizedBox(height: AppSpacing.large),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: AppColors.border),
                      foregroundColor: AppColors.textPrimary,
                      minimumSize: const Size(double.infinity, 48),
                    ),
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: AppSpacing.standard),
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.accent,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(double.infinity, 48),
                    ),
                    onPressed: widget.rows.isEmpty
                        ? null
                        : () => Navigator.pop(context, true),
                    child: const Text('Confirm'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _rowCard(ImportReviewRow row) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.cardPad),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(row.name, style: AppText.bodyText),
          const SizedBox(height: AppSpacing.small),
          Row(
            children: [
              ChoiceChip(
                label: Text(row.action),
                selected: !row.skip,
                showCheckmark: false,
                onSelected: (_) => setState(() => row.skip = false),
              ),
              const SizedBox(width: AppSpacing.small),
              ChoiceChip(
                label: const Text('Skip'),
                selected: row.skip,
                showCheckmark: false,
                onSelected: (_) => setState(() => row.skip = true),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.micro),
          Text(
            row.skip
                ? "Skipped: \"${row.name}\" won't be touched."
                : (row.alreadyExists
                      ? 'Replace: overwrites the existing "${row.name}".'
                      : 'Add: saved as new.'),
            style: AppText.smallText,
          ),
          if (row.unmatchedNames.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.micro),
            Text(
              "Skipped, didn't match anything: "
              '${row.unmatchedNames.join(', ')}',
              style: AppText.smallText.copyWith(
                fontStyle: FontStyle.italic,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
