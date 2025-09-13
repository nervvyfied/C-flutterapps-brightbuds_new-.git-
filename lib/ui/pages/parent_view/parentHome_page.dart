import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '/data/models/parent_model.dart';
import '/data/models/child_model.dart';
import '/data/repositories/user_repository.dart';
import '/providers/auth_provider.dart';

class ParentDashboardPage extends StatefulWidget {
  final String parentId;
  final String childId; // 🔹 pass child's id here

  const ParentDashboardPage({
    required this.parentId,
    required this.childId,
    super.key,
  });

  @override
  State<ParentDashboardPage> createState() => _ParentDashboardPageState();
}

class _ParentDashboardPageState extends State<ParentDashboardPage> {
  final UserRepository _userRepo = UserRepository();
  List<ChildUser> _children = [];
  String? _accessCode; // single code instead of list
  bool _loading = false;

  Future<void> _loadData() async {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final model = auth.currentUserModel;
    if (model == null || model is! ParentUser) return;

    setState(() => _loading = true);

    // Refresh parent (and get latest access code)
    final parent = await _userRepo.fetchParentAndCache(model.uid);
    _accessCode = parent?.accessCode;

    // Fetch child (even though it's single, keep list for consistency in UI)
    final children = await _userRepo.fetchChildrenAndCache(model.uid);
    setState(() {
      _children = children;
      _loading = false;
    });
  }

  Future<void> _showAddChildDialog() async {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final parent = auth.currentUserModel as ParentUser?;
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

              Navigator.pop(ctx); // close dialog quickly

              setState(() => _loading = true);

              // Create child (auth generates access code)
              final created = await auth.addChild(name);

              // Refresh parent and child
              final refreshedParent =
                  await _userRepo.fetchParentAndCache(parent.uid);
              final children =
                  await _userRepo.fetchChildrenAndCache(parent.uid);

              setState(() {
                _children = children;
                _accessCode = refreshedParent?.accessCode;
                _loading = false;
              });

              ScaffoldMessenger.of(context).showSnackBar(
  SnackBar(
    content: Text(
      created != null
          ? "Child '${created.name}' added! "
            "Access code: ${refreshedParent?.childrenAccessCodes?[created.cid] ?? '—'}"
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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadData());
  }

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context);
    final current = auth.currentUserModel;
    if (current == null || current is! ParentUser) {
      return const Scaffold(
        body: Center(child: Text('Not logged in as parent.')),
      );
    }

    final parent = current;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Parent Dashboard'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadData,
            tooltip: 'Refresh',
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => auth.signOut(),
            tooltip: 'Sign out',
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(12.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(parent.name,
                        style: const TextStyle(
                            fontSize: 20, fontWeight: FontWeight.bold)),
                    subtitle: Text(parent.email),
                  ),
                  const SizedBox(height: 12),

                  // Access Code Section
                  const Text('Children & Access Codes',
    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
const SizedBox(height: 8),
Expanded(
  flex: 2,
  child: _children.isEmpty
      ? const Center(child: Text('No children yet. Tap + to add one.'))
      : ListView.builder(
          itemCount: _children.length,
          itemBuilder: (ctx, i) {
            final child = _children[i];
            final parent = auth.currentUserModel as ParentUser;
            final code = parent.childrenAccessCodes?[child.cid] ?? "—";

            return Card(
              margin: const EdgeInsets.symmetric(vertical: 6),
              child: ListTile(
                title: Text(child.name),
                subtitle: Text(
                    'Balance: ${child.balance} • Streak: ${child.streak}\nAccess Code: $code'),
                trailing: IconButton(
                  icon: const Icon(Icons.copy),
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Copied $code to clipboard')),
                    );
                  },
                ),
              ),
            );
          },
        ),
),

                ],
              ),
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddChildDialog,
        child: const Icon(Icons.add),
      ),
    );
  }
}
