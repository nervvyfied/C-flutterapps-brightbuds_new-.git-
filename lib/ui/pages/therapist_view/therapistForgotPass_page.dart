import 'package:brightbuds_new/ui/pages/Therapistlogin_page.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

class TherapistForgotPassPage extends StatefulWidget {
  const TherapistForgotPassPage({super.key});

  @override
  State<TherapistForgotPassPage> createState() => _TherapistForgotPassPageState();
}

class _TherapistForgotPassPageState extends State<TherapistForgotPassPage> {
  final _emailController = TextEditingController();
  bool isLoading = false;
  bool emailSent = false;

  Future<void> _sendResetEmail() async {
    final email = _emailController.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please enter a valid email.")),
      );
      return;
    }

    setState(() => isLoading = true);

    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      setState(() => emailSent = true);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Failed to send reset email: $e")),
      );
    } finally {
      setState(() => isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F4FE),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32.0),
            child: SingleChildScrollView(
              child: emailSent
                  ? Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.mark_email_read_rounded,
                          size: 100,
                          color: Color(0xFF8657F3),
                        ),
                        const SizedBox(height: 20),
                        const Text(
                          "Password Reset Link Sent!",
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontFamily: 'Fredoka',
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF8657F3),
                          ),
                        ),
                        const SizedBox(height: 10),
                        const Text(
                          "Check your email inbox or spam folder and follow the link to set a new password.",
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontFamily: 'Fredoka',
                            fontSize: 14,
                            color: Colors.black54,
                          ),
                        ),
                        const SizedBox(height: 30),
                        SizedBox(
                          width: double.infinity,
                          height: 50,
                          child: ElevatedButton(
                            onPressed: () {
                              Navigator.pushAndRemoveUntil(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const TherapistAuthPage(),
                                ),
                                (route) => false,
                              );
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF8657F3),
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                              textStyle: const TextStyle(
                                fontFamily: 'Fredoka',
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            child: const Text("Back to Login"),
                          ),
                        ),
                      ],
                    )
                  : Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Image.asset(
                          'assets/bb3.png',
                          width: 140,
                          height: 140,
                        ),
                        const SizedBox(height: 20),
                        const Text(
                          "Forgot Password?",
                          style: TextStyle(
                            fontFamily: 'Fredoka',
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF8657F3),
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          "Enter your email below to receive a password reset link.",
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontFamily: 'Fredoka',
                            fontSize: 14,
                            color: Colors.black54,
                          ),
                        ),
                        const SizedBox(height: 30),
                        TextField(
                          controller: _emailController,
                          keyboardType: TextInputType.emailAddress,
                          textAlign: TextAlign.center,
                          decoration: InputDecoration(
                            filled: true,
                            fillColor: Colors.white,
                            hintText: "Enter your email",
                            hintStyle: const TextStyle(
                              fontFamily: 'Fredoka',
                              color: Colors.black38,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(
                                color: Color(0xFF8657F3),
                                width: 1.5,
                              ),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(
                                color: Color(0xFF8657F3),
                                width: 1.5,
                              ),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              vertical: 16,
                              horizontal: 12,
                            ),
                          ),
                          style: const TextStyle(
                            fontFamily: 'Fredoka',
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 30),
                        isLoading
                            ? const CircularProgressIndicator()
                            : SizedBox(
                                width: double.infinity,
                                height: 50,
                                child: ElevatedButton(
                                  onPressed: _sendResetEmail,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF8657F3),
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                    textStyle: const TextStyle(
                                      fontFamily: 'Fredoka',
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  child: const Text("Send Reset Link"),
                                ),
                              ),
                        const SizedBox(height: 20),
                        TextButton(
                          onPressed: () {
                            Navigator.pop(context);
                          },
                          child: const Text(
                            "Back to Login",
                            style: TextStyle(
                              fontFamily: 'Fredoka',
                              fontSize: 14,
                              color: Colors.black54,
                              decoration: TextDecoration.underline,
                            ),
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
