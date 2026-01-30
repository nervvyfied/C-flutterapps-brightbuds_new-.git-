import 'dart:async';
import 'package:brightbuds_new/ui/pages/therapistlogin_page.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import 'package:brightbuds_new/ui/pages/therapist_view/therapistNav_page.dart';
import '../../../data/models/therapist_model.dart';
import '/data/providers/auth_provider.dart' as app_auth;

class VerifyEmailScreen extends StatefulWidget {
  final String email;
  const VerifyEmailScreen({super.key, required this.email});

  @override
  State<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends State<VerifyEmailScreen> {
  bool isEmailVerified = false;
  bool canResendEmail = true;
  Timer? timer;

  @override
  void initState() {
    super.initState();
    _checkEmailVerification();
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  Future<void> _checkEmailVerification() async {
    print("=== VERIFICATION PAGE: Checking email verification ===");

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      print("No user found - going to login");
      _redirectToLogin();
      return;
    }

    // 🔥 CRITICAL: Check if email is actually verified
    isEmailVerified = user.emailVerified;
    print("User email verified status: $isEmailVerified");
    print("User email: ${user.email}");

    if (isEmailVerified) {
      // Email is verified - proceed to update Firestore and go to dashboard
      print("Email verified! Processing to dashboard...");
      await _processVerifiedAccount(user);
    } else {
      // Email NOT verified - start checking periodically
      print("Email NOT verified - starting timer to check every 3 seconds");
      timer = Timer.periodic(
        const Duration(seconds: 3),
        (_) => _verifyAndCheck(),
      );
    }

    setState(() {});
  }

  Future<void> _verifyAndCheck() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      timer?.cancel();
      _redirectToLogin();
      return;
    }

    try {
      // 🔥 IMPORTANT: Reload user to get latest verification status
      await user.reload();
      final updatedUser = FirebaseAuth.instance.currentUser;

      if (updatedUser != null && updatedUser.emailVerified) {
        print("✅ Email verification DETECTED!");
        setState(() => isEmailVerified = true);
        timer?.cancel();

        // Process the verified account
        await _processVerifiedAccount(updatedUser);
      }
    } catch (e) {
      print("Error checking verification: $e");
    }
  }

  Future<void> _processVerifiedAccount(User user) async {
    print("Processing verified account for user: ${user.uid}");

    try {
      // 1. Update Firestore to mark as verified
      await FirebaseFirestore.instance
          .collection('therapists')
          .doc(user.uid)
          .update({
            'isVerified': true,
            'emailVerified': true,
            'verifiedAt': FieldValue.serverTimestamp(),
          });

      // 2. Load therapist data
      final therapistDoc = await FirebaseFirestore.instance
          .collection('therapists')
          .doc(user.uid)
          .get();

      if (therapistDoc.exists) {
        final therapist = TherapistUser.fromMap(
          therapistDoc.data()!,
          therapistDoc.id,
        );
        final authProvider = context.read<app_auth.AuthProvider>();
        await authProvider.updateCurrentUserModel(therapist);
      }

      // 3. Go to dashboard
      if (mounted) {
        print("✅ Verification complete - navigating to dashboard");
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const TherapistNavigationShell()),
        );
      }
    } catch (e) {
      print("Error processing verified account: $e");
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Error: $e")));
      }
    }
  }

  Future<void> sendVerificationEmail() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _redirectToLogin();
      return;
    }

    try {
      setState(() => canResendEmail = false);

      print("Sending verification email to: ${user.email}");
      await user.sendEmailVerification();

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ Verification email sent! Check your inbox.'),
        ),
      );

      // Start checking for verification
      timer = Timer.periodic(
        const Duration(seconds: 3),
        (_) => _verifyAndCheck(),
      );

      // Enable resend after 30 seconds
      await Future.delayed(const Duration(seconds: 30));
      if (mounted) setState(() => canResendEmail = true);
    } on FirebaseAuthException catch (e) {
      String message = e.code == 'too-many-requests'
          ? '⚠️ Too many requests. Please wait a few minutes.'
          : '❌ Failed to send verification email: ${e.message}';
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
      if (mounted) setState(() => canResendEmail = true);
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('❌ Error: $e')));
      if (mounted) setState(() => canResendEmail = true);
    }
  }

  void _redirectToLogin() {
    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const TherapistAuthPage()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Verify Your Email"),
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Icon
              Icon(
                isEmailVerified ? Icons.verified : Icons.mark_email_read,
                size: 90,
                color: isEmailVerified ? Colors.green : Colors.deepPurple,
              ),
              const SizedBox(height: 20),

              // Title
              Text(
                isEmailVerified ? "Email Verified!" : "Verify Your Email",
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 10),

              // Email display
              Text(
                widget.email,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w500,
                  color: Colors.deepPurple,
                ),
              ),
              const SizedBox(height: 20),

              // Message
              Text(
                isEmailVerified
                    ? "Your email has been verified! Processing your account..."
                    : "Please check your inbox and click the verification link.\n\n"
                          "After clicking the link, this page will automatically update.",
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 15),
              ),
              const SizedBox(height: 30),

              if (!isEmailVerified) ...[
                // Resend Email button
                SizedBox(
                  width: 220,
                  height: 45,
                  child: ElevatedButton.icon(
                    onPressed: canResendEmail ? sendVerificationEmail : null,
                    icon: const Icon(Icons.email),
                    label: const Text("Resend Verification"),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.deepPurple,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      textStyle: const TextStyle(
                        fontFamily: 'Fredoka',
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 15),

                // Manual check button
                SizedBox(
                  width: 220,
                  height: 45,
                  child: ElevatedButton.icon(
                    onPressed: _checkEmailVerification,
                    icon: const Icon(Icons.refresh),
                    label: const Text("Check Verification"),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 15),

                // Status indicator
                if (!isEmailVerified)
                  const Column(
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 10),
                      Text(
                        "Waiting for email verification...",
                        style: TextStyle(fontSize: 14, color: Colors.grey),
                      ),
                    ],
                  ),
              ],

              if (isEmailVerified)
                const Column(
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 10),
                    Text(
                      "Setting up your account...",
                      style: TextStyle(fontSize: 14, color: Colors.grey),
                    ),
                  ],
                ),

              const SizedBox(height: 30),

              // Back to Login button
              TextButton(
                onPressed: () async {
                  await FirebaseAuth.instance.signOut();
                  _redirectToLogin();
                },
                child: const Text(
                  "Back to Login",
                  style: TextStyle(
                    fontSize: 15,
                    color: Colors.deepPurple,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
