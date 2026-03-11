import 'package:com.brightbuds/aquarium/manager/unlockManager.dart';
import 'package:com.brightbuds/aquarium/notifiers/achievement_listener.dart';
import 'package:com.brightbuds/aquarium/notifiers/achievement_notifier.dart';
import 'package:com.brightbuds/aquarium/notifiers/unlock_listener.dart';
import 'package:com.brightbuds/aquarium/pages/achievement_page.dart';
import 'package:com.brightbuds/aquarium/notifiers/unlockNotifier.dart';
import 'package:com.brightbuds/aquarium/providers/progression_provider.dart';
import 'package:com.brightbuds/cbt/models/assigned_cbt_model.dart';
import 'package:com.brightbuds/cbt/models/cbt_exercise_model.dart';
import 'package:com.brightbuds/cbt/providers/cbt_provider.dart';
import 'package:com.brightbuds/data/models/child_model.dart';
import 'package:com.brightbuds/data/models/journal_model.dart';
import 'package:com.brightbuds/data/models/parent_model.dart';
import 'package:com.brightbuds/data/models/therapist_model.dart';
import 'package:com.brightbuds/data/models/task_model.dart';
import 'package:com.brightbuds/data/providers/journal_provider.dart';
import 'package:com.brightbuds/data/providers/selected_child_provider.dart';
import 'package:com.brightbuds/data/providers/auth_provider.dart';
import 'package:com.brightbuds/data/providers/task_provider.dart';
import 'package:com.brightbuds/notifications/notification_service.dart';
import 'package:com.brightbuds/ui/pages/Therapistlogin_page.dart';
import 'package:com.brightbuds/ui/pages/parentlogin_page.dart';
import 'package:com.brightbuds/ui/pages/childlogin_page.dart';
import 'package:com.brightbuds/ui/widgets/splash_screen.dart';
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
      AndroidInitializationSettings('@mipmap/launcher_icon');

  const InitializationSettings initSettings = InitializationSettings(
    android: initializationSettingsAndroid,
  );

  await flutterLocalNotificationsPlugin.initialize(
    initSettings,
    onDidReceiveNotificationResponse: (NotificationResponse response) {},
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
  // Initialize PathService early

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
  } catch (e) {}

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
  await Hive.openBox<CBTExercise>('cbtExercise');
  await Hive.openBox<AssignedCBT>('assignedCBT');
  await Hive.openBox('settingsBox');

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
    // Get FCM token
    try {
      await messaging.getToken();
    } catch (e) {}

    // Single listener for foreground messages
    FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
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
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {});

    // Handle app launch from terminated state
    final initialMessage = await messaging.getInitialMessage();
    if (initialMessage != null) {}
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
        ChangeNotifierProvider(create: (_) => UnlockNotifier()),
        ChangeNotifierProvider(create: (_) => AchievementNotifier()),
        ChangeNotifierProvider(
          create: (_) => ProgressionProvider(
            child: ChildUser(
              cid: '',
              name: '',
              parentUid: '',
              therapistUid: '',
            ),
          ),
        ),
        ChangeNotifierProvider(
          create: (context) =>
              JournalProvider(context.read<AchievementNotifier>()),
        ),
        ChangeNotifierProvider(create: (_) => CBTProvider()),
        ChangeNotifierProvider(
          create: (context) => UnlockManager(
            childProvider: context.read<SelectedChildProvider>(),
            unlockNotifier: context.read<UnlockNotifier>(),
            achievementNotifier: context.read<AchievementNotifier>(),
          ),
        ),
        ChangeNotifierProvider(
          create: (context) => TaskProvider(
            context.read<UnlockManager>(),
            context.read<AchievementNotifier>(),
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
              home: AchievementListener(
                child: UnlockListener(child: const SplashScreen()),
              ),
              onGenerateRoute: (settings) {
                switch (settings.name) {
                  case '/parentAuth':
                    return MaterialPageRoute(
                      builder: (_) => const ParentAuthPage(),
                    );
                  case '/childAuth':
                    return MaterialPageRoute(
                      builder: (_) => const ChildAuthPage(),
                    );
                  case '/therapistAuth':
                    return MaterialPageRoute(
                      builder: (_) => const TherapistAuthPage(),
                    );
                  case '/achievements':
                    final args = settings.arguments as Map<String, dynamic>;
                    final child = args['child'] as ChildUser;
                    final tasks = args['tasks'] as List<TaskModel>;
                    final journals = args['journals'] as List<JournalEntry>;
                    return MaterialPageRoute(
                      builder: (_) => AchievementPage(
                        child: child,
                        tasks: tasks,
                        journals: journals,
                      ),
                    );
                  default:
                    return null;
                }
              },
            ),
          );
        },
      ),
    );
  }
}
