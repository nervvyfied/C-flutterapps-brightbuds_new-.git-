import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '/providers/auth_provider.dart';

class ParentLandingPage extends StatelessWidget {
  const ParentLandingPage({super.key});

  @override
  Widget build(BuildContext context) {
    final authProvider = context.watch<AuthProvider>();
    final accessCode = authProvider.currentUserModel?.accessCode ?? 'N/A';

    return Scaffold(
      appBar: AppBar(
        title: const Text("Parent Dashboard"),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              "Welcome, Parent! 🎉",
              style: TextStyle(fontSize: 24),
            ),
            const SizedBox(height: 20),
            Text(
              "Your Child's Access Code:",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 10),
            SelectableText(
              accessCode,
              style: const TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                color: Colors.blueAccent,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
