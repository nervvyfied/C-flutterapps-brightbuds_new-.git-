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
import 'package:brightbuds_new/data/models/therapist_model.dart';
import 'package:brightbuds_new/data/models/task_model.dart';
import 'package:brightbuds_new/data/providers/journal_provider.dart';
import 'package:brightbuds_new/data/providers/selected_child_provider.dart';
import 'package:brightbuds_new/data/providers/auth_provider.dart';
import 'package:brightbuds_new/data/providers/task_provider.dart';
import 'package:brightbuds_new/notifications/notification_service.dart';
import 'package:brightbuds_new/ui/pages/parent_view/parentHome_page.dart';
import 'package:brightbuds_new/ui/pages/parentlogin_page.dart';
import 'package:brightbuds_new/ui/pages/childlogin_page.dart';
import 'package:brightbuds_new/ui/pages/therapist_view/therapistHome_page.dart';
import 'package:brightbuds_new/ui/pages/therapistlogin_page.dart';
import 'package:brightbuds_new/ui/widgets/splash_screen.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:provider/provider.dart';
import 'firebase_options.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

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

  const InitializationSettings initSettings = InitializationSettings(
    android: initializationSettingsAndroid,
  );

  await flutterLocalNotificationsPlugin.initialize(
    initSettings,
    onDidReceiveNotificationResponse: (NotificationResponse response) {
      debugPrint('🔔 Local notification tapped: ${response.payload}');
    },
  );

  // ✅ Request permission for notifications
  final bool? granted = await flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >()
      ?.requestNotificationsPermission();

  if (granted ?? false) {
    final dailyChannel = AndroidNotificationChannel(
      'daily_reminder_channel',
      'Daily Task Reminders',
      description: 'Daily reminders for tasks',
      importance: Importance.high,
    );

    await flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(dailyChannel);

    await flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(_androidChannel);
  }
}

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

/// ------------------ MAIN ENTRY ------------------
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ✅ Initialize Firebase first
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // ✅ Initialize local notifications (for both alarm + FCM compatibility)
  await _initFlutterLocalNotifications();
  await NotificationService().init();

  // ✅ Initialize timezone (important for alarms)
  tz.initializeTimeZones();
  tz.setLocalLocation(tz.getLocation('Asia/Manila'));

  // ✅ Enable Firestore offline caching (optional but good)
  try {
    FirebaseFirestore.instance.settings = const Settings(
      persistenceEnabled: true,
    );
    debugPrint('✅ Firestore offline persistence enabled');
  } catch (e) {
    debugPrint('⚠️ Failed to enable Firestore persistence: $e');
  }

  // ✅ Setup FCM background handler
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  // ✅ Initialize Hive
  await Hive.initFlutter();
  if (!Hive.isAdapterRegistered(TherapistUserAdapter().typeId)) {
    Hive.registerAdapter(TherapistUserAdapter());
  }
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

  await Hive.openBox<TherapistUser>('therapistBox');
  await Hive.openBox<ParentUser>('parentBox');
  await Hive.openBox<ChildUser>('childBox');
  await Hive.openBox<TaskModel>('tasksBox');
  await Hive.openBox<JournalEntry>('journalBox');
  await Hive.openBox<PlacedDecor>('placedDecors');
  await Hive.openBox<CBTExercise>('cbtExercise');
  await Hive.openBox<AssignedCBT>('assignedCBT');

  debugPrint('✅ Hive boxes opened and ready.');

  runApp(const MyApp());
}

/// ------------------ FCM INITIALIZATION ------------------
bool _fcmInitialized = false;

Future<void> _initializeFCM() async {
  if (_fcmInitialized) return;
  _fcmInitialized = true;

  final FirebaseMessaging messaging = FirebaseMessaging.instance;

  // Request permission
  final settings = await messaging.requestPermission(
    alert: true,
    badge: true,
    sound: true,
  );
  if (settings.authorizationStatus != AuthorizationStatus.authorized) {
    debugPrint('❌ Notifications not authorized!');
  }

  // Get FCM token
  try {
    final token = await messaging.getToken();
    debugPrint('🔹 FCM token: $token');
  } catch (e) {
    debugPrint('⚠️ Failed to get FCM token: $e');
  }

  // Single listener for foreground messages
  FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
    debugPrint('📩 [FCM] Foreground message received!');
    debugPrint('Title: ${message.notification?.title}');
    debugPrint('Body: ${message.notification?.body}');
    debugPrint('Data: ${message.data}');

    final notification = message.notification;
    final androidDetails = AndroidNotificationDetails(
      _androidChannel.id,
      _androidChannel.name,
      channelDescription: _androidChannel.description,
      importance: Importance.high,
      priority: Priority.high,
    );

    // 🔔 Show local notification to confirm reception
    await flutterLocalNotificationsPlugin.show(
      message.hashCode,
      notification?.title ?? 'BrightBuds',
      notification?.body ?? 'You have a new update!',
      NotificationDetails(android: androidDetails),
    );
  });

  // When notification is tapped and app opens
  FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
    debugPrint('🔹 Notification opened app: ${message.notification?.title}');
  });

  // Handle app launch from terminated state
  final initialMessage = await messaging.getInitialMessage();
  if (initialMessage != null) {
    debugPrint(
      '🔹 App opened from terminated state: ${initialMessage.notification?.title}',
    );
  }
}

/// ------------------ APP ------------------
class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  @override
  void initState() {
    super.initState();
    // Initialize FCM in initState instead of build
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _initializeFCM();
    });
  }

  @override
  Widget build(BuildContext context) {
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
              navigatorKey: navigatorKey,
              title: 'BrightBuds',
              theme: ThemeData(
                fontFamily: 'Fredoka', // <- applies Fredoka globally
                primarySwatch: Colors.blue,
              ),
              home: Builder(
                builder: (context) {
                  if (auth.isLoading) {
                    return const Scaffold(
                      body: Center(child: CircularProgressIndicator()),
                    );
                  }

                  // Show splash screen first
                  return const SplashScreen();
                },
              ),

              routes: {
                '/parentAuth': (context) => const ParentAuthPage(),
                '/therapistAuth': (context) => const TherapistAuthPage(),
                '/childAuth': (context) => const ChildAuthPage(),
                '/achievements': (context) => const AchievementPage(),
                '/therapistHome': (context) => const TherapistDashboardPage(
                  therapistId: '',
                  parentId: '',
                ), // Added
                '/parentHome': (context) =>
                    const ParentDashboardPage(parentId: ''), // Added
              },
            ),
          );
        },
      ),
    );
  }
}
