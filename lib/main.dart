import 'package:brightbuds_new/data/models/child_model.dart';
import 'package:brightbuds_new/data/models/parent_model.dart';
import 'package:brightbuds_new/data/models/task_model.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:provider/provider.dart';

import 'firebase_options.dart';
import 'providers/auth_provider.dart';
import 'providers/task_provider.dart';
import 'ui/pages/role_page.dart';
import 'ui/pages/parentlogin_page.dart';
import 'ui/pages/childlogin_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // Initialize Hive
  await Hive.initFlutter();

  // ---------------- Register Adapters ----------------
  // Only register once per typeId, otherwise HiveError occurs
  if (!Hive.isAdapterRegistered(ParentUserAdapter().typeId)) {
    Hive.registerAdapter(ParentUserAdapter());
  }
  if (!Hive.isAdapterRegistered(ChildUserAdapter().typeId)) {
    Hive.registerAdapter(ChildUserAdapter());
  }
  if (!Hive.isAdapterRegistered(TaskModelAdapter().typeId)) {
    Hive.registerAdapter(TaskModelAdapter());
  }

  // ---------------- Open Boxes ----------------
  await Hive.openBox<ParentUser>('parentBox');
  await Hive.openBox<ChildUser>('childBox');
  await Hive.openBox<TaskModel>('tasksBox');

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => TaskProvider()),
        // Add other providers here (TaskRepository, UserRepository) if needed
      ],
      child: MaterialApp(
        title: 'BrightBuds',
        theme: ThemeData(primarySwatch: Colors.blue),
        home: const ChooseRolePage(),
        routes: {
          '/parentAuth': (context) => const ParentAuthPage(),
          '/childAuth': (context) => const ChildAuthPage(),
        },
      ),
    );
  }
}
