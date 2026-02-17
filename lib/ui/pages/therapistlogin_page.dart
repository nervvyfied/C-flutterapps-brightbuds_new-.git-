// ignore_for_file: use_build_context_synchronously, deprecated_member_use

import 'dart:async';
import 'package:brightbuds_new/data/models/therapist_model.dart';
import 'package:brightbuds_new/ui/pages/Therapist_view/TherapistForgotPass_page.dart';
import 'package:brightbuds_new/ui/pages/Therapist_view/TherapistNav_page.dart';
import 'package:brightbuds_new/ui/pages/Therapist_view/TherapistVerification_page.dart';
import 'package:brightbuds_new/ui/pages/role_page.dart';
import 'package:firebase_auth/firebase_auth.dart'
    show FirebaseAuthException, GoogleAuthProvider, FirebaseAuth;
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:provider/provider.dart';
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

  int _failedLoginAttempts = 0;
  bool _isWaiting = false;
  int _cooldownSeconds = 0;

  void _showSnackBar(String message, {Color? color}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: color ?? Colors.red),
    );
  }

  void _handleAuth() async {
    if (_isWaiting) return;

    final auth = context.read<AuthProvider>();
    setState(() => isLoading = true);

    try {
      if (isLogin) {
        // Login
        final email = _emailController.text.trim();
        final password = _passwordController.text.trim();

        // Add validation
        if (email.isEmpty || password.isEmpty) {
          _showSnackBar("Please fill in all fields");
          return;
        }

        await auth.loginTherapist(email, password);

        // Get therapist data
        final therapist = auth.currentUserModel as TherapistUser?;

        // Check if verified
        if (therapist != null && therapist.isVerified == false) {
          // Not verified - go to verification page
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => VerifyEmailScreen(email: email)),
          );
          return;
        }

        // Verified - go to dashboard
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const TherapistNavigationShell()),
        );
      } else {
        // Sign-up
        final name = _nameController.text.trim();
        final email = _emailController.text.trim();
        final password = _passwordController.text.trim();
        final confirmPassword = _confirmPasswordController.text.trim();

        // Add validation
        if (name.isEmpty ||
            email.isEmpty ||
            password.isEmpty ||
            confirmPassword.isEmpty) {
          _showSnackBar("Please fill in all fields");
          return;
        }

        if (password != confirmPassword) {
          _showSnackBar("Passwords do not match");
          return;
        }

        if (password.length < 6) {
          _showSnackBar("Password must be at least 6 characters");
          return;
        }

        // Call sign-up method from auth provider
        await auth.signUpTherapist(name, email, password);

        // After successful sign-up, go to verification page
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => VerifyEmailScreen(email: email)),
        );
      }
    } catch (e) {
      _showSnackBar("Error: ${e.toString()}");
    } finally {
      if (mounted) {
        setState(() => isLoading = false);
      }
    }
  }

  Future<void> signInWithGoogle() async {
    final auth = context.read<AuthProvider>();
    setState(() => isLoading = true);

    try {
      final googleUser = await _googleSignIn.signIn();
      if (googleUser == null) {
        _showSnackBar("Google sign-in cancelled.");
        return;
      }

      final googleAuth = await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      final userCredential = await FirebaseAuth.instance.signInWithCredential(
        credential,
      );
      final user = userCredential.user;

      if (!mounted) return;

      if (user != null) {
        if (userCredential.additionalUserInfo?.isNewUser ?? false) {
          _showSnackBar("Google sign-up successful!", color: Colors.green);

          Future.microtask(() {
            if (!mounted) return;
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (_) => VerifyEmailScreen(email: user.email ?? ''),
              ),
            );
          });
        } else {
          _showSnackBar("Google sign-in successful!", color: Colors.green);

          Future.microtask(() {
            if (!mounted) return;
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (_) => TherapistNavigationShell()),
            );
          });
        }
      }
    } on FirebaseAuthException catch (e) {
      String message = switch (e.code) {
        'account-exists-with-different-credential' =>
          'An account already exists with a different sign-in method.',
        'invalid-credential' => 'Invalid Google credentials.',
        'user-disabled' => 'This account has been disabled.',
        'operation-not-allowed' => 'Google sign-in not enabled.',
        'network-request-failed' => 'Network error. Check your connection.',
        _ => 'Authentication error: ${e.message}',
      };
      _showSnackBar(message);
    } catch (e) {
      _showSnackBar("Unexpected error: $e");
    } finally {
      if (!mounted) return;
      setState(() => isLoading = false);
    }
  }

  void _goToForgotPassword() {
    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const TherapistForgotPassPage()),
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (!mounted) return;
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
                      if (!isLogin)
                        TextField(
                          controller: _nameController,
                          decoration: const InputDecoration(
                            labelText: "Name",
                            prefixIcon: Icon(Icons.person_outline),
                          ),
                        ),
                      if (!isLogin) const SizedBox(height: 15),

                      TextField(
                        controller: _emailController,
                        decoration: const InputDecoration(
                          labelText: "Email",
                          prefixIcon: Icon(Icons.email_outlined),
                        ),
                      ),

                      const SizedBox(height: 15),

                      // Login: Only password field
                      if (isLogin)
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
                              onPressed: () => setState(
                                () => _obscurePassword = !_obscurePassword,
                              ),
                            ),
                          ),
                        ),

                      // Sign-up: Password and Confirm Password
                      if (!isLogin)
                        Column(
                          children: [
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
                                  onPressed: () => setState(
                                    () => _obscurePassword = !_obscurePassword,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 15),
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
                                  onPressed: () => setState(
                                    () => _obscureConfirmPassword =
                                        !_obscureConfirmPassword,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),

                      const SizedBox(height: 15),

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
                                  "Too many attempts. Wait $_cooldownSeconds s...",
                                )
                              : Text(isLogin ? "Login" : "Sign Up"),
                        ),
                      ),

                      const SizedBox(height: 15),
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: ElevatedButton(
                          onPressed: (isLoading || _isWaiting)
                              ? null
                              : signInWithGoogle,
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
              TextButton(
                onPressed: () => setState(() => isLogin = !isLogin),
                child: Text(
                  isLogin
                      ? "Don't have an account? Sign Up"
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
