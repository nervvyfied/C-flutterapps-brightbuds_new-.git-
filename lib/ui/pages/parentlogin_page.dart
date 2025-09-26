import 'package:brightbuds_new/ui/pages/parent_view/parentNav_page.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_sign_in/google_sign_in.dart'; 
import '../../providers/auth_provider.dart';
import '/data/models/parent_model.dart';
import 'package:flutter_signin_button/flutter_signin_button.dart';

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

  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: ['email'],
      clientId: "953113321611-54jmsk02tdju21s8hd6quaj4529eift4.apps.googleusercontent.com",
  );

  // ---------------- EMAIL AUTH ----------------
  void _handleAuth() async {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    setState(() => isLoading = true);

    try {
      if (isLogin) {
        await auth.loginParent(
          _emailController.text.trim(),
          _passwordController.text.trim(),
        );

        final parent = auth.currentUserModel as ParentUser;
        final childId = parent.childId ?? "";

        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Login successful')));

        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => ParentNavigationShell(
              parentId: parent.uid,
              childId: childId,
            ),
          ),
        );
      } else {
        await auth.signUpParent(
          _nameController.text.trim(),
          _emailController.text.trim(),
          _passwordController.text.trim(),
        );

        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Signup successful')));
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
    setState(() => isLoading = true);

    try {
      final GoogleSignInAccount? account = await _googleSignIn.signIn();
      if (account == null) {
        // user canceled
        setState(() => isLoading = false);
        return;
      }

      final auth = Provider.of<AuthProvider>(context, listen: false);
      await auth.signInWithGoogle();

      final parent = auth.currentUserModel as ParentUser;
      final childId = parent.childId ?? "";

      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Google login successful')));

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => ParentNavigationShell(
            parentId: parent.uid,
            childId: childId,
          ),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      setState(() => isLoading = false);
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
              obscureText: true,
              decoration: const InputDecoration(labelText: "Password"),
            ),
            const SizedBox(height: 20),
            if (isLoading)
              const CircularProgressIndicator()
            else ...[
            
              const SizedBox(height: 10),

                  // ---------------- AUTH BUTTONS ----------------
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
                      backgroundColor: Colors.deepPurple, // Login button color
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 10),

                // -------- GOOGLE SIGN IN BUTTON --------
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
                        Image.asset(
                          'assets/images/g-logo.png',
                          height: 24,
                        ),
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
              child: Text(isLogin
                  ? "Don’t have an account? Signup"
                  : "Already have an account? Login"),
            ),
          ],
        ),
      ),
    );
  }
}
