import 'package:brightbuds_new/data/models/child_model.dart';
import 'package:brightbuds_new/providers/auth_provider.dart';
import 'package:brightbuds_new/ui/pages/child_view/childNav_page.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class ChildAuthPage extends StatefulWidget {
  const ChildAuthPage({super.key});

  @override
  State<ChildAuthPage> createState() => _ChildAuthPageState();
}

class _ChildAuthPageState extends State<ChildAuthPage> {
  final _codeController = TextEditingController();
  bool _loading = false;

  void _loginChild() async {
  final code = _codeController.text.trim();
  if (code.isEmpty) return;

  setState(() => _loading = true);

  try {
    final authProvider = context.read<AuthProvider>();
    await authProvider.loginChild(code);

    final child = authProvider.currentUserModel as ChildUser;

    Navigator.pushReplacement(
  context,
  MaterialPageRoute(
    builder: (_) => ChildNavigationShell(
      childId: child.cid,
      parentId: child.parentUid,
      childName: child.name,
    ),
  ),
);

  } catch (e) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(e.toString())));
  } finally {
    setState(() => _loading = false);
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
              decoration: const InputDecoration(
                  labelText: "Enter Access Code", border: OutlineInputBorder()),
            ),
            const SizedBox(height: 20),
            _loading
                ? const CircularProgressIndicator()
                : ElevatedButton(
                    onPressed: _loginChild, child: const Text("Login")),
          ],
        ),
      ),
    );
  }
}
