import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:provider/provider.dart';

import 'firebase_options.dart';
import 'data/models/user_model.dart';
import 'data/models/task_model.dart';
import 'providers/auth_provider.dart';
import 'ui/pages/role_page.dart';
import 'ui/pages/parentlogin_page.dart';
import 'ui/pages/childlogin_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Firebase
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // Hive
  await Hive.initFlutter();
  Hive.registerAdapter(UserModelAdapter());
  Hive.registerAdapter(TaskModelAdapter());
  await Hive.openBox<UserModel>('usersBox');
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
        // you can add TaskRepository provider later if needed
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
