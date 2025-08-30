/*import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../../data/models/task_model.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class TaskPage extends StatefulWidget {
  const TaskPage({super.key});

  @override
  State<TaskPage> createState() => _TaskPageState();
}

class _TaskPageState extends State<TaskPage> {
  final TextEditingController _controller = TextEditingController();
  final Box<TaskModel> taskBox = Hive.box<TaskModel>('tasks');

  void _addTask(String title) {
    if (title.isEmpty) return;
    final task = TaskModel(title: title);
    taskBox.add(task);
    _controller.clear();
    setState(() {});
  }

  void _toggleTask(TaskModel task) {
    task.isDone = !task.isDone;
    task.save();
    setState(() {});
  }

  void _deleteTask(TaskModel task) {
    task.delete();
    setState(() {});
  }

  void _editTask(TaskModel task) {
    final editController = TextEditingController(text: task.title);

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Edit Task"),
        content: TextField(
          controller: editController,
          decoration: const InputDecoration(
            labelText: "Task title",
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () {
              final newTitle = editController.text.trim();
              if (newTitle.isNotEmpty) {
                task.title = newTitle;
                task.save();
                setState(() {});
              }
              Navigator.pop(context);
            },
            child: const Text("Save"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tasks = taskBox.values.toList();

    return Scaffold(
      appBar: AppBar(title: const Text("BrightBuds Tasks")),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    decoration: const InputDecoration(
                      labelText: "Add a task",
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => _addTask(_controller.text),
                  icon: const Icon(Icons.add),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: tasks.length,
              itemBuilder: (_, i) {
                final task = tasks[i];
                return ListTile(
                  leading: Checkbox(
                    value: task.isDone,
                    onChanged: (_) => _toggleTask(task),
                  ),
                  title: Text(
                    task.title,
                    style: TextStyle(
                      decoration: task.isDone
                          ? TextDecoration.lineThrough
                          : TextDecoration.none,
                    ),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.edit, color: Colors.blue),
                        onPressed: () => _editTask(task),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete, color: Colors.red),
                        onPressed: () => _deleteTask(task),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

*/
