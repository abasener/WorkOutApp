import 'package:flutter/material.dart';

import '../../data/models/custom_metric.dart';
import '../../data/models/custom_metric_entry.dart';
import '../../services/app_services.dart';
import '../../theme/app_theme.dart';

/// Browse (and delete) every logged value for a custom metric — the "did I
/// already log this today" visibility gap the user hit, where a second log
/// silently added a duplicate row rather than anything showing up as a
/// correction. Opened via the notebook icon on the metric's Metrics card,
/// separate from the "+" that opens `CustomMetricEntrySheet` to add a new
/// one — one is "log a new value," this is "look at/fix what's there."
class CustomMetricHistorySheet extends StatefulWidget {
  final CustomMetric metric;
  const CustomMetricHistorySheet({super.key, required this.metric});

  @override
  State<CustomMetricHistorySheet> createState() => _CustomMetricHistorySheetState();
}

class _CustomMetricHistorySheetState extends State<CustomMetricHistorySheet> {
  bool _loading = true;
  List<CustomMetricEntry> _entries = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final entries = await AppServices.customMetrics.getEntries(widget.metric.id!);
    if (!mounted) return;
    setState(() {
      _entries = entries.reversed.toList(); // newest first
      _loading = false;
    });
  }

  Future<void> _delete(CustomMetricEntry entry) async {
    await AppServices.customMetrics.deleteEntry(entry.id!);
    AppServices.signalReload();
    await _load();
  }

  @override
  Widget build(BuildContext context) {
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
        child: _loading
            ? const Center(child: CircularProgressIndicator(color: AppColors.accent))
            : SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${widget.metric.name} Log', style: AppText.subHeader),
                    const SizedBox(height: AppSpacing.large),
                    if (_entries.isEmpty)
                      Text('No entries logged yet.', style: AppText.smallText)
                    else
                      ..._entries.map((e) => Padding(
                            padding: const EdgeInsets.only(bottom: AppSpacing.small),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: AppSpacing.standard, vertical: AppSpacing.small),
                              decoration: BoxDecoration(
                                border: Border.all(color: AppColors.border),
                                borderRadius: BorderRadius.circular(AppRadius.button),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      '${e.date} — ${widget.metric.formatValue(e.value)}',
                                      style: AppText.bodyText,
                                    ),
                                  ),
                                  GestureDetector(
                                    onTap: () => _delete(e),
                                    child: const Icon(Icons.delete_outline,
                                        size: 20, color: AppColors.textSecondary),
                                  ),
                                ],
                              ),
                            ),
                          )),
                  ],
                ),
              ),
      ),
    );
  }
}
