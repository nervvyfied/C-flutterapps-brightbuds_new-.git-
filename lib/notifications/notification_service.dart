import 'package:brightbuds_new/ui/widgets/child_alarm_trigger_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
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
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const InitializationSettings initializationSettings =
        InitializationSettings(android: initializationSettingsAndroid);

    await flutterLocalNotificationsPlugin.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: (response) {
        if (response.payload != null && response.payload!.isNotEmpty) {
          final parts = response.payload!.split('|');
          final taskId = parts[0];
          final childId = parts[1];
          final parentId = parts[2];
          final childName = parts[3];

          final taskProvider = navigatorKey.currentContext?.read<TaskProvider>();
          TaskModel? task =
              taskProvider?.tasks.firstWhere((t) => t.id == taskId, orElse: () => TaskModel(
                id: taskId,
                name: 'Unknown Task',
                difficulty: 'Easy',
                reward: 0,
                routine: 'Anytime',
                parentId: parentId,
                childId: childId,
                createdAt: DateTime.now(),
              ));

          navigatorKey.currentState?.push(MaterialPageRoute(
            builder: (_) => ChildAlarmTriggerPage(
              task: task!,
              childId: childId,
              parentId: parentId,
              childName: childName,
            ),
          ));
        }
      },
    );
  }

  Future<void> scheduleNotification({
  required int id,
  required String title,
  required String body,
  required DateTime scheduledDate,
  required String payload,
}) async {
  // ⚠️ Skip alarms on web
  if (kIsWeb) {
    print('⚠️ Skipping alarm scheduling on web for $title');
    return;
  }

  debugPrint('⏰ Attempting to schedule alarm: $title at $scheduledDate');

  if (scheduledDate.isBefore(DateTime.now())) {
    debugPrint('❌ Alarm cancelled because scheduledDate is in the past');
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


  Future<void> cancelNotification(int id) async {
    await flutterLocalNotificationsPlugin.cancel(id);
  }
}
