// ignore_for_file: file_names, unused_local_variable, use_build_context_synchronously, await_only_futures, avoid_print, deprecated_member_use

import 'package:brightbuds_new/data/models/therapist_model.dart';
import 'package:brightbuds_new/data/services/firestore_service.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../data/providers/auth_provider.dart' as app_auth;
import '../../../data/providers/selected_child_provider.dart';
import '../../../data/providers/journal_provider.dart';
import '../../pages/role_page.dart';

class TherapistAccountSidebar extends StatefulWidget {
  final String therapistId;
  const TherapistAccountSidebar({super.key, required this.therapistId});

  @override
  State<TherapistAccountSidebar> createState() =>
      _TherapistAccountSidebarState();
}

class _TherapistAccountSidebarState extends State<TherapistAccountSidebar> {
  final FirestoreService _firestore = FirestoreService();
  Map<String, dynamic>? therapistData;
  List<Map<String, dynamic>> childrenList = [];
  bool isLoading = true;

  final _editFormKey = GlobalKey<FormState>();
  String? _newName;
  String? _newEmail;
  String? _newPassword;

  @override
  void initState() {
    super.initState();

    // Use post frame callback to safely access context
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await fetchTherapistData();

      final selectedChildProv = Provider.of<SelectedChildProvider>(
        context,
        listen: false,
      );

      if (!mounted) return;
      if (childrenList.isNotEmpty && selectedChildProv.selectedChild == null) {
        await _forceSelectChild();
      }
    });
  }

  Future<void> _showLinkChildDialog(
    BuildContext context,
    String therapistUid,
  ) async {
    final controller = TextEditingController();
    final firestoreService = FirestoreService();

    if (!mounted) return;

    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Link Child with Access Code'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Enter the 6-digit access code provided by the parent'),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                labelText: 'Access Code',
                hintText: 'ABC123',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.code),
              ),
              maxLength: 6,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 20,
                letterSpacing: 2,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              if (!mounted) return;
              Navigator.pop(ctx);
            },
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final code = controller.text.trim().toUpperCase();
              if (code.length != 6) {
                if (!mounted) return;
                ScaffoldMessenger.of(ctx).showSnackBar(
                  const SnackBar(
                    content: Text('Please enter a valid 6-digit code'),
                  ),
                );
                return;
              }

              if (!mounted) return;
              Navigator.pop(ctx); // Close input dialog

              if (!mounted) return;
              showDialog(
                context: context,
                barrierDismissible: false,
                builder: (context) =>
                    const Center(child: CircularProgressIndicator()),
              );

              try {
                await firestoreService.linkChildByAccessCode(
                  accessCode: code,
                  therapistUid: therapistUid,
                );

                if (!mounted) return;
                Navigator.of(
                  context,
                  rootNavigator: true,
                ).pop(); // Close loading

                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('✅ Child linked successfully!'),
                    backgroundColor: Colors.green,
                  ),
                );

                if (!mounted) return;
                await fetchTherapistData(); // Refresh children list
                if (!mounted) return;
                setState(() {});
              } catch (e) {
                if (!mounted) return;
                Navigator.of(
                  context,
                  rootNavigator: true,
                ).pop(); // Close loading

                String errorMessage = 'Failed to link child';
                if (e.toString().contains('already linked')) {
                  errorMessage =
                      'This child is already linked to another therapist.';
                } else if (e.toString().contains('already linked to you')) {
                  errorMessage = 'This child is already linked to you.';
                } else if (e.toString().contains('not found')) {
                  errorMessage =
                      'Invalid access code. Please check with the parent.';
                }
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(errorMessage),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
            child: const Text('Link Child'),
          ),
        ],
      ),
    );
  }

  Future<void> _showTherapistSettingsDialog() async {
    if (therapistData == null) return;

    _newName = therapistData!['name'];
    _newEmail = therapistData!['email'];
    String? newPasswordConfirm;
    bool obscureNewPassword = true;
    bool obscureConfirmPassword = true;

    if (!mounted) return;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setStateDialog) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: const Center(
            child: Text(
              "Therapist Settings",
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
                  decoration: const InputDecoration(
                    labelText: "Name",
                    labelStyle: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  onSaved: (val) => _newName = val,
                  validator: (val) =>
                      val == null || val.isEmpty ? "Enter a name" : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  initialValue: _newEmail,
                  decoration: const InputDecoration(
                    labelText: "Email",
                    labelStyle: TextStyle(fontWeight: FontWeight.bold),
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
                        obscureNewPassword
                            ? Icons.visibility
                            : Icons.visibility_off,
                      ),
                      onPressed: () => setStateDialog(
                        () => obscureNewPassword = !obscureNewPassword,
                      ),
                    ),
                  ),
                  onSaved: (val) => _newPassword = val,
                  obscureText: obscureNewPassword,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  decoration: InputDecoration(
                    labelText: "Confirm New Password",
                    labelStyle: const TextStyle(fontWeight: FontWeight.bold),
                    suffixIcon: IconButton(
                      icon: Icon(
                        obscureConfirmPassword
                            ? Icons.visibility
                            : Icons.visibility_off,
                      ),
                      onPressed: () => setStateDialog(
                        () => obscureConfirmPassword = !obscureConfirmPassword,
                      ),
                    ),
                  ),
                  onSaved: (val) => newPasswordConfirm = val,
                  obscureText: obscureConfirmPassword,
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
              onPressed: () async {
                if (!mounted) return;
                await _updateTherapistInfo();
              },
              child: const Text("Save"),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _forceSelectChild() async {
    await Future.delayed(const Duration(milliseconds: 500));
    if (!mounted) return;

    final selectedChildProv = Provider.of<SelectedChildProvider>(
      context,
      listen: false,
    );

    if (selectedChildProv.selectedChild != null || childrenList.isEmpty) return;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text("Select a Child"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: childrenList.map((childMap) {
            final childName = childMap['name'] ?? 'Child';
            final accessCode = childMap['accessCode'] ?? 'N/A';
            return ListTile(
              leading: CircleAvatar(
                backgroundColor: Colors.blue[100],
                child: Text(
                  childName[0],
                  style: const TextStyle(color: Colors.black),
                ),
              ),
              title: Text(childName),
              subtitle: Text("Access Code: $accessCode"),
              onTap: () async {
                selectedChildProv.setSelectedChild(childMap);
                await Provider.of<JournalProvider>(
                  context,
                  listen: false,
                ).getEntries(childMap['cid']);
                if (!mounted) return;
                Navigator.pop(ctx);
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text("Switched to $childName")),
                );
                if (!mounted) return;
                setState(() {});
              },
            );
          }).toList(),
        ),
      ),
    );
  }

  Future<void> fetchTherapistData() async {
    if (!mounted) return;
    setState(() => isLoading = true);

    final auth = Provider.of<app_auth.AuthProvider>(context, listen: false);
    final user = auth.currentUserModel;

    if (user == null || user is! TherapistUser) {
      debugPrint('❌ No logged-in therapist');
      if (!mounted) return;
      setState(() => isLoading = false);
      return;
    }

    final therapistUid = user.uid;
    debugPrint('🔍 Fetching therapist data for UID: $therapistUid');

    try {
      final therapistSnap = await FirebaseFirestore.instance
          .collection('therapists')
          .doc(therapistUid)
          .get();

      if (!therapistSnap.exists) {
        debugPrint('❌ Therapist document not found');
        if (!mounted) return;
        setState(() {
          therapistData = null;
          childrenList = [];
          isLoading = false;
        });
        return;
      }

      therapistData = therapistSnap.data()!;
      final childrenField = therapistData!['childrenAccessCodes'];

      List<Map<String, dynamic>> fetchedChildren = [];
      if (childrenField is Map<String, dynamic>) {
        childrenField.forEach((childId, childData) {
          if (childData is Map<String, dynamic>) {
            final parentUid = childData['parentUid'] ?? '';
            final childName = childData['childName'] ?? 'Child';
            final accessCode = childData['accessCode'] ?? 'N/A';
            if (parentUid.isEmpty) return;
            fetchedChildren.add({
              'cid': childId,
              'name': childName,
              'parentUid': parentUid,
              'accessCode': accessCode,
            });
          }
        });
      }

      if (!mounted) return;
      setState(() {
        childrenList = fetchedChildren;
        isLoading = false;
      });
    } catch (e, stack) {
      debugPrint('❌ fetchTherapistData error: $e');
      debugPrint(stack.toString());
      if (!mounted) return;
      setState(() {
        therapistData = null;
        childrenList = [];
        isLoading = false;
      });
    }
  }

  Future<void> _switchChildDialog() async {
    if (childrenList.isEmpty) return;
    if (!mounted) return;
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Switch Child"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: childrenList.map((childMap) {
            final childName = childMap['name'] ?? 'Child';
            final accessCode = childMap['accessCode'] ?? 'N/A';
            return ListTile(
              leading: CircleAvatar(
                backgroundColor: Colors.blue[100],
                child: Text(
                  childName[0],
                  style: const TextStyle(color: Colors.black),
                ),
              ),
              title: Text(
                childName,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              subtitle: Text("Access Code: $accessCode"),
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
                if (!mounted) return;
                Navigator.pop(ctx);
                if (!mounted) return;
                setState(() {});
              },
            );
          }).toList(),
        ),
      ),
    );
  }

  Future<void> _updateTherapistInfo() async {
    if (!_editFormKey.currentState!.validate()) return;
    _editFormKey.currentState!.save();

    try {
      final user = FirebaseAuth.instance.currentUser;

      if (_newEmail != null &&
          _newEmail!.isNotEmpty &&
          _newEmail != therapistData!['email']) {
        await user?.updateEmail(_newEmail!);
      }

      if (_newPassword != null && _newPassword!.isNotEmpty) {
        await user?.updatePassword(_newPassword!);
      }

      await FirebaseFirestore.instance
          .collection('therapists')
          .doc(widget.therapistId)
          .update({'name': _newName, 'email': _newEmail});

      if (!mounted) return;
      setState(() {
        therapistData!['name'] = _newName;
        therapistData!['email'] = _newEmail;
      });

      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Therapist info updated successfully!")),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Failed to update: $e")));
    }
  }

  Future<void> _logout() async {
    try {
      final selectedChildProv = Provider.of<SelectedChildProvider>(
        context,
        listen: false,
      );
      final journalProv = Provider.of<JournalProvider>(context, listen: false);
      final authProvider = Provider.of<app_auth.AuthProvider>(
        context,
        listen: false,
      );

      selectedChildProv.clearSelectedChild();
      journalProv.clearEntries();

      if (!mounted) return;
      setState(() {
        therapistData = null;
        childrenList = [];
        isLoading = true;
      });

      await FirebaseAuth.instance.signOut();
      await authProvider.signOut();
      await FirebaseFirestore.instance.clearPersistence();

      await Future.delayed(const Duration(milliseconds: 500));

      if (!mounted) return;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const ChooseRolePage()),
        (route) => false,
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const ChooseRolePage()),
        (route) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) return const Center(child: CircularProgressIndicator());
    if (therapistData == null) {
      return const Center(child: Text("Therapist data not found."));
    }

    final selectedChildProv = Provider.of<SelectedChildProvider>(context);
    final activeChild = selectedChildProv.selectedChild;

    return Drawer(
      child: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(child: Image.asset("assets/bb3.png", height: 80)),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 30,
                        backgroundColor: Colors.blue[100],
                        child: Text(
                          therapistData!['name'][0].toUpperCase(),
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
                              therapistData!['name'],
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              "${childrenList.length} ${childrenList.length == 1 ? 'child' : 'children'}",
                              style: TextStyle(color: Colors.grey[600]),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.settings, color: Colors.grey),
                        onPressed: _showTherapistSettingsDialog,
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton.icon(
                    onPressed: () =>
                        _showLinkChildDialog(context, widget.therapistId),
                    icon: const Icon(Icons.add),
                    label: const Text("Link Child"),
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

                  // Display selected child with access code
                  if (childrenList.isNotEmpty && activeChild != null)
                    Card(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 3,
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: const Color(
                            0xFF8657F3,
                          ).withOpacity(0.2),
                          child: Text(
                            activeChild['name'][0],
                            style: const TextStyle(
                              color: Color(0xFF8657F3),
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        title: Text(
                          activeChild['name'],
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF070211),
                          ),
                        ),
                        subtitle: Text(
                          "Access Code: ${activeChild['accessCode'] ?? 'N/A'}",
                          style: TextStyle(
                            color: const Color(0xFF070211).withOpacity(0.8),
                          ),
                        ),
                        trailing: IconButton(
                          onPressed: _switchChildDialog,
                          icon: const Icon(
                            Icons.swap_horiz,
                            color: Color(0xFF070211),
                          ),
                          tooltip: "Switch Child",
                        ),
                      ),
                    ),

                  if (childrenList.isEmpty)
                    Card(
                      elevation: 2,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const ListTile(
                        leading: Icon(
                          Icons.child_care,
                          size: 40,
                          color: Colors.blue,
                        ),
                        title: Text(
                          "No children added yet",
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Text("Add your first child to get started."),
                      ),
                    ),
                ],
              ),
            ),
          ),
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
