import 'package:brightbuds_new/aquarium/models/placedDecor_model.dart';
import 'package:brightbuds_new/aquarium/notifiers/unlock_listener.dart';
import 'package:brightbuds_new/aquarium/pages/achievement_page.dart';
import 'package:brightbuds_new/aquarium/providers/decor_provider.dart';
import 'package:brightbuds_new/aquarium/providers/fish_provider.dart';
import 'package:brightbuds_new/aquarium/notifiers/unlockNotifier.dart';
import 'package:brightbuds_new/data/models/child_model.dart';
import 'package:brightbuds_new/data/models/journal_model.dart';
import 'package:brightbuds_new/data/models/parent_model.dart';
import 'package:brightbuds_new/data/models/task_model.dart';
import 'package:brightbuds_new/providers/journal_provider.dart';
import 'package:brightbuds_new/providers/selected_child_provider.dart';
import 'package:brightbuds_new/providers/auth_provider.dart';
import 'package:brightbuds_new/providers/task_provider.dart';
import 'package:brightbuds_new/ui/pages/child_view/childNav_page.dart';
import 'package:brightbuds_new/ui/pages/parent_view/parentNav_page.dart';
import 'package:brightbuds_new/ui/pages/role_page.dart';
import 'package:brightbuds_new/ui/pages/parentlogin_page.dart';
import 'package:brightbuds_new/ui/pages/childlogin_page.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:provider/provider.dart';

import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  await Hive.initFlutter();

  // ---------------- Register Adapters ----------------
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
  // ---------------- Open Boxes ----------------
  await Hive.openBox<ParentUser>('parentBox');
  await Hive.openBox<ChildUser>('childBox');
  await Hive.openBox<TaskModel>('tasksBox');
  await Hive.openBox<JournalEntry>('journalBox');
  await Hive.openBox<PlacedDecor>('placedDecors');

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

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

            // Automatically redirect based on saved login
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
