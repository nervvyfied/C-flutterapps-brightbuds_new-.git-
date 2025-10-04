import 'dart:io';
import 'package:brightbuds_new/data/repositories/user_repository.dart';
import 'package:brightbuds_new/ui/pages/role_page.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import '../../../data/providers/auth_provider.dart' as app_auth;
import '../../../data/providers/selected_child_provider.dart';
import '../../../data/providers/journal_provider.dart';

class ParentAccountPage extends StatefulWidget {
  final String parentId;
  const ParentAccountPage({super.key, required this.parentId});

  @override
  State<ParentAccountPage> createState() => _ParentAccountPageState();
}

class _ParentAccountPageState extends State<ParentAccountPage> {
  final UserRepository _userRepo = UserRepository();
  Map<String, dynamic>? parentData;
  List<Map<String, dynamic>> childrenList = [];
  bool isLoading = true;
  File? _profileImage;

  final _editFormKey = GlobalKey<FormState>();
  String? _newName;
  String? _newEmail;
  String? _newPassword;

  @override
  void initState() {
    super.initState();
    // Reset selected child on new login
    Provider.of<SelectedChildProvider>(context, listen: false).clearSelectedChild();
    fetchParentData();
  }

  Future<void> fetchParentData() async {
    setState(() => isLoading = true);
    try {
      // Get parent doc
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

      // Always fetch children fresh from Firestore
      final childrenSnapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.parentId)
          .collection('children')
          .get();

      List<Map<String, dynamic>> tempChildren = childrenSnapshot.docs.map((doc) {
        var c = doc.data() as Map<String, dynamic>;
        String code = accessCodes[doc.id]?.toString() ?? "—";
        return {
          "cid": doc.id,
          "name": c['name'] ?? 'Child',
          "accessCode": code,
          "balance": c['balance'] ?? 0,
          "streak": c['streak'] ?? 0,
        };
      }).toList();

      final selectedChildProv =
          Provider.of<SelectedChildProvider>(context, listen: false);

      // Auto-select first child if none selected
      if (tempChildren.isNotEmpty && selectedChildProv.selectedChild == null) {
        selectedChildProv.setSelectedChild(tempChildren[0]);
        Provider.of<JournalProvider>(context, listen: false)
            .fetchEntries(widget.parentId, tempChildren[0]['cid']);
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
                  child: Text(childMap['name'][0]),
                ),
                title: Text(childMap['name']),
                subtitle: Text("Access Code: ${childMap['accessCode']}"),
                onTap: () async {
                  final selectedChildProv =
                      Provider.of<SelectedChildProvider>(context, listen: false);

                  selectedChildProv.setSelectedChild(childMap);

                  await Provider.of<JournalProvider>(context, listen: false)
                      .fetchEntries(widget.parentId, childMap['cid']);

                  Navigator.pop(ctx);
                },
              );
            }).toList(),
          ),
        );
      },
    );
  }

  Future<void> _showParentSettingsDialog() async {
    _newName = parentData!['name'];
    _newEmail = parentData!['email'];

    final auth = Provider.of<app_auth.AuthProvider>(context, listen: false);

    await showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text("Settings"),
          content: Form(
            key: _editFormKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  initialValue: _newName,
                  decoration: const InputDecoration(labelText: "Name"),
                  onSaved: (val) => _newName = val,
                  validator: (val) =>
                      val == null || val.isEmpty ? "Enter a name" : null,
                ),
                TextFormField(
                  initialValue: _newEmail,
                  decoration: const InputDecoration(labelText: "Email"),
                  onSaved: (val) => _newEmail = val,
                  validator: (val) =>
                      val == null || !val.contains('@')
                          ? "Enter a valid email"
                          : null,
                ),
                TextFormField(
                  decoration: const InputDecoration(
                    labelText: "Password (leave blank to keep)",
                  ),
                  onSaved: (val) => _newPassword = val,
                  obscureText: true,
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
          actions: [
           ElevatedButton.icon(
            icon: const Icon(Icons.logout),
            label: const Text("Log Out"),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: Colors.deepPurple,
            ),
            onPressed: () async {
              final auth = Provider.of<app_auth.AuthProvider>(context, listen: false);

              // Clear selected child
              Provider.of<SelectedChildProvider>(context, listen: false)
                  .clearSelectedChild();

              // Sign out parent and clear cached children
              await auth.signOut();

              // Navigate back to role selection page
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => const ChooseRolePage()),
                (route) => false,
              );
            },
          ),
            ElevatedButton(
              onPressed: _updateParentInfo,
              child: const Text("Save"),
            ),
          ],
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Failed to update: $e")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) return const Center(child: CircularProgressIndicator());
    if (parentData == null) {
      return const Center(child: Text("Parent data not found."));
    }

    final activeChild = Provider.of<SelectedChildProvider>(context).selectedChild;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Account Page'),
        automaticallyImplyLeading: false,
      ),
      body: RefreshIndicator(
        onRefresh: fetchParentData,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              // --- Parent Profile Info ---
              Row(
                children: [
                  const CircleAvatar(
                    radius: 40,
                    backgroundImage:
                        AssetImage("assets/profile_placeholder.png"),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              parentData!['name'] ?? "Parent",
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.settings),
                              onPressed: _showParentSettingsDialog,
                            ),
                          ],
                        ),
                        Text(
                          "${childrenList.length} children",
                          style: TextStyle(color: Colors.grey[600]),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // --- Show "Add Child" if no children ---
              if (childrenList.isEmpty)
                Card(
                  elevation: 2,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: ListTile(
                    leading: const Icon(Icons.child_care,
                        size: 40, color: Colors.blue),
                    title: const Text(
                      "No children added yet",
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle:
                        const Text("Add your first child to get started."),
                    trailing: ElevatedButton.icon(
                      icon: const Icon(Icons.add),
                      label: const Text("Add Child"),
                      onPressed: _showAddChildDialog,
                    ),
                  ),
                ),

              // --- If children exist, show active child card ---
              if (childrenList.isNotEmpty && activeChild != null)
                Card(
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: Colors.blue[100],
                      child: Text(activeChild['name'][0]),
                    ),
                    title: Text(activeChild['name']),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text("Balance: ${activeChild['balance']}"),
                        Text("Streak: ${activeChild['streak']}"),
                      ],
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          onPressed: _showAddChildDialog,
                          icon: const Icon(Icons.add),
                          tooltip: "Add Child",
                        ),
                        IconButton(
                          onPressed: _switchChildDialog,
                          icon: const Icon(Icons.swap_horiz),
                          tooltip: "Switch Child",
                        ),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 24),
            ],
          ),
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
        title: const Text('Add Child'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: 'Child name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final name = controller.text.trim();
              if (name.isEmpty) return;
              Navigator.pop(ctx);

              final created = await auth.addChild(name);

              // Re-fetch children fresh
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
}
