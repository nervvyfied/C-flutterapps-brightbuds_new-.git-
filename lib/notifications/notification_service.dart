import 'package:com.brightbuds/notifications/fcm_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import '../data/models/task_model.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  // Channels
  final AndroidNotificationChannel dailyReminderChannel =
      AndroidNotificationChannel(
        'daily_reminder_channel',
        'Daily Task Reminders',
        description: 'Daily reminders for tasks',
        importance: Importance.high,
      );

  final AndroidNotificationChannel generalChannel = AndroidNotificationChannel(
    'brightbuds_channel',
    'BrightBuds Notifications',
    description: 'General notifications for BrightBuds app',
    importance: Importance.high,
  );

  Future<void> init() async {
    if (kIsWeb) {
      return;
    }
    // Initialize timezone
    tz.initializeTimeZones();

    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/launcher_icon');

    const InitializationSettings initializationSettings =
        InitializationSettings(android: initializationSettingsAndroid);

    await flutterLocalNotificationsPlugin.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: (response) {},
    );

    // Create notification channels
    await flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(dailyReminderChannel);

    await flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(generalChannel);
  }

  Future<void> scheduleNotification({
    required int id,
    required String title,
    required String body,
    required DateTime scheduledDate,
    required String payload,
  }) async {
    if (kIsWeb) {
      return;
    }

    if (scheduledDate.isBefore(DateTime.now())) {
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
            'daily_reminder_channel',
            'Daily Task Reminders',
            channelDescription: 'Daily reminders for tasks',
            importance: Importance.max,
            priority: Priority.high,
          ),
        ),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        matchDateTimeComponents: DateTimeComponents.time,
        payload: payload,
      );
    } catch (e) {}
  }

  // Schedule daily notification
  Future<void> scheduleDailyNotification({
    required int id,
    required String title,
    required String body,
    required int hour,
    required int minute,
    String? payload,
  }) async {
    if (kIsWeb) {
      return;
    }

    final now = tz.TZDateTime.now(tz.local);
    var scheduledDate = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      hour,
      minute,
    );
    if (scheduledDate.isBefore(now))
      scheduledDate = scheduledDate.add(const Duration(days: 1));

    final androidDetails = AndroidNotificationDetails(
      dailyReminderChannel.id,
      dailyReminderChannel.name,
      channelDescription: dailyReminderChannel.description,
      importance: Importance.max,
      priority: Priority.high,
    );

    await flutterLocalNotificationsPlugin.zonedSchedule(
      id,
      title,
      body,
      scheduledDate,
      NotificationDetails(android: androidDetails),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      matchDateTimeComponents:
          DateTimeComponents.time, // repeat daily at same time
      payload: payload,
    );
  }

  Future<void> cancelNotification(int id) async {
    await flutterLocalNotificationsPlugin.cancel(id);
  }

  // NOTIFICATIONS

  Future<void> notifyParent({
    required String parentFcmToken,
    required String childName,
    required String taskName,
    required bool isCbt,
  }) async {
    final title = isCbt ? "CBT Completed" : "Task Completed";
    final body = isCbt
        ? "$childName has completed a CBT exercise!"
        : "$childName has completed the task: $taskName";

    await FCMService.sendNotification(
      title: title,
      body: body,
      token: parentFcmToken,
      data: {
        'childName': childName,
        'taskName': taskName,
        'isCbt': isCbt.toString(),
      },
    );
  }

  Future<void> scheduleChildTaskNotification({
    required String childFcmToken,
    required String taskName,
    required DateTime scheduledTime,
  }) async {
    // Local notification (for offline)
    await NotificationService().scheduleNotification(
      id: scheduledTime.millisecondsSinceEpoch ~/ 1000,
      title: "Time for your task!",
      body: taskName,
      scheduledDate: scheduledTime,
      payload: taskName,
    );
  }

  /// 🔹 Web alarm simulation (runs only on Chrome)
  void startWebAlarmSimulation(List<TaskModel> tasks) {
    if (!kIsWeb) return;

    Future.doWhile(() async {
      final now = DateTime.now();
      for (final task in tasks) {
        if (task.alarm != null) {
          final alarmTime = DateTime(
            now.year,
            now.month,
            now.day,
            task.alarm!.hour,
            task.alarm!.minute,
          );

          if (now.difference(alarmTime).inSeconds.abs() <= 5) {}
        }
      }
      await Future.delayed(const Duration(seconds: 10));
      return true;
    });
  }

  // Add this method in NotificationService
  Future<void> debugTestNotification(String title, String body) async {
    // Only show a local notification if not web
    if (!kIsWeb) {
      await flutterLocalNotificationsPlugin.show(
        9999,
        title,
        body,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'debug_channel',
            'Debug Notifications',
            importance: Importance.high,
            priority: Priority.high,
            icon: '@mipmap/launcher_icon',
          ),
        ),
      );
    } else {}
  }
}
