import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

/// Local reminder notifications for Home's Checklist widget — one scheduled
/// notification per item that has a time set, repeating daily at that
/// time-of-day. Deliberately **inexact** (`AndroidScheduleMode.
/// inexactAllowWhileIdle`) rather than requesting Android 12+'s separate
/// "exact alarm" permission (a dedicated system-settings toggle, much
/// heavier to ask for than the normal notification prompt) — "remind me
/// around 7am to bring my water bottle" doesn't need to-the-second
/// precision, so the plain runtime `POST_NOTIFICATIONS` prompt is enough.
abstract class NotificationService {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _initialized = false;

  static const _channelId = 'todo_reminders';
  static const _channelName = 'Checklist Reminders';
  static const _channelDescription = "Reminders for Home's checklist items";

  static Future<void> init() async {
    if (_initialized) return;
    tz_data.initializeTimeZones();
    try {
      final localTz = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(localTz.identifier));
    } catch (_) {
      // Falls back to UTC if the platform lookup fails — reminders still
      // fire, just not necessarily at the intended local hour. Not worth
      // blocking init over.
    }
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
    );
    _initialized = true;
  }

  /// Shows the OS permission prompt (Android 13+) if not already
  /// granted/denied — returns whether notifications are usable. Safe to
  /// call repeatedly; the OS only actually prompts once.
  static Future<bool> requestPermission() async {
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    final granted = await android?.requestNotificationsPermission();
    return granted ?? true;
  }

  /// Schedules (or reschedules — cancels any existing one with this [id]
  /// first) a daily reminder at [hour]:[minute] local time. [id] should be
  /// stable per todo item (its DB row id) so re-saving the same item
  /// updates its reminder instead of stacking up duplicates.
  ///
  /// [skipToday] pushes the first occurrence to tomorrow even if today's
  /// [hour]:[minute] hasn't happened yet — used to silence today's reminder
  /// the moment a checklist item gets checked off (already done, no need to
  /// be reminded again today) without disturbing the recurring schedule for
  /// the days after.
  static Future<void> scheduleDaily({
    required int id,
    required String title,
    required String body,
    required int hour,
    required int minute,
    bool skipToday = false,
  }) async {
    await _plugin.zonedSchedule(
      id: id,
      title: title,
      body: body,
      scheduledDate: _nextInstanceOf(hour, minute, skipToday: skipToday),
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: _channelDescription,
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.time,
    );
  }

  static Future<void> cancel(int id) => _plugin.cancel(id: id);

  static tz.TZDateTime _nextInstanceOf(int hour, int minute, {bool skipToday = false}) {
    final now = tz.TZDateTime.now(tz.local);
    var scheduled = tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);
    if (scheduled.isBefore(now) || skipToday) {
      scheduled = scheduled.add(const Duration(days: 1));
    }
    return scheduled;
  }
}
