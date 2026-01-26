import 'package:brightbuds_new/ui/pages/parent_view/parentNav_page.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '/data/providers/auth_provider.dart';
import 'package:brightbuds_new/ui/pages/role_page.dart';
import 'package:brightbuds_new/ui/pages/therapist_view/therapistNav_page.dart';
import 'package:brightbuds_new/ui/pages/child_view/childNav_page.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();

    // Fade-in animation controller
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    );

    _animation = Tween<double>(begin: 0.0, end: 1.0).animate(_controller);

    // Start fade-in
    _controller.forward();

    // After 3 seconds, navigate based on auth
    Future.delayed(const Duration(seconds: 3), () {
      final auth = context.read<AuthProvider>();
      Widget nextPage;
      if (auth.isParent) {
        nextPage = const ParentNavigationShell();
      } else if (auth.isChild) {
        nextPage = const ChildNavigationShell();
      } else if (auth.isTherapist) {
        nextPage = const TherapistNavigationShell();
      } else {
        nextPage = const ChooseRolePage();
      }

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => nextPage),
      );
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white, // You can change the background color
      body: Center(
        child: FadeTransition(
          opacity: _animation,
          child: Image.asset('assets/bb3.png', width: 150, height: 150),
        ),
      ),
    );
  }
}
