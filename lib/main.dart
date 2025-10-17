import 'package:brightbuds_new/aquarium/manager/unlockManager.dart';
import 'package:brightbuds_new/aquarium/models/placedDecor_model.dart';
import 'package:brightbuds_new/aquarium/notifiers/unlock_listener.dart';
import 'package:brightbuds_new/aquarium/pages/achievement_page.dart';
import 'package:brightbuds_new/aquarium/providers/decor_provider.dart';
import 'package:brightbuds_new/aquarium/providers/fish_provider.dart';
import 'package:brightbuds_new/aquarium/notifiers/unlockNotifier.dart';
import 'package:brightbuds_new/cbt/models/assigned_cbt_model.dart';
import 'package:brightbuds_new/cbt/models/cbt_exercise_model.dart';
import 'package:brightbuds_new/cbt/providers/cbt_provider.dart';
import 'package:brightbuds_new/data/models/child_model.dart';
import 'package:brightbuds_new/data/models/journal_model.dart';
import 'package:brightbuds_new/data/models/parent_model.dart';
import 'package:brightbuds_new/data/models/task_model.dart';
import 'package:brightbuds_new/data/providers/journal_provider.dart';
import 'package:brightbuds_new/data/providers/selected_child_provider.dart';
import 'package:brightbuds_new/data/providers/auth_provider.dart';
import 'package:brightbuds_new/data/providers/task_provider.dart';
import 'package:brightbuds_new/ui/pages/child_view/childNav_page.dart';
import 'package:brightbuds_new/ui/pages/parent_view/parentNav_page.dart';
import 'package:brightbuds_new/ui/pages/role_page.dart';
import 'package:brightbuds_new/ui/pages/parentlogin_page.dart';
import 'package:brightbuds_new/ui/pages/childlogin_page.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:provider/provider.dart';
import 'firebase_options.dart';

// 🔔 FCM + local notifications
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// ------------------ BACKGROUND HANDLER ------------------
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  debugPrint('🔹 FCM background message received: ${message.messageId}');
}

/// ------------------ LOCAL NOTIFICATIONS SETUP ------------------
final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

final AndroidNotificationChannel _androidChannel = AndroidNotificationChannel(
  'brightbuds_channel', // id
  'BrightBuds Notifications', // name
  description: 'Notifications for BrightBuds app',
  importance: Importance.high,
);

Future<void> _initFlutterLocalNotifications() async {
  const AndroidInitializationSettings initializationSettingsAndroid =
      AndroidInitializationSettings('@mipmap/ic_launcher');

  const InitializationSettings initSettings =
      InitializationSettings(android: initializationSettingsAndroid);

  await flutterLocalNotificationsPlugin.initialize(initSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) {
    debugPrint('🔔 Local notification tapped: ${response.payload}');
  });

  await flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(_androidChannel);
}

/// ------------------ MAIN ENTRY ------------------
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ---------------- Firebase Core ----------------
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // ✅ ADD THIS: Enable Firestore offline caching
  // ------------------------------------------------
  try {
    FirebaseFirestore.instance.settings = const Settings(
      persistenceEnabled: true,
    );
    debugPrint('✅ Firestore offline persistence enabled');
  } catch (e) {
    debugPrint('⚠️ Failed to enable Firestore persistence: $e');
  }

  // ---------------- FCM Setup ----------------
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  await _initFlutterLocalNotifications();

  // ---------------- Hive Setup ----------------
  await Hive.initFlutter();

  if (!Hive.isAdapterRegistered(ParentUserAdapter().typeId)) {
    Hive.registerAdapter(ParentUserAdapter());
  }
  if (!Hive.isAdapterRegistered(ChildUserAdapter().typeId)) {
    Hive.registerAdapter(ChildUserAdapter());
  }
  if (!Hive.isAdapterRegistered(TaskModelAdapter().typeId)) {
    Hive.registerAdapter(TaskModelAdapter());
  }
  if (!Hive.isAdapterRegistered(JournalEntryAdapter().typeId)) {
    Hive.registerAdapter(JournalEntryAdapter());
  }
  if (!Hive.isAdapterRegistered(PlacedDecorAdapter().typeId)) {
    Hive.registerAdapter(PlacedDecorAdapter());
  }
  if (!Hive.isAdapterRegistered(AssignedCBTAdapter().typeId)) {
    Hive.registerAdapter(AssignedCBTAdapter());
  }
  if (!Hive.isAdapterRegistered(CBTExerciseAdapter().typeId)) {
    Hive.registerAdapter(CBTExerciseAdapter());
  }

  await Hive.openBox<ParentUser>('parentBox');
  await Hive.openBox<ChildUser>('childBox');
  await Hive.openBox<TaskModel>('tasksBox');
  await Hive.openBox<JournalEntry>('journalBox');
  await Hive.openBox<PlacedDecor>('placedDecors');
  await Hive.openBox<CBTExercise>('cbtExercise');
  await Hive.openBox<AssignedCBT>('assignedCBT');

  // ✅ (Optional but recommended) Print confirmation for debug
  debugPrint('✅ Hive boxes opened and ready.');

  runApp(const MyApp());
}


