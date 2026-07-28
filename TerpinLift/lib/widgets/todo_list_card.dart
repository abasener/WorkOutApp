import 'dart:async';

import 'package:flutter/material.dart';

import '../data/models/todo_item.dart';
import '../screens/home/todo_edit_sheet.dart';
import '../services/app_services.dart';
import '../services/notification_service.dart';
import '../theme/app_theme.dart';
import 'app_card.dart';
import 'tap_icon.dart';

/// Home's Checklist widget — a fixed, user-edited list of recurring
/// reminders ("bring water bottle," "log sleep"), each with a circular
/// tap-to-check box that strikes through the text once checked. Checks
/// reset every day on their own (`TodoItem.isCheckedOn` just compares
/// against today's date), no background job needed. Edit pencil opens
/// `TodoEditSheet` for adding/removing/reordering items and setting an
/// optional reminder time per item.
class TodoListCard extends StatefulWidget {
  const TodoListCard({super.key});

  @override
  State<TodoListCard> createState() => _TodoListCardState();
}

class _TodoListCardState extends State<TodoListCard> {
  bool _loading = true;
  List<TodoItem> _items = [];
  String _shownDate = '';
  Timer? _midnightCheck;

  @override
  void initState() {
    super.initState();
    AppServices.reloadSignal.addListener(_load);
    _shownDate = _today;
    _load();
    // isCheckedOn already re-derives against whatever "today" is at build
    // time, so this doesn't touch the DB — it just makes sure something
    // rebuilds the card if the app is left open across midnight, instead of
    // waiting on some unrelated reload to happen to fire first.
    _midnightCheck = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted && _today != _shownDate) setState(() => _shownDate = _today);
    });
  }

  @override
  void dispose() {
    AppServices.reloadSignal.removeListener(_load);
    _midnightCheck?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final items = await AppServices.todos.getAll();
    if (!mounted) return;
    setState(() {
      _items = items;
      _loading = false;
    });
  }

  String get _today => DateTime.now().toIso8601String().substring(0, 10);

  Future<void> _toggle(TodoItem item) async {
    final wasChecked = item.isCheckedOn(_today);
    await AppServices.todos.setCheckedToday(item, _today, !wasChecked);
    // Checking an item off silences *today's* reminder — already done, no
    // need to be nagged again — without touching the recurring schedule for
    // the days after. Unchecking (undo) restores the normal schedule, which
    // may still fire today if the reminder time hasn't passed yet.
    final id = item.id;
    final hour = item.reminderHour;
    final minute = item.reminderMinute;
    if (id != null && hour != null && minute != null) {
      // Explicit cancel before rescheduling — a bare re-schedule with the
      // same id doesn't reliably replace an already-pending native alarm
      // for a `matchDateTimeComponents` repeating reminder, which is how a
      // checked-off item could still fire later that same day. Mirrors
      // TodoEditSheet._save, which already did this correctly.
      await NotificationService.cancel(id);
      await NotificationService.scheduleDaily(
        id: id,
        title: 'Checklist reminder',
        body: item.text,
        hour: hour,
        minute: minute,
        skipToday: !wasChecked,
      );
    }
    AppServices.signalReload();
  }

  Future<void> _edit() async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => TodoEditSheet(items: _items),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Checklist', style: AppText.bodyText),
              const Spacer(),
              TapIcon(icon: Icons.edit_outlined, size: 18, onTap: _edit),
            ],
          ),
          const SizedBox(height: AppSpacing.small),
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: AppSpacing.standard),
              child: Center(
                child: CircularProgressIndicator(color: AppColors.accent),
              ),
            )
          else if (_items.isEmpty)
            Text(
              'No items yet. Tap the pencil to add some.',
              style: AppText.smallText,
            )
          else
            ..._items.map(_row),
        ],
      ),
    );
  }

  Widget _row(TodoItem item) {
    final checked = item.isCheckedOn(_today);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: GestureDetector(
        onTap: () => _toggle(item),
        child: Row(
          children: [
            Icon(
              checked ? Icons.check_circle : Icons.radio_button_unchecked,
              size: 22,
              color: checked ? AppColors.accent : AppColors.textSecondary,
            ),
            const SizedBox(width: AppSpacing.standard),
            Expanded(
              child: Text(
                item.text,
                style: AppText.bodyText.copyWith(
                  color: checked
                      ? AppColors.textSecondary
                      : AppColors.textPrimary,
                  decoration: checked ? TextDecoration.lineThrough : null,
                ),
              ),
            ),
            if (item.timeOfDay != null) ...[
              const SizedBox(width: AppSpacing.small),
              Icon(Icons.alarm, size: 14, color: AppColors.textSecondary),
              const SizedBox(width: 2),
              Text(item.timeOfDay!, style: AppText.smallText),
            ],
          ],
        ),
      ),
    );
  }
}
