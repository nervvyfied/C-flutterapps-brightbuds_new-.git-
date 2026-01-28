// ignore_for_file: use_build_context_synchronously, deprecated_member_use

import 'dart:async';

import 'package:brightbuds_new/ui/pages/Therapist_view/TherapistForgotPass_page.dart';
import 'package:brightbuds_new/ui/pages/Therapist_view/TherapistNav_page.dart';
import 'package:brightbuds_new/ui/pages/role_page.dart';
import 'package:firebase_auth/firebase_auth.dart' show FirebaseAuthException;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:provider/provider.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '/data/providers/auth_provider.dart';

class TherapistAuthPage extends StatefulWidget {
  const TherapistAuthPage({super.key});

  @override
  State<TherapistAuthPage> createState() => _TherapistAuthPageState();
}

class _TherapistAuthPageState extends State<TherapistAuthPage> {
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool isLogin = true;
  bool isLoading = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;

  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: ['email'],
    clientId:
        "953113321611-54jmsk02tdju21s8hd6quaj4529eift4.apps.googleusercontent.com",
  );

  // ---------------- AUTH HANDLERS ----------------
  int _failedLoginAttempts = 0;
  bool _isWaiting = false; // Prevent multiple taps during cooldown
  int _cooldownSeconds = 0; // Track countdown

  void _handleAuth() async {
    if (_isWaiting) return; // Prevent login during cooldown

    final auth = context.read<AuthProvider>();
    setState(() => isLoading = true);

    try {
      final email = _emailController.text.trim();
      final password = _passwordController.text.trim();

      if (isLogin) {
        if (email.isEmpty || password.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Please enter both email and password"),
            ),
          );
          return;
        }
        if (!email.contains('@')) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Please enter a valid email")),
          );
          return;
        }

        await auth.loginTherapist(email, password);

        _failedLoginAttempts = 0; // reset failed attempts

        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text("Login successful")));

        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const TherapistNavigationShell()),
        );
      } else {
        // Sign-up
        final name = _nameController.text.trim();
        final confirmPassword = _confirmPasswordController.text.trim();

        if (name.isEmpty || email.isEmpty || password.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("All fields are required")),
          );
          return;
        }
        if (password != confirmPassword) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Passwords do not match")),
          );
          return;
        }

        await auth.signUpTherapist(name, email, password);

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Account created successfully")),
        );

        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const TherapistNavigationShell()),
        );
      }
    } on FirebaseAuthException catch (e) {
      _failedLoginAttempts++;

      String message;
      switch (e.code) {
        case 'user-not-found':
          message = "No account found with this email.";
          break;
        case 'wrong-password':
          message = "Incorrect password. Please try again.";
          break;
        case 'invalid-email':
          message = "Invalid email address.";
          break;
        default:
          message = "Login failed. Please check your credentials.";
      }

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));

      // Cooldown
      if (_failedLoginAttempts >= 5 && !_isWaiting) {
        _isWaiting = true;
        _cooldownSeconds = ((_failedLoginAttempts - 4) * 5).clamp(5, 30);

        Timer.periodic(const Duration(seconds: 1), (timer) {
          setState(() {
            if (_cooldownSeconds > 0) {
              _cooldownSeconds--;
            } else {
              _isWaiting = false;
              timer.cancel();
            }
          });
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Unexpected error: $e")));
    } finally {
      setState(() => isLoading = false);
    }
  }

  Future<void> signInWithGoogle() async {
    final auth = context.read<AuthProvider>();
    setState(() => isLoading = true);

    try {
      final googleUser = await _googleSignIn.signIn();
      if (googleUser == null) return;

      // 🔧 FIX: do NOT assign result (method returns void)
      await auth.signInTherapistWithGoogle();

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Google sign-in successful')),
      );

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const TherapistNavigationShell()),
      );
    } on FirebaseAuthException catch (e) {
      String message;
      switch (e.code) {
        case 'account-exists-with-different-credential':
          message =
              'An account already exists with a different sign-in method for this email.';
          break;
        case 'invalid-credential':
          message = 'Invalid Google credentials. Please try again.';
          break;
        case 'user-disabled':
          message = 'This account has been disabled.';
          break;
        case 'operation-not-allowed':
          message = 'Google sign-in is not enabled for this project.';
          break;
        case 'network-request-failed':
          message = 'Network error. Please check your connection.';
          break;
        default:
          message = 'Unhandled FirebaseAuthException code: ${e.code}';
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Unexpected error: $e')));
    } finally {
      setState(() => isLoading = false);
    }
  }

  void _goToForgotPassword() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const TherapistForgotPassPage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (_) => const ChooseRolePage()),
            );
          },
        ),
      ),
      backgroundColor: Colors.white,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // App logo
              Image.asset('assets/bb2.png', width: 150, height: 150),
              const SizedBox(height: 20),

              Text(
                isLogin ? "Welcome Back, Therapist!" : "Create Your Account",
                style: const TextStyle(
                  fontFamily: 'Fredoka',
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF8657F3),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                isLogin
                    ? "Log in to continue to BrightBuds"
                    : "Join BrightBuds to connect with your child",
                style: const TextStyle(
                  fontFamily: 'Fredoka',
                  fontSize: 15,
                  color: Colors.grey,
                ),
              ),
              const SizedBox(height: 30),

              // Card container
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 24,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 12,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  child: Column(
                    key: ValueKey(isLogin),
                    children: [
                      if (!isLogin) ...[
                        TextField(
                          controller: _nameController,
                          decoration: const InputDecoration(
                            labelText: "Name",
                            prefixIcon: Icon(Icons.person_outline),
                          ),
                        ),
                        const SizedBox(height: 15),
                      ],
                      TextField(
                        controller: _emailController,
                        decoration: const InputDecoration(
                          labelText: "Email",
                          prefixIcon: Icon(Icons.email_outlined),
                        ),
                      ),
                      const SizedBox(height: 15),
                      TextField(
                        controller: _passwordController,
                        obscureText: _obscurePassword,
                        decoration: InputDecoration(
                          labelText: "Password",
                          prefixIcon: const Icon(Icons.lock_outline),
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscurePassword
                                  ? Icons.visibility_off
                                  : Icons.visibility,
                            ),
                            onPressed: () => setState(() {
                              _obscurePassword = !_obscurePassword;
                            }),
                          ),
                        ),
                      ),
                      const SizedBox(height: 15),
                      if (!isLogin)
                        TextField(
                          controller: _confirmPasswordController,
                          obscureText: _obscureConfirmPassword,
                          decoration: InputDecoration(
                            labelText: "Confirm Password",
                            prefixIcon: const Icon(Icons.lock_outline),
                            suffixIcon: IconButton(
                              icon: Icon(
                                _obscureConfirmPassword
                                    ? Icons.visibility_off
                                    : Icons.visibility,
                              ),
                              onPressed: () => setState(() {
                                _obscureConfirmPassword =
                                    !_obscureConfirmPassword;
                              }),
                            ),
                          ),
                        ),
                      if (isLogin)
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            onPressed: _goToForgotPassword,
                            child: const Text(
                              "Forgot Password?",
                              style: TextStyle(
                                color: Color(0xFF8657F3),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      const SizedBox(height: 10),

                      // Auth button
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: ElevatedButton(
                          onPressed: (isLoading || _isWaiting)
                              ? null
                              : _handleAuth,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _isWaiting
                                ? Colors.grey
                                : const Color(0xFF8657F3),
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
                          child: isLoading
                              ? const CircularProgressIndicator(
                                  color: Colors.white,
                                )
                              : _isWaiting
                              ? Text(
                                  "Too many attempts. Wait for $_cooldownSeconds s...",
                                )
                              : Text(isLogin ? "Login" : "Sign Up"),
                        ),
                      ),

                      const SizedBox(height: 15),

                      // Google Sign-In
                      if (!isLogin)
                        SizedBox(
                          width: double.infinity,
                          height: 48,
                          child: ElevatedButton(
                            onPressed: signInWithGoogle,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.white,
                              foregroundColor: Colors.black,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                                side: BorderSide(color: Colors.grey.shade300),
                              ),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Image.asset(
                                  'assets/images/g-logo.png',
                                  height: 22,
                                ),
                                const SizedBox(width: 10),
                                const Text(
                                  "Continue with Google",
                                  style: TextStyle(
                                    fontFamily: 'Fredoka',
                                    fontSize: 15,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 25),

              // Switch mode
              TextButton(
                onPressed: () => setState(() => isLogin = !isLogin),
                child: Text(
                  isLogin
                      ? "Don’t have an account? Sign Up"
                      : "Already have an account? Log In",
                  style: const TextStyle(
                    fontFamily: 'Fredoka',
                    color: Color(0xFF8657F3),
                    fontWeight: FontWeight.w600,
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
