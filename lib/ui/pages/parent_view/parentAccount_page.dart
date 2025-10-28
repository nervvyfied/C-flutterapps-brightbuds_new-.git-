import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../data/providers/auth_provider.dart' as app_auth;
import '../../../data/providers/selected_child_provider.dart';
import '../../../data/providers/journal_provider.dart';
import '../../../data/repositories/user_repository.dart';
import '../../pages/role_page.dart';

class ParentAccountSidebar extends StatefulWidget {
  final String parentId;
  const ParentAccountSidebar({super.key, required this.parentId});

  @override
  State<ParentAccountSidebar> createState() => _ParentAccountSidebarState();
}

class _ParentAccountSidebarState extends State<ParentAccountSidebar> {
  final UserRepository _userRepo = UserRepository();
  Map<String, dynamic>? parentData;
  List<Map<String, dynamic>> childrenList = [];
  bool isLoading = true;

  final _editFormKey = GlobalKey<FormState>();
  String? _newName;
  String? _newEmail;
  String? _newPassword;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final selectedChildProvider = Provider.of<SelectedChildProvider>(
        context,
        listen: false,
      );
      await fetchParentData();
      if (childrenList.isNotEmpty &&
          selectedChildProvider.selectedChild == null) {
        _forceSelectChild();
      }
    });
  }

  Future<void> _forceSelectChild() async {
    final selectedChildProv = Provider.of<SelectedChildProvider>(
      context,
      listen: false,
    );
    if (selectedChildProv.selectedChild != null) return;
    await Future.delayed(const Duration(milliseconds: 300));

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return AlertDialog(
          title: const Text("Select a Child"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: childrenList.map((childMap) {
              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: Colors.blue[100],
                  child: Text(
                    childMap['name'][0],
                    style: const TextStyle(color: Colors.black),
                  ),
                ),
                title: Text(childMap['name']),
                subtitle: Text("Access Code: ${childMap['accessCode']}"),
                onTap: () async {
                  selectedChildProv.setSelectedChild(childMap);
                  await Provider.of<JournalProvider>(
                    context,
                    listen: false,
                  ).getEntries(childMap['cid']);
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text("Switched to ${childMap['name']}")),
                  );
                  setState(() {});
                },
              );
            }).toList(),
          ),
        );
      },
    );
  }

  Future<void> fetchParentData() async {
    setState(() => isLoading = true);
    try {
      final parentSnapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.parentId)
          .get();

      if (!parentSnapshot.exists) {
        setState(() {
          parentData = null;
          childrenList = [];
          isLoading = false;
        });
        return;
      }

      Map<String, dynamic> data =
          parentSnapshot.data() as Map<String, dynamic>? ?? {};
      Map<String, dynamic> accessCodes =
          (data['childrenAccessCodes'] ?? {}) as Map<String, dynamic>;

      final childrenSnapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.parentId)
          .collection('children')
          .get();

      List<Map<String, dynamic>> tempChildren = childrenSnapshot.docs.map((
        doc,
      ) {
        var c = doc.data() as Map<String, dynamic>;
        String code = accessCodes[doc.id]?.toString() ?? "—";
        return {
          "cid": doc.id,
          "name": c['name'] ?? 'Child',
          "accessCode": code,
          "balance": c['balance'] ?? 0,
        };
      }).toList();

      final selectedChildProv = Provider.of<SelectedChildProvider>(
        context,
        listen: false,
      );

      if (tempChildren.isNotEmpty) {
        var currentSelected = selectedChildProv.selectedChild;
        if (currentSelected == null ||
            !tempChildren.any((c) => c['cid'] == currentSelected['cid'])) {
          selectedChildProv.setSelectedChild(tempChildren[0]);
          await Provider.of<JournalProvider>(
            context,
            listen: false,
          ).getEntries(tempChildren[0]['cid']);
        } else {
          await Provider.of<JournalProvider>(
            context,
            listen: false,
          ).getEntries(currentSelected['cid']);
        }
      } else {
        selectedChildProv.setSelectedChild(null);
      }

      setState(() {
        parentData = data;
        childrenList = tempChildren;
        isLoading = false;
      });
    } catch (e) {
      print("Error fetching parent data: $e");
      setState(() {
        parentData = null;
        childrenList = [];
        isLoading = false;
      });
    }
  }

  Future<void> _switchChildDialog() async {
    if (childrenList.isEmpty) return;
    await showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text("Switch Child"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: childrenList.map((childMap) {
              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: Colors.blue[100],
                  child: Text(
                    childMap['name'][0],
                    style: const TextStyle(color: Colors.black),
                  ),
                ),
                title: Text(childMap['name']),
                subtitle: Text("Access Code: ${childMap['accessCode']}"),
                onTap: () async {
                  final selectedChildProv = Provider.of<SelectedChildProvider>(
                    context,
                    listen: false,
                  );
                  selectedChildProv.setSelectedChild(childMap);
                  await Provider.of<JournalProvider>(
                    context,
                    listen: false,
                  ).getEntries(childMap['cid']);
                  Navigator.pop(ctx);
                  setState(() {});
                },
              );
            }).toList(),
          ),
        );
      },
    );
  }

  Future<void> _updateParentInfo() async {
    if (!_editFormKey.currentState!.validate()) return;
    _editFormKey.currentState!.save();

    try {
      final user = FirebaseAuth.instance.currentUser;

      if (_newEmail != null &&
          _newEmail!.isNotEmpty &&
          _newEmail != parentData!['email']) {
        await user?.updateEmail(_newEmail!);
      }

      if (_newPassword != null && _newPassword!.isNotEmpty) {
        await user?.updatePassword(_newPassword!);
      }

      await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.parentId)
          .update({'name': _newName, 'email': _newEmail});

      setState(() {
        parentData!['name'] = _newName;
        parentData!['email'] = _newEmail;
      });

      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Parent info updated successfully!")),
      );
    } catch (e) {
      print("Error updating parent info: $e");
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Failed to update: $e")));
    }
  }

  Future<void> _showParentSettingsDialog() async {
    _newName = parentData!['name'];
    _newEmail = parentData!['email'];
    String? _newPasswordConfirm;
    bool _obscureNewPassword = true;
    bool _obscureConfirmPassword = true;

    final auth = Provider.of<app_auth.AuthProvider>(context, listen: false);

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setStateDialog) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: const Center(
            child: Text(
              "Parent Settings",
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          content: Form(
            key: _editFormKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  initialValue: _newName,
                  decoration: InputDecoration(
                    labelText: "Name",
                    labelStyle: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  onSaved: (val) => _newName = val,
                  validator: (val) =>
                      val == null || val.isEmpty ? "Enter a name" : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  initialValue: _newEmail,
                  decoration: InputDecoration(
                    labelText: "Email",
                    labelStyle: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  onSaved: (val) => _newEmail = val,
                  validator: (val) => val == null || !val.contains('@')
                      ? "Enter a valid email"
                      : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  decoration: InputDecoration(
                    labelText: "New Password (leave blank to keep)",
                    labelStyle: const TextStyle(fontWeight: FontWeight.bold),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscureNewPassword
                            ? Icons.visibility
                            : Icons.visibility_off,
                      ),
                      onPressed: () {
                        setStateDialog(() {
                          _obscureNewPassword = !_obscureNewPassword;
                        });
                      },
                    ),
                  ),
                  onSaved: (val) => _newPassword = val,
                  obscureText: _obscureNewPassword,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  decoration: InputDecoration(
                    labelText: "Confirm New Password",
                    labelStyle: const TextStyle(fontWeight: FontWeight.bold),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscureConfirmPassword
                            ? Icons.visibility
                            : Icons.visibility_off,
                      ),
                      onPressed: () {
                        setStateDialog(() {
                          _obscureConfirmPassword = !_obscureConfirmPassword;
                        });
                      },
                    ),
                  ),
                  onSaved: (val) => _newPasswordConfirm = val,
                  obscureText: _obscureConfirmPassword,
                  validator: (val) {
                    if ((_newPassword != null && _newPassword!.isNotEmpty) &&
                        val != _newPassword) {
                      return "Passwords do not match";
                    }
                    return null;
                  },
                ),
              ],
            ),
          ),
          actionsAlignment: MainAxisAlignment.center,
          actions: [
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF8657F3),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                minimumSize: const Size(100, 40),
              ),
              onPressed: _updateParentInfo,
              child: const Text("Save"),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showAddChildDialog() async {
    final auth = Provider.of<app_auth.AuthProvider>(context, listen: false);
    final parent = auth.currentUserModel;
    if (parent == null) return;

    final controller = TextEditingController();

    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Center(
          child: Text(
            'Add Child',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(
            labelText: 'Child Name',
            labelStyle: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF8657F3),
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              final name = controller.text.trim();
              if (name.isEmpty) return;
              Navigator.pop(ctx);

              final created = await auth.addChild(name);
              await fetchParentData();

              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    created != null
                        ? "Child '${created.name}' added!"
                        : "Child created, refresh to see it.",
                  ),
                ),
              );
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  Future<void> _logout() async {
    final auth = Provider.of<app_auth.AuthProvider>(context, listen: false);
    Provider.of<SelectedChildProvider>(
      context,
      listen: false,
    ).clearSelectedChild();
    await auth.signOut();
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const ChooseRolePage()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) return const Center(child: CircularProgressIndicator());
    if (parentData == null)
      return const Center(child: Text("Parent data not found."));

    final activeChild = Provider.of<SelectedChildProvider>(
      context,
    ).selectedChild;

    return Drawer(
      child: Column(
        children: [
          // Scrollable content
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Logo
                  Center(child: Image.asset("assets/bb3.png", height: 80)),
                  const SizedBox(height: 24),

                  // Parent Profile
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 30,
                        backgroundColor: Colors.blue[100],
                        child: Text(
                          parentData!['name'][0].toUpperCase(),
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              parentData!['name'],
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              "${childrenList.length} children",
                              style: TextStyle(color: Colors.grey[600]),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.settings, color: Colors.grey),
                        onPressed: _showParentSettingsDialog,
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // Add Child Button
                  ElevatedButton.icon(
                    onPressed: _showAddChildDialog,
                    icon: const Icon(Icons.add),
                    label: const Text("Add Child"),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFA6C26F),
                      foregroundColor: Colors.white,
                      minimumSize: const Size(double.infinity, 50),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Active Child Card
                  if (childrenList.isNotEmpty &&
                      Provider.of<SelectedChildProvider>(
                            context,
                          ).selectedChild !=
                          null)
                    Card(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 3,
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: Colors.blue[100],
                          child: Text(
                            Provider.of<SelectedChildProvider>(
                              context,
                            ).selectedChild!['name'][0],
                            style: const TextStyle(color: Colors.black),
                          ),
                        ),
                        title: Text(
                          Provider.of<SelectedChildProvider>(
                            context,
                          ).selectedChild!['name'],
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              "Balance: ${Provider.of<SelectedChildProvider>(context).selectedChild!['balance']}",
                            ),
                          ],
                        ),
                        trailing: IconButton(
                          onPressed: _switchChildDialog,
                          icon: const Icon(Icons.swap_horiz),
                          tooltip: "Switch Child",
                        ),
                      ),
                    ),

                  // No children
                  if (childrenList.isEmpty)
                    Card(
                      elevation: 2,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: ListTile(
                        leading: const Icon(
                          Icons.child_care,
                          size: 40,
                          color: Colors.blue,
                        ),
                        title: const Text(
                          "No children added yet",
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: const Text(
                          "Add your first child to get started.",
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),

          // Logout Button at the bottom
          Padding(
            padding: const EdgeInsets.all(16),
            child: ElevatedButton.icon(
              onPressed: _logout,
              icon: const Icon(Icons.logout),
              label: const Text("Log Out"),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF8657F3),
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 50),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
