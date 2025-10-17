import 'package:brightbuds_new/aquarium/manager/unlockManager.dart';
import 'package:brightbuds_new/data/providers/auth_provider.dart';
import 'package:brightbuds_new/data/providers/task_provider.dart';
import 'package:brightbuds_new/ui/pages/role_page.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class ChildQuestsPage extends StatefulWidget {
  final String parentId;
  final String childId;
  final String childName;

  const ChildQuestsPage({
    required this.parentId,
    required this.childId,
    required this.childName,
    super.key,
  });

  @override
  State<ChildQuestsPage> createState() => _ChildQuestsPageState();
}

class _ChildQuestsPageState extends State<ChildQuestsPage> {
  bool _initialLoadDone = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(() async {
      final taskProvider = Provider.of<TaskProvider>(context, listen: false);

      // 1️⃣ Load from Hive first (offline)
      await taskProvider.loadTasks(
        parentId: widget.parentId,
        childId: widget.childId,
      );

      // 2️⃣ Only fetch from Firestore if no tasks in Hive
      if (taskProvider.tasks
          .where((t) => t.childId == widget.childId)
          .isEmpty) {
        await taskProvider.loadTasks(
          parentId: widget.parentId,
          childId: widget.childId,
        );
      }

      setState(() {
        _initialLoadDone = true;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final taskProvider = Provider.of<TaskProvider>(context);
    final unlockManager = context.read<UnlockManager>();

    // Filter tasks for this child
    final childTasks = taskProvider.tasks
        .where((task) => task.childId == widget.childId && task.name.isNotEmpty)
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: Text("Hello, ${widget.childName}"),
        automaticallyImplyLeading: false,
        actions: [
          ElevatedButton(
            onPressed: () async {
              await context.read<AuthProvider>().logoutChild();
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (_) => const ChooseRolePage()),
              );
            },
            child: const Text("Logout"),
          ),
        ],
      ),
      body: !_initialLoadDone || taskProvider.isLoading
          ? const Center(child: CircularProgressIndicator())
          : childTasks.isEmpty
              ? const Center(child: Text("No quests yet! 🎉"))
              : ListView.builder(
                  itemCount: childTasks.length,
                  itemBuilder: (_, i) {
                    final task = childTasks[i];
                    return Card(
                      margin: const EdgeInsets.symmetric(
                          vertical: 6, horizontal: 12),
                      child: ListTile(
                        title: Text(task.name),
                        subtitle: Text(
                            "Routine: ${task.routine} • Reward: ${task.reward} tokens"),
                        trailing: task.isDone
                            ? (task.verified
                                ? const Icon(Icons.verified, color: Colors.blue)
                                : const Icon(Icons.check, color: Colors.green))
                            : ElevatedButton(
                                onPressed: () {
                                  // 1️⃣ Optimistic update: mark task as done locally first
                                  taskProvider.markTaskAsDone(
                                      task.id, widget.childId);

                                  // 2️⃣ Immediately update UI
                                  setState(() {});

                                  // 3️⃣ Check unlocks
                                  unlockManager.checkUnlocks();

                                  // 4️⃣ Push changes to Firestore asynchronously
                                  taskProvider.pushPendingChanges();
                                },
                                child: const Text("Done"),
                              ),
                      ),
                    );
                  },
                ),
    );
  }
}
