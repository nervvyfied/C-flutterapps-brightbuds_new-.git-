import 'package:brightbuds_new/aquarium/providers/decor_provider.dart';
import 'package:brightbuds_new/aquarium/providers/fish_provider.dart';
import 'package:brightbuds_new/data/models/child_model.dart';
import 'package:brightbuds_new/data/providers/auth_provider.dart';
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

  Future<void> _loginChild() async {
    final code = _codeController.text.trim();
    if (code.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please enter your access code")),
      );
      return;
    }

    setState(() => _loading = true);

    try {
      final authProvider = context.read<AuthProvider>();
      await authProvider.loginChild(code);
      await authProvider.saveFcmToken();

      final child = authProvider.currentUserModel as ChildUser;

      final fishProvider = context.read<FishProvider>();
      final decorProvider = context.read<DecorProvider>();
      await fishProvider.setChild(child);
      await decorProvider.setChild(child);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Login successful!')),
      );

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const ChildNavigationShell()),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    } finally {
      setState(() => _loading = false);
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
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Logo
                  Image.asset(
                    'assets/bb2.png',
                    width: 150,
                    height: 150,
                  ),
                  const SizedBox(height: 20),

                  // Title
                  const Text(
                    "Enter Access Code",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: 'Fredoka',
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF8657F3),
                    ),
                  ),
                  const SizedBox(height: 8),

                  // Subtitle
                  const Text(
                    "Enter the code your parent gave you to start using BrightBuds.",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: 'Fredoka',
                      fontSize: 14,
                      color: Colors.black54,
                    ),
                  ),

                  const SizedBox(height: 30),

                  // Input Field
                  TextField(
                    controller: _codeController,
                    textAlign: TextAlign.center,
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: Colors.white,
                      hintText: "Access Code",
                      hintStyle: const TextStyle(
                        fontFamily: 'Fredoka',
                        color: Colors.black38,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        vertical: 16,
                        horizontal: 12,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Colors.deepPurple),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(
                          color: Color(0xFF8657F3),
                          width: 1.5,
                        ),
                      ),
                    ),
                    style: const TextStyle(
                      fontFamily: 'Fredoka',
                      fontSize: 16,
                    ),
                  ),

                  const SizedBox(height: 30),

                  // Login Button
                  _loading
                      ? const CircularProgressIndicator()
                      : SizedBox(
                          width: double.infinity,
                          height: 50,
                          child: ElevatedButton(
                            onPressed: _loginChild,
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
                              elevation: 2,
                            ),
                            child: const Text("Login"),
                          ),
                        ),
                  const SizedBox(height: 20),

                  // Tip
                  const Text(
                    "Ask your parent to share your code if you don’t have one yet.",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: 'Fredoka',
                      fontSize: 13,
                      color: Colors.black54,
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
