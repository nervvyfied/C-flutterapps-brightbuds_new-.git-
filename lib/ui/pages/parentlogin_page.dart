import 'package:brightbuds_new/ui/pages/parent_view/parentNav_page.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(isLogin ? "Parent Login" : "Parent Signup")),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            if (!isLogin) // only show on signup
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
            isLoading
                ? const CircularProgressIndicator()
                : ElevatedButton(
                    onPressed: _handleAuth,
                    child: Text(isLogin ? "Login" : "Signup"),
                  ),
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
