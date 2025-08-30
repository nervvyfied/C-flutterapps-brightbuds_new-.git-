import 'package:brightbuds_new/ui/pages/testchild.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '/providers/auth_provider.dart';

class ChildAuthPage extends StatefulWidget {
  const ChildAuthPage({super.key});

  @override
  State<ChildAuthPage> createState() => _ChildAuthPageState();
}

class _ChildAuthPageState extends State<ChildAuthPage> {
  final _codeController = TextEditingController();
  final _nameController = TextEditingController(); // Optional: child name if needed
  bool isLoading = false;

  void _handleChildLogin() async {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final code = _codeController.text.trim();
    final childName = _nameController.text.trim();

    setState(() => isLoading = true);

    try {
      // Attempt to join child with code
      await auth.childJoin(code, childName);

      if (auth.currentUserModel != null) {
        // Successful login
        Navigator.pushReplacement(
  context,
  MaterialPageRoute(builder: (context) => const ChildLandingPage()),
);
      } else {
        // Failed login
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Invalid code')),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Child Login")),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: _codeController,
              decoration: const InputDecoration(labelText: "Enter Access Code"),
            ),
            const SizedBox(height: 10),
            // Optional: input for child's name if needed
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: "Child Name"),
            ),
            const SizedBox(height: 20),
            isLoading
                ? const CircularProgressIndicator()
                : ElevatedButton(
                    onPressed: _handleChildLogin,
                    child: const Text("Login"),
                  ),
          ],
        ),
      ),
    );
  }
}
