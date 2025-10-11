import 'package:brightbuds_new/ui/pages/parent_view/parentForgotPass_page.dart';
import 'package:brightbuds_new/ui/pages/parent_view/parentNav_page.dart';
import 'package:brightbuds_new/ui/pages/parent_view/parentVerification_page.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../../data/providers/auth_provider.dart';
import '/data/models/parent_model.dart';
import 'package:firebase_auth/firebase_auth.dart' hide AuthProvider;

class ParentAuthPage extends StatefulWidget {
  const ParentAuthPage({super.key});

  @override
  State<ParentAuthPage> createState() => _ParentAuthPageState();
}

class _ParentAuthPageState extends State<ParentAuthPage> {
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

  // ---------------- EMAIL AUTH ----------------
  void _handleAuth() async {
    final auth = context.read<AuthProvider>();
    setState(() => isLoading = true);

    try {
      if (isLogin) {
        await auth.loginParent(
          _emailController.text.trim(),
          _passwordController.text.trim(),
        );

        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Login successful')));

        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const ParentNavigationShell()),
        );
      } else {
        final name = _nameController.text.trim();
        final email = _emailController.text.trim();
        final password = _passwordController.text.trim();
        final confirmPassword = _confirmPasswordController.text.trim();

        if (password != confirmPassword) {
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text("Passwords do not match")));
          setState(() => isLoading = false);
          return;
        }

        if (password.length < 6) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text("Password must be at least 6 characters")));
          setState(() => isLoading = false);
          return;
        }

        try {
          await auth.signUpParent(name, email, password);

          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => VerifyEmailScreen(email: email),
            ),
          );
        } catch (e) {
          if (e.toString().contains("verification")) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (_) => VerifyEmailScreen(email: email),
              ),
            );
          } else {
            ScaffoldMessenger.of(context)
                .showSnackBar(SnackBar(content: Text('Error: $e')));
          }
        }
      }
    } catch (e) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      setState(() => isLoading = false);
    }
  }

  // ---------------- GOOGLE SIGN-IN ----------------
  void _handleGoogleSignIn() async {
    final auth = context.read<AuthProvider>();
    setState(() => isLoading = true);

    try {
      await auth.signInWithGoogle();

      // If user already exists, bypass password
      if (auth.currentUserModel != null && auth.currentUserModel is ParentUser) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const ParentNavigationShell()),
        );
      } else {
        await _showSetPasswordDialog();
      }
    } catch (e) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      setState(() => isLoading = false);
    }
  }

  Future<void> _showSetPasswordDialog() async {
    final auth = context.read<AuthProvider>();
    final passwordController = TextEditingController();
    final confirmPasswordController = TextEditingController();
    bool obscurePassword = true;
    bool obscureConfirm = true;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(builder: (context, setState) {
          return AlertDialog(
            title: const Text("Set a password"),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: passwordController,
                  obscureText: obscurePassword,
                  decoration: InputDecoration(
                    labelText: "Password",
                    suffixIcon: IconButton(
                      icon: Icon(
                          obscurePassword ? Icons.visibility_off : Icons.visibility),
                      onPressed: () {
                        setState(() => obscurePassword = !obscurePassword);
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: confirmPasswordController,
                  obscureText: obscureConfirm,
                  decoration: InputDecoration(
                    labelText: "Confirm Password",
                    suffixIcon: IconButton(
                      icon: Icon(obscureConfirm
                          ? Icons.visibility_off
                          : Icons.visibility),
                      onPressed: () {
                        setState(() => obscureConfirm = !obscureConfirm);
                      },
                    ),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () async {
                  final pass = passwordController.text.trim();
                  final confirmPass = confirmPasswordController.text.trim();

                  if (pass.isEmpty || confirmPass.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text("Enter a password")));
                    return;
                  }

                  if (pass != confirmPass) {
                    ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text("Passwords do not match")));
                    return;
                  }

                  if (pass.length < 6) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                        content: Text("Password must be at least 6 characters")));
                    return;
                  }

                  try {
                    await auth.setPasswordForCurrentUser(pass);
                    Navigator.of(context).pop(); // Close dialog
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const ParentNavigationShell()),
                    );
                  } catch (e) {
                    ScaffoldMessenger.of(context)
                        .showSnackBar(SnackBar(content: Text("Error: $e")));
                  }
                },
                child: const Text("Save"),
              ),
            ],
          );
        });
      },
    );
  }

  // ---------------- NAVIGATE TO FORGOT PASSWORD PAGE ----------------
  void _goToForgotPassword() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ParentForgotPassPage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(isLogin ? "Parent Login" : "Parent Signup")),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: SingleChildScrollView(
          child: Column(
            children: [
              if (!isLogin)
                TextField(
                  controller: _nameController,
                  decoration: const InputDecoration(labelText: "Name"),
                ),
              const SizedBox(height: 10),
              TextField(
                controller: _emailController,
                decoration: const InputDecoration(labelText: "Email"),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _passwordController,
                obscureText: _obscurePassword,
                decoration: InputDecoration(
                  labelText: "Password",
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscurePassword ? Icons.visibility_off : Icons.visibility,
                    ),
                    onPressed: () {
                      setState(() {
                        _obscurePassword = !_obscurePassword;
                      });
                    },
                  ),
                ),
              ),
              const SizedBox(height: 10),
              if (!isLogin)
                TextField(
                  controller: _confirmPasswordController,
                  obscureText: _obscureConfirmPassword,
                  decoration: InputDecoration(
                    labelText: "Confirm Password",
                    suffixIcon: IconButton(
                      icon: Icon(_obscureConfirmPassword
                          ? Icons.visibility_off
                          : Icons.visibility),
                      onPressed: () {
                        setState(() {
                          _obscureConfirmPassword = !_obscureConfirmPassword;
                        });
                      },
                    ),
                  ),
                ),
              const SizedBox(height: 10),

              // Forgot password in login mode
              if (isLogin)
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: _goToForgotPassword,
                    child: const Text(
                      "Forgot Password?",
                      style: TextStyle(color: Colors.deepPurple),
                    ),
                  ),
                ),

              const SizedBox(height: 20),
              if (isLoading)
                const CircularProgressIndicator()
              else ...[
                SizedBox(
                  width: double.infinity,
                  height: 45,
                  child: ElevatedButton.icon(
                    onPressed: _handleAuth,
                    icon: const Icon(Icons.login, size: 20, color: Colors.white),
                    label: Text(
                      isLogin ? "Login" : "Signup",
                      style: const TextStyle(fontSize: 16),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.deepPurple,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  height: 45,
                  child: ElevatedButton(
                    onPressed: _handleGoogleSignIn,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                        side: BorderSide(color: Colors.grey.shade300),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Image.asset('assets/images/g-logo.png', height: 24),
                        const SizedBox(width: 8),
                        const Text(
                          "Continue with Google",
                          style: TextStyle(fontSize: 16),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 10),
              TextButton(
                onPressed: () => setState(() => isLogin = !isLogin),
                child: Text(
                  isLogin
                      ? "Don’t have an account? Signup"
                      : "Already have an account? Login",
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
