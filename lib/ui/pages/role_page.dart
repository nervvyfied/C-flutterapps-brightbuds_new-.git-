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
    await Future.delayed(const Duration(milliseconds: 300));

    if (auth.isParent && auth.isLoggedIn) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Navigator.pushReplacementNamed(context, '/parentHome');
      });
    } else if (auth.isChild && auth.isLoggedIn) {
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
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
    // Move logo higher
    Image.asset(
      'assets/bb2.png',
      width: 180,
      height: 180,
    ),
    const SizedBox(height: 20),
    

    // Parent Button
    SizedBox(
      width: 220,
      height: 45,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFFFECE00),
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(
            fontFamily: 'Fredoka',
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        onPressed: () {
          Navigator.pushReplacementNamed(context, '/parentAuth');
        },
        child: const Text("Parent Login/Sign Up"),
      ),
    ),
    const SizedBox(height: 20),

    // Child Button
    SizedBox(
      width: 220,
      height: 45,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF8657F3),
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(
            fontFamily: 'Fredoka',
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        onPressed: () {
          Navigator.pushReplacementNamed(context, '/childAuth');
        },
        child: const Text("Enter Access Code"),
      ),
    ),

    const SizedBox(height: 40), // extra bottom padding
  ],
            ),
          ),
        ),
      ),
    );
  }
}
