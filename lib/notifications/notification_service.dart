import 'package:brightbuds_new/ui/widgets/child_alarm_trigger_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import '../main.dart'; // for navigatorKey
import '../data/providers/task_provider.dart';
import '../data/models/task_model.dart';
import 'package:provider/provider.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  Future<void> init() async {
    // initialize timezone db
    tz.initializeTimeZones();

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidInit);

    await flutterLocalNotificationsPlugin.initialize(initSettings);

  /// Schedule a one-time (or next-occurrence) notification at a specific DateTime
  }

  Future<void> scheduleNotification({
    required int id,
    required String title,
    required String body,
    required DateTime scheduledDate,
    required String payload,
  }) async {
    if (kIsWeb) {
      debugPrint('⚠️ Skipping alarm scheduling on web for $title');
      return;
    }

    debugPrint('⏰ Attempting to schedule alarm: $title at $scheduledDate');

    if (scheduledDate.isBefore(DateTime.now())) {
      debugPrint('❌ Alarm not scheduled: scheduledDate is in the past');
      return;
    }

    try {
      await flutterLocalNotificationsPlugin.zonedSchedule(
        id,
        title,
        body,
        tz.TZDateTime.from(scheduledDate, tz.local),
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'daily_tasks_channel',
            'Daily Tasks',
            channelDescription: 'Daily task reminders',
            importance: Importance.max,
            priority: Priority.high,
          ),
        ),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        matchDateTimeComponents: DateTimeComponents.time,
        payload: payload,
      );
      debugPrint('✅ Alarm scheduled successfully for $title at $scheduledDate');
    } catch (e) {
      debugPrint('❌ Failed to schedule alarm for $title: $e');
    }
  }

  /// Schedule a **recurring daily** notification (fires every day at hour:minute)
  Future<void> scheduleDailyNotification({
    required int id,
    required String title,
    required String body,
    required int hour,
    required int minute,
    String? payload,
  }) async {
    if (kIsWeb) {
      debugPrint('⚠️ Skipping daily schedule on web');
      return;
    }

    final androidDetails = AndroidNotificationDetails(
      'daily_reminder_channel',
      'Daily Task Reminders',
      channelDescription: 'Daily reminders for tasks',
      importance: Importance.high,
      priority: Priority.high,
    );
    final details = NotificationDetails(android: androidDetails);

    final now = tz.TZDateTime.now(tz.local);
    var scheduledDate = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      hour,
      minute,
    );

    if (scheduledDate.isBefore(now)) {
      scheduledDate = scheduledDate.add(const Duration(days: 1));
    }

    try {
      await flutterLocalNotificationsPlugin.zonedSchedule(
        id,
        title,
        body,
        scheduledDate,
        details,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        matchDateTimeComponents: DateTimeComponents.time, // repeats daily
        payload: payload,
      );
      debugPrint('✅ Daily notification scheduled at $hour:$minute');
    } catch (e) {
      debugPrint('❌ Failed to schedule daily notification: $e');
    }
  }

  Future<void> cancelNotification(int id) async {
    await flutterLocalNotificationsPlugin.cancel(id);
    debugPrint('❌ Cancelled notification $id');
  }

  Future<void> cancelAllNotifications() async {
    await flutterLocalNotificationsPlugin.cancelAll();
    debugPrint('🧹 All notifications cancelled');
  }
}