import 'package:flutter/material.dart';

class ChildLandingPage extends StatelessWidget {
  const ChildLandingPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Child Dashboard"),
      ),
      body: const Center(
        child: Text(
          "Welcome, BrightBud 🌟",
          style: TextStyle(fontSize: 24),
        ),
      ),
    );
  }
}
