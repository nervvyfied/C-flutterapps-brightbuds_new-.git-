import 'package:brightbuds_new/ui/pages/parent_view/parentNav_page.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_sign_in/google_sign_in.dart'; 
import '../../data/providers/auth_provider.dart';
import '/data/models/parent_model.dart';

class ParentAuthPage extends StatefulWidget {
  const ParentAuthPage({super.key});

  @override
  State<ParentAuthPage> createState() => _ParentAuthPageState();
}

class _ParentAuthPageState extends State<ParentAuthPage> {
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  bool isLogin = true;
  bool isLoading = false;
  bool _obscurePassword = true;

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
        // Login parent
        await auth.loginParent(
          _emailController.text.trim(),
          _passwordController.text.trim(),
        );

        // Session is saved automatically in AuthProvider
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Login successful')),
        );

        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const ParentNavigationShell()),
        );
      } else {
        // Signup parent
        await auth.signUpParent(
          _nameController.text.trim(),
          _emailController.text.trim(),
          _passwordController.text.trim(),
        );

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Signup successful')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
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

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Google login successful')),
      );

      // Optional: prompt to set email login password
      await _promptSetPassword(auth);

      // Navigate to parent home
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const ParentNavigationShell()),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    } finally {
      setState(() => isLoading = false);
    }
  }

  // --- Prompt user to set password ---
  Future<void> _promptSetPassword(AuthProvider auth) async {
    final _passwordController = TextEditingController();
    bool _obscureDialogPassword = true;

    bool? result = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              title: const Text("Set a password"),
              content: TextField(
                controller: _passwordController,
                obscureText: _obscureDialogPassword,
                decoration: InputDecoration(
                  labelText: "Password for email login (optional)",
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscureDialogPassword
                          ? Icons.visibility_off
                          : Icons.visibility,
                    ),
                    onPressed: () {
                      setDialogState(() {
                        _obscureDialogPassword = !_obscureDialogPassword;
                      });
                    },
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text("Skip"),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text("Save"),
                ),
              ],
            );
          },
        );
      },
    );

    if (result == true && _passwordController.text.trim().isNotEmpty) {
      try {
        await auth.setPasswordForCurrentUser(_passwordController.text.trim());
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Password set successfully")),
        );
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Failed to set password: $e")),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(isLogin ? "Parent Login" : "Parent Signup")),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            if (!isLogin)
              TextField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: "Name"),
              ),
            TextField(
              controller: _emailController,
              decoration: const InputDecoration(labelText: "Email"),
            ),
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
                  label: Text(isLogin ? "Login" : "Signup",
                      style: const TextStyle(fontSize: 16)),
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
                      const Text("Continue with Google",
                          style: TextStyle(fontSize: 16)),
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
    );
  }
}
