import 'package:flutter/material.dart';

class ChooseRolePage extends StatelessWidget {
  const ChooseRolePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Who will use BrightBuds?")),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ElevatedButton(
              onPressed: () => Navigator.pushNamed(context, '/parentAuth'),
              child: const Text("I am a Parent"),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pushNamed(context, '/childAuth'),
              child: const Text("I am a Child"),
            ),
          ],
        ),
      ),
    );
  }
}
