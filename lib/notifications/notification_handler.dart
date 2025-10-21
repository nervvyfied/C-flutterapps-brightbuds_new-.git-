import 'package:flutter/material.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class NotificationHandler extends StatefulWidget {
  final String parentId;
  final String? childId; // Only for child
  final String role; // 'parent' or 'child'

  const NotificationHandler({
    super.key,
    required this.parentId,
    this.childId,
    required this.role,
  });

  @override
  State<NotificationHandler> createState() => _NotificationHandlerState();
}

class _NotificationHandlerState extends State<NotificationHandler> {
  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications = FlutterLocalNotificationsPlugin();

  @override
  void initState() {
    super.initState();
    _initNotifications();
  }

  Future<void> _initNotifications() async {
    final settings = await _messaging.requestPermission(alert: true, badge: true, sound: true);

    if (settings.authorizationStatus == AuthorizationStatus.authorized) {
      print('✅ Notification permission granted');

      // Save FCM token
      final token = await _messaging.getToken();
      if (token != null) await _saveTokenToFirestore(token);
      print("🔹 ${widget.role} FCM Token: $token");

      FirebaseMessaging.onMessage.listen(_handleIncomingMessage);
      FirebaseMessaging.onMessageOpenedApp.listen(_handleNotificationTap);
    } else {
      print('⚠️ Notification permission denied');
    }
  }

  Future<void> _saveTokenToFirestore(String token) async {
    try {
      if (widget.role == 'parent') {
        await FirebaseFirestore.instance.collection('users').doc(widget.parentId).update({'fcmToken': token});
      } else if (widget.role == 'child' && widget.childId != null) {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(widget.parentId)
            .collection('children')
            .doc(widget.childId)
            .update({'fcmToken': token});
      }
    } catch (e) {
      print('⚠️ Failed to save FCM token: $e');
    }
  }

  void _handleIncomingMessage(RemoteMessage message) {
    final data = message.data;
    final type = data['type'] ?? '';
    String title = message.notification?.title ?? 'BrightBuds';
    String body = message.notification?.body ?? '';

    if (widget.role == 'parent') {
      switch (type) {
        case 'task_completed':
          title = '🎉 Task Completed';
          body = '${data['childName']} just finished ${data['taskName']}!';
          break;
        case 'journal_added':
          title = '📔 New Journal Entry';
          body = '${data['childName']} just added a new journal entry.';
          break;
      }
    } else if (widget.role == 'child') {
      switch (type) {
        case 'new_task':
          title = '🧩 New Task Assigned!';
          body = 'Your parent added a new task: ${data['taskName']}.';
          break;
        case 'cbt_assigned':
          title = '🧠 New CBT Exercise';
          body = 'Your parent assigned you new CBT exercises.';
          break;
        case 'fish_neglected':
          title = '🐟 Your Fish Needs Attention!';
          body = 'You haven’t checked your aquarium lately!';
          break;
      }
    }

    _showLocalNotification(title, body);
  }

  Future<void> _showLocalNotification(String title, String body) async {
    const androidDetails = AndroidNotificationDetails(
      'brightbuds_channel',
      'BrightBuds Notifications',
      importance: Importance.high,
      priority: Priority.high,
    );
    const details = NotificationDetails(android: androidDetails);

    await _localNotifications.show(DateTime.now().millisecondsSinceEpoch ~/ 1000, title, body, details);
  }

  void _handleNotificationTap(RemoteMessage message) {
    final type = message.data['type'];
    print("🔹 Notification tapped: $type");
    // Navigate if needed
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: Text("🔔 Notifications Active")));
  }
}
