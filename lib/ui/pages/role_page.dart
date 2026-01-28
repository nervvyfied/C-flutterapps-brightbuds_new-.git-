import 'package:brightbuds_new/data/providers/auth_provider.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

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

    // Defer everything until after first build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkExistingSession();
    });
  }

  Future<void> _checkExistingSession() async {
    await Future.delayed(const Duration(milliseconds: 300));

    if (!mounted) return;

    final auth = context.read<AuthProvider>();

    String? route;

    if (auth.isLoggedIn) {
      if (auth.isParent) {
        route = '/parentHome';
      } else if (auth.isChild) {
        route = '/childHome';
      } else if (auth.isTherapist) {
        route = '/therapistHome';
      }
    }

    if (!mounted) return;

    if (route != null) {
      Navigator.of(context).pushReplacementNamed(route);
    } else {
      setState(() => _checkingSession = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_checkingSession) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Image.asset('assets/bb2.png', width: 180, height: 180),
                const SizedBox(height: 20),

                _roleButton(
                  color: const Color(0xFFFECE00),
                  label: 'Parent',
                  route: '/parentAuth',
                ),
                const SizedBox(height: 20),

                _roleButton(
                  color: const Color(0xFF8657F3),
                  label: 'Child',
                  route: '/childAuth',
                ),
                const SizedBox(height: 20),

                _roleButton(
                  color: const Color(0xFF2CC66D),
                  label: 'Therapist',
                  route: '/therapistAuth',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _roleButton({
    required Color color,
    required String label,
    required String route,
  }) {
    return SizedBox(
      width: 220,
      height: 45,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
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
          Navigator.pushReplacementNamed(context, route);
        },
        child: Text(label),
      ),
    );
  }
}
