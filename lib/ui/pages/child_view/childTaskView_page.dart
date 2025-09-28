import 'package:brightbuds_new/providers/auth_provider.dart';
import 'package:brightbuds_new/providers/task_provider.dart';
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
  @override
  void initState() {
    super.initState();
    // Load tasks filtered by childId
    Future.microtask(() {
      Provider.of<TaskProvider>(context, listen: false)
          .loadTasks(parentId: widget.parentId, childId: widget.childId);
    });
  }

  @override
  Widget build(BuildContext context) {
    final taskProvider = Provider.of<TaskProvider>(context);
    final authProvider = Provider.of<AuthProvider>(context, listen: false);

    // Filter tasks to ensure they belong to this child and have valid fields
    final childTasks = taskProvider.tasks.where((task) {
      return task.childId == widget.childId && task.name.isNotEmpty;
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: Text("Hello, ${widget.childName}"),
        automaticallyImplyLeading: false,
        actions: [
         ElevatedButton(
          onPressed: () async {
            await context.read<AuthProvider>().logoutChild(); // sign out child
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (_) => const ChooseRolePage()),
            );
          },
          child: const Text("Logout"),
        )

        ],
      ),
      body: taskProvider.isLoading
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
                                ? const Icon(Icons.verified,
                                    color: Colors.blue)
                                : const Icon(Icons.check, color: Colors.green))
                            : ElevatedButton(
                                onPressed: () {
                                  taskProvider.markTaskAsDone(
                                      task.id, widget.childId);
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
