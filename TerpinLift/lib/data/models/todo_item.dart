/// One row in Home's Checklist widget — a recurring reminder, not a one-off
/// task. [lastCheckedDate] is the entire daily-reset mechanism: [isCheckedOn]
/// compares it against whatever date is asked about, so a new day just reads
/// as unchecked without anything needing to run overnight to clear it.
class TodoItem {
  final int? id;
  final String text;

  /// `'HH:mm'`, 24-hour, local time — `null` means no reminder.
  final String? timeOfDay;
  final int sortOrder;
  final String? lastCheckedDate;

  const TodoItem({
    this.id,
    required this.text,
    this.timeOfDay,
    required this.sortOrder,
    this.lastCheckedDate,
  });

  bool isCheckedOn(String dateStr) => lastCheckedDate == dateStr;

  /// Parsed out of [timeOfDay] ('HH:mm') for `NotificationService` call
  /// sites, without pulling a Flutter `TimeOfDay` into this plain-Dart model.
  int? get reminderHour => timeOfDay == null ? null : int.parse(timeOfDay!.split(':')[0]);
  int? get reminderMinute => timeOfDay == null ? null : int.parse(timeOfDay!.split(':')[1]);

  factory TodoItem.fromMap(Map<String, dynamic> m) => TodoItem(
        id: m['id'] as int?,
        text: m['text'] as String,
        timeOfDay: m['time_of_day'] as String?,
        sortOrder: m['sort_order'] as int,
        lastCheckedDate: m['last_checked_date'] as String?,
      );

  Map<String, dynamic> toMap() => {
        'text': text,
        'time_of_day': timeOfDay,
        'sort_order': sortOrder,
        'last_checked_date': lastCheckedDate,
      };

  TodoItem copyWith({
    String? text,
    String? timeOfDay,
    bool clearTimeOfDay = false,
    int? sortOrder,
    String? lastCheckedDate,
    bool clearLastCheckedDate = false,
  }) =>
      TodoItem(
        id: id,
        text: text ?? this.text,
        timeOfDay: clearTimeOfDay ? null : (timeOfDay ?? this.timeOfDay),
        sortOrder: sortOrder ?? this.sortOrder,
        lastCheckedDate:
            clearLastCheckedDate ? null : (lastCheckedDate ?? this.lastCheckedDate),
      );
}