/// ------------------ APP ------------------
class MyApp extends StatelessWidget {
  const MyApp({super.key});

  Future<void> _initializeFCM() async {
    final FirebaseMessaging messaging = FirebaseMessaging.instance;

    final settings = await messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    debugPrint('🔹 FCM permission status: ${settings.authorizationStatus}');

    try {
      final token = await messaging.getToken();
      debugPrint('🔹 FCM token: $token');
    } catch (e) {
      debugPrint('⚠️ Failed to get FCM token: $e');
    }

    // Foreground message handler
    FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
      debugPrint('🔹 Foreground FCM message: ${message.notification?.title}');

      final notification = message.notification;
      final android = message.notification?.android;

      // ⚙️ FIXED: remove `const` — cannot use const with dynamic values
      final androidDetails = AndroidNotificationDetails(
        _androidChannel.id,
        _androidChannel.name,
        channelDescription: _androidChannel.description,
        importance: Importance.high,
        priority: Priority.high,
        icon: android?.smallIcon ?? '@mipmap/ic_launcher',
      );

      final platformDetails = NotificationDetails(android: androidDetails);

      await flutterLocalNotificationsPlugin.show(
        message.hashCode,
        notification?.title ?? 'BrightBuds',
        notification?.body ?? '',
        platformDetails,
        payload: message.data.isNotEmpty ? message.data.toString() : null,
      );
    });

    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      debugPrint('🔹 Notification opened app: ${message.notification?.title}');
    });

    final initialMessage = await FirebaseMessaging.instance.getInitialMessage();
    if (initialMessage != null) {
      debugPrint(
          '🔹 App opened from terminated state: ${initialMessage.notification?.title}');
    }
  }

  @override
  Widget build(BuildContext context) {
    _initializeFCM();

    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => SelectedChildProvider()),
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => TaskProvider()),
        ChangeNotifierProvider(create: (_) => JournalProvider()),
        ChangeNotifierProvider(
          create: (context) =>
              DecorProvider(authProvider: context.read<AuthProvider>()),
        ),
        ChangeNotifierProvider(
          create: (context) =>
              FishProvider(authProvider: context.read<AuthProvider>()),
        ),
        ChangeNotifierProvider(create: (_) => UnlockNotifier()),
        ChangeNotifierProvider(create: (_) => CBTProvider()),
        Provider(
          create: (context) => UnlockManager(
            unlockNotifier: context.read<UnlockNotifier>(),
            fishProvider: context.read<FishProvider>(),
            selectedChildProvider: context.read<SelectedChildProvider>(),
          ),
        ),
      ],
      child: Consumer<AuthProvider>(
        builder: (context, auth, _) {
          return UnlockListener(
            child: MaterialApp(
              title: 'BrightBuds',
              theme: ThemeData(primarySwatch: Colors.blue),
              home: Builder(
                builder: (context) {
                  if (auth.isLoading) {
                    return const Scaffold(
                      body: Center(child: CircularProgressIndicator()),
                    );
                  }

                  if (auth.isParent) return const ParentNavigationShell();
                  if (auth.isChild) return const ChildNavigationShell();

                  return const ChooseRolePage();
                },
              ),
              routes: {
                '/parentAuth': (context) => const ParentAuthPage(),
                '/childAuth': (context) => const ChildAuthPage(),
                '/achievements': (context) => const AchievementPage(),
              },
            ),
          );
        },
      ),
    );
  }
}
