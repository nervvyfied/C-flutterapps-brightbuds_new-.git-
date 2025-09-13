// Parent Task List Screen
import 'package:brightbuds_new/data/models/task_model.dart';
import 'package:brightbuds_new/providers/task_provider.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class ParentTaskListScreen extends StatefulWidget {
  final String parentId;
  final String childId; // 🔹 pass child's id here

  const ParentTaskListScreen({
    required this.parentId,
    required this.childId,
    super.key,
  });

  @override
  State<ParentTaskListScreen> createState() => _ParentTaskListScreenState();
}

class _ParentTaskListScreenState extends State<ParentTaskListScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      Provider.of<TaskProvider>(context, listen: false)
          .loadTasks(parentId: widget.parentId, childId: widget.childId);
    });
  }

  @override
  Widget build(BuildContext context) {
    final taskProvider = Provider.of<TaskProvider>(context);

    return Scaffold(
      appBar: AppBar(title: const Text("Parent Tasks")),
      body: taskProvider.isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              itemCount: taskProvider.tasks.length,
              itemBuilder: (context, index) {
                final task = taskProvider.tasks[index];
                return ListTile(
                  title: Text(task.name),
                  subtitle: Text("Difficulty: ${task.difficulty} • Reward: ${task.reward} tokens",),
                  trailing: task.verified
                      ? const Icon(Icons.verified, color: Colors.green)
                      : task.isDone
                          ? ElevatedButton(
                              child: const Text("Verify"),
                              onPressed: () {
                                taskProvider.verifyTask(
                                    task.id, task.childId);
                              },
                            )
                          : const Icon(Icons.pending),
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => AddTaskScreen(
                parentId: widget.parentId,
                childId: widget.childId, // 🔹 pass child's id here
              ),
            ),
          );
        },
        child: const Icon(Icons.add),
      ),
    );
  }
}

// Add Task Screen
class AddTaskScreen extends StatefulWidget {
  final String parentId;
  final String childId; // 🔹 child comes from ParentTaskListScreen

  const AddTaskScreen({
    required this.parentId,
    required this.childId,
    super.key,
  });

  @override
  State<AddTaskScreen> createState() => _AddTaskScreenState();
}

class _AddTaskScreenState extends State<AddTaskScreen> {
  final _formKey = GlobalKey<FormState>();

  String taskName = '';
  String difficulty = 'Easy';
  int reward = 10;
  String routine = 'Anytime';

  @override
  Widget build(BuildContext context) {
    final taskProvider = Provider.of<TaskProvider>(context, listen: false);

    return Scaffold(
      appBar: AppBar(title: const Text("Add Task")),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              TextFormField(
                decoration: const InputDecoration(labelText: "Title"),
                onSaved: (val) => taskName = val ?? '',
                validator: (val) => val!.isEmpty ? "Enter title" : null,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                decoration: const InputDecoration(labelText: "Difficulty"),
                value: difficulty,
                items: ['Easy', 'Medium', 'Hard']
                    .map((d) => DropdownMenuItem(value: d, child: Text(d)))
                    .toList(),
                onChanged: (val) => setState(() => difficulty = val!),
              ),
              const SizedBox(height: 12),
              TextFormField(
                decoration: const InputDecoration(labelText: "Reward (tokens)"),
                keyboardType: TextInputType.number,
                initialValue: reward.toString(),
                onSaved: (val) => reward = int.tryParse(val ?? '10') ?? 10,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                decoration: const InputDecoration(labelText: "Routine"),
                value: routine,
                items: ['Morning', 'Afternoon', 'Evening', 'Anytime']
                    .map((r) => DropdownMenuItem(value: r, child: Text(r)))
                    .toList(),
                onChanged: (val) => setState(() => routine = val!),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                child: const Text("Save Task"),
                onPressed: () {
                  if (_formKey.currentState!.validate()) {
                    _formKey.currentState!.save();
                    final task = TaskModel(
                      id: DateTime.now()
                          .millisecondsSinceEpoch
                          .toString(), // simple id
                      name: taskName,
                      difficulty: difficulty,
                      reward: reward,
                      routine: routine,
                      parentId: widget.parentId,
                      childId: widget.childId,
                      createdAt: DateTime.now(),
                    );
                    taskProvider.addTask(task);
                    Navigator.pop(context);
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
