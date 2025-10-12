import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import 'package:brightbuds_new/ui/pages/parent_view/parentNav_page.dart';
import '/data/models/parent_model.dart';
import '/data/providers/auth_provider.dart'
    as app_auth; // alias to avoid conflict

class VerifyEmailScreen extends StatefulWidget {
  final String email;
  const VerifyEmailScreen({super.key, required this.email});

  @override
  State<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends State<VerifyEmailScreen> {
  bool isEmailVerified = false;
  bool canResendEmail = true; // start true, only disables after sending
  Timer? timer;

  @override
  void initState() {
    super.initState();

    isEmailVerified = FirebaseAuth.instance.currentUser?.emailVerified ?? false;

    // Start periodic verification check
    if (!isEmailVerified) {
      timer = Timer.periodic(
        const Duration(seconds: 3),
        (_) => _checkEmailVerified(),
      );
    }
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  Future<void> _checkEmailVerified() async {
    await FirebaseAuth.instance.currentUser?.reload();
    final user = FirebaseAuth.instance.currentUser;

    if (user != null && user.emailVerified) {
      setState(() => isEmailVerified = true);
      timer?.cancel();

      // Load Parent Data
      final parentDoc = await FirebaseFirestore.instance
          .collection('parents')
          .doc(user.uid)
          .get();

      if (parentDoc.exists) {
        final parent = ParentUser.fromMap(parentDoc.data()!, parentDoc.id);
        final authProvider = context.read<app_auth.AuthProvider>();
        await authProvider.updateCurrentUserModel(parent);
      }

      // Navigate to dashboard
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const ParentNavigationShell()),
        );
      }
    }
  }

  Future<void> sendVerificationEmail() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      // Disable resend button immediately
      setState(() => canResendEmail = false);

      await user.sendEmailVerification();

      // Enable button after cooldown
      await Future.delayed(const Duration(seconds: 30));
      if (mounted) setState(() => canResendEmail = true);
    } on FirebaseAuthException catch (e) {
      if (e.code == 'too-many-requests') {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Too many requests. Please wait a few minutes before trying again.',
            ),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to send verification email: ${e.message}')),
        );
      }
      if (mounted) setState(() => canResendEmail = true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to send verification email: $e')),
        );
        setState(() => canResendEmail = true);
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Verify Your Email')),
        body: Padding(
          padding: const EdgeInsets.all(20),
          child: Center(
            child: isEmailVerified
                ? const CircularProgressIndicator()
                : Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text(
                        "A verification email has been sent to:",
                        style: TextStyle(fontSize: 16),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        widget.email,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 20),
                      const Text(
                        "Please check your email inbox or spam.\nOnce verified, this screen will automatically continue.",
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 30),
                      ElevatedButton.icon(
                        onPressed: canResendEmail ? sendVerificationEmail : null,
                        icon: const Icon(Icons.email),
                        label: const Text("Resend Email"),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.deepPurple,
                          foregroundColor: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextButton(
                        onPressed: () async {
                          await FirebaseAuth.instance.signOut();
                          if (mounted) Navigator.pop(context);
                        },
                        child: const Text("Back to Login"),
                      ),
                    ],
                  ),
          ),
        ),
      );

}
