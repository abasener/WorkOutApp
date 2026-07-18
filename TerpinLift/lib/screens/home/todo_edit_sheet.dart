import 'package:flutter/material.dart';

import '../../data/models/todo_item.dart';
import '../../services/app_services.dart';
import '../../services/notification_service.dart';
import '../../theme/app_theme.dart';

class _EditableTodo {
  final int? id;
  final TextEditingController textController;
  TimeOfDay? time;

  _EditableTodo({this.id, required String text, this.time})
      : textController = TextEditingController(text: text);
}

TimeOfDay _parseTime(String hhmm) {
  final parts = hhmm.split(':');
  return TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
}

String _formatTime(TimeOfDay t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

/// Batch editor for Home's Checklist — add/remove/reorder rows, each with an
/// optional reminder time, same "edit the whole set at once" shape as a lift
/// session's set-row editor. Saving replaces the entire list in one go
/// (`TodoRepository.replaceAll`) and reconciles reminder notifications:
/// every previously-scheduled id is cancelled, then a fresh daily reminder
/// is scheduled for whichever items still have a time set.
class TodoEditSheet extends StatefulWidget {
  final List<TodoItem> items;
  const TodoEditSheet({super.key, required this.items});

  @override
  State<TodoEditSheet> createState() => _TodoEditSheetState();
}

class _TodoEditSheetState extends State<TodoEditSheet> {
  late final List<_EditableTodo> _rows = widget.items.isEmpty
      ? [_EditableTodo(text: '')]
      : widget.items
          .map((i) => _EditableTodo(
                id: i.id,
                text: i.text,
                time: i.timeOfDay == null ? null : _parseTime(i.timeOfDay!),
              ))
          .toList();
  bool _saving = false;

  @override
  void dispose() {
    for (final row in _rows) {
      row.textController.dispose();
    }
    super.dispose();
  }

  Future<void> _pickTime(int i) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _rows[i].time ?? TimeOfDay.now(),
    );
    if (picked != null) setState(() => _rows[i].time = picked);
  }

  Future<void> _save() async {
    setState(() => _saving = true);

    final kept = _rows.where((r) => r.textController.text.trim().isNotEmpty).toList();
    final items = [
      for (var i = 0; i < kept.length; i++)
        TodoItem(
          id: kept[i].id,
          text: kept[i].textController.text.trim(),
          timeOfDay: kept[i].time == null ? null : _formatTime(kept[i].time!),
          sortOrder: i,
        ),
    ];
    await AppServices.todos.replaceAll(items);
    final saved = await AppServices.todos.getAll();

    // Clear out every previously-scheduled reminder first (covers removed
    // items and items whose time changed/cleared), then reschedule fresh
    // for whichever items currently have a time set.
    for (final old in widget.items) {
      if (old.id != null) await NotificationService.cancel(old.id!);
    }
    final anyTimed = saved.any((i) => i.timeOfDay != null);
    if (anyTimed) await NotificationService.requestPermission();
    for (final item in saved) {
      if (item.timeOfDay == null || item.id == null) continue;
      final t = _parseTime(item.timeOfDay!);
      await NotificationService.scheduleDaily(
        id: item.id!,
        title: 'Checklist reminder',
        body: item.text,
        hour: t.hour,
        minute: t.minute,
      );
    }

    AppServices.signalReload();
    if (mounted) Navigator.pop(context);
  }

  Widget _buildRow(int i) {
    final row = _rows[i];
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.standard),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          IconButton(
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            onPressed: _rows.length <= 1 ? null : () => setState(() => _rows.removeAt(i)),
            icon: const Icon(Icons.remove_circle_outline, size: 18),
            color: AppColors.textSecondary,
            disabledColor: AppColors.border,
          ),
          const SizedBox(width: AppSpacing.small),
          Expanded(
            child: TextField(
              controller: row.textController,
              style: AppText.bodyText,
              decoration: const InputDecoration(labelText: 'Item'),
            ),
          ),
          const SizedBox(width: AppSpacing.small),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: AppColors.border),
              foregroundColor: AppColors.textPrimary,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            ),
            onPressed: () => _pickTime(i),
            icon: const Icon(Icons.alarm, size: 16),
            label: Text(row.time == null ? 'None' : _formatTime(row.time!)),
          ),
          if (row.time != null)
            IconButton(
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              onPressed: () => setState(() => row.time = null),
              icon: const Icon(Icons.close, size: 16),
              color: AppColors.textSecondary,
            ),
        ],
      ),
    );
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
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Edit Checklist', style: AppText.subHeader),
              const SizedBox(height: AppSpacing.small),
              Text(
                'Set a time to get a daily reminder for that item — leave it '
                '"None" for a plain checklist row.',
                style: AppText.smallText,
              ),
              const SizedBox(height: AppSpacing.large),
              ...List.generate(_rows.length, _buildRow),
              const SizedBox(height: AppSpacing.small),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: AppColors.border),
                  foregroundColor: AppColors.textPrimary,
                  minimumSize: const Size(double.infinity, 44),
                ),
                onPressed: () => setState(() => _rows.add(_EditableTodo(text: ''))),
                icon: const Icon(Icons.add),
                label: const Text('Add another item'),
              ),
              const SizedBox(height: AppSpacing.large),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadius.button)),
                  ),
                  onPressed: _saving ? null : _save,
                  child: _saving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('Save'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
