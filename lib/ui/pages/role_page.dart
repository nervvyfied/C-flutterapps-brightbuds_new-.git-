import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '/data/providers/auth_provider.dart';

class ChooseRolePage extends StatefulWidget {
  const ChooseRolePage({super.key});

  @override
  State<ChooseRolePage> createState() => _ChooseRolePageState();
}

class _ChooseRolePageState extends State<ChooseRolePage> {
  bool _checkingSession = true;

  @override
  void initState() {
    super.initState();
    _checkExistingSession();
  }

  Future<void> _checkExistingSession() async {
    final auth = context.read<AuthProvider>();

    // Wait a bit to ensure provider restores session
    await Future.delayed(const Duration(milliseconds: 300));

    if (auth.isParent && auth.isLoggedIn) {
      // Parent already logged in → go to parent home
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Navigator.pushReplacementNamed(context, '/parentHome');
      });
    } else if (auth.isChild && auth.isLoggedIn) {
      // Child already logged in → go to child home
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Navigator.pushReplacementNamed(context, '/childHome');
      });
    } else {
      setState(() => _checkingSession = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_checkingSession) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text("Who will use BrightBuds?")),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ElevatedButton(
              onPressed: () {
                Navigator.pushReplacementNamed(context, '/parentAuth');
              },
              child: const Text("I am a Parent"),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () {
                Navigator.pushReplacementNamed(context, '/childAuth');
              },
              child: const Text("I am a Child"),
            ),
          ],
        ),
      ),
    );
  }
}
