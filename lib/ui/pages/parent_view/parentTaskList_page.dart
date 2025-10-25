import 'dart:async';
import 'package:brightbuds_new/data/models/task_model.dart';
import 'package:brightbuds_new/data/providers/task_provider.dart';
import 'package:brightbuds_new/data/providers/selected_child_provider.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class ParentTaskListScreen extends StatefulWidget {
  final String parentId;

  const ParentTaskListScreen({required this.parentId, super.key});

  @override
  State<ParentTaskListScreen> createState() => _ParentTaskListScreenState();
}

class _ParentTaskListScreenState extends State<ParentTaskListScreen> {
  Timer? _autoResetTimer;

  @override
  void initState() {
    super.initState();

    // Auto-reset every 5 minutes
    _autoResetTimer = Timer.periodic(const Duration(minutes: 5), (_) {
      final taskProvider = Provider.of<TaskProvider>(context, listen: false);
      taskProvider.autoResetIfNeeded();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Listen for changes in selected child
    final selectedChildProv = Provider.of<SelectedChildProvider>(
      context,
      listen: false,
    );
    selectedChildProv.addListener(_loadTasksForSelectedChild);

    // Load tasks for initial child
    _loadTasksForSelectedChild();
  }

  @override
  void dispose() {
    _autoResetTimer?.cancel();
    final selectedChildProv = Provider.of<SelectedChildProvider>(
      context,
      listen: false,
    );
    selectedChildProv.removeListener(_loadTasksForSelectedChild);
    super.dispose();
  }

  void _loadTasksForSelectedChild() {
    final taskProvider = Provider.of<TaskProvider>(context, listen: false);
    final selectedChildProv = Provider.of<SelectedChildProvider>(
      context,
      listen: false,
    );

    final childId = selectedChildProv.selectedChild?['cid'];

    if (childId != null && childId.isNotEmpty) {
      taskProvider.loadTasks(parentId: widget.parentId, childId: childId);
    } else {
      taskProvider.loadTasks(parentId: widget.parentId);
    }
  }

  void _openTaskModal(BuildContext context, {TaskModel? task}) {
    final selectedChildProv = Provider.of<SelectedChildProvider>(
      context,
      listen: false,
    );
    final childId = selectedChildProv.selectedChild?['cid'];
    if (childId == null) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: TaskFormModal(
          parentId: widget.parentId,
          childId: childId,
          task: task,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final selectedChildProv = Provider.of<SelectedChildProvider>(context);
    final childId = selectedChildProv.selectedChild?['cid'];
    final childName = selectedChildProv.selectedChild?['name'] ?? 'No Child';

    return Scaffold(
      appBar: AppBar(
        title: Text("Quests for $childName"),
        automaticallyImplyLeading: false,
      ),
      body: Consumer<TaskProvider>(
        builder: (context, taskProvider, _) {
          final childTasks = childId != null
              ? taskProvider.tasks.where((t) => t.childId == childId).toList()
              : [];

          if (taskProvider.isLoading) {
            return const Center(child: CircularProgressIndicator());
          } else if (childTasks.isEmpty) {
            return Center(
              child: Text("No quests assigned to $childName. Add some!"),
            );
          }

          return ListView.builder(
            itemCount: childTasks.length,
            itemBuilder: (context, index) {
              final task = childTasks[index];
              return ListTile(
                title: Text(task.name),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Difficulty: ${task.difficulty} • Reward: ${task.reward} tokens",
                    ),
                    const SizedBox(height: 4),
                    task.verified
                        ? const Text(
                            "✅ Verified",
                            style: TextStyle(color: Colors.green),
                          )
                        : task.isDone
                        ? ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              textStyle: const TextStyle(fontSize: 14),
                            ),
                            child: const Text("Verify"),
                            onPressed: () {
                              taskProvider.verifyTask(task.id, task.childId);
                            },
                          )
                        : const Text(
                            "⏳ Pending",
                            style: TextStyle(color: Colors.orange),
                          ),
                  ],
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.edit),
                  onPressed: () => _openTaskModal(context, task: task),
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openTaskModal(context),
        child: const Icon(Icons.add),
      ),
    );
  }
}
// ---------------- Task Modal ----------------

class TaskFormModal extends StatefulWidget {
  final String parentId;
  final String childId;
  final TaskModel? task;

  const TaskFormModal({
    required this.parentId,
    required this.childId,
    this.task,
    super.key,
  });

  @override
  State<TaskFormModal> createState() => _TaskFormModalState();
}

class _TaskFormModalState extends State<TaskFormModal> {
  final _formKey = GlobalKey<FormState>();

  late String taskName;
  late String difficulty;
  late int reward;
  late String routine;
  DateTime? alarmDateTime;

  @override
  void initState() {
    super.initState();
    taskName = widget.task?.name ?? '';
    difficulty = widget.task?.difficulty ?? 'Easy';
    reward = widget.task?.reward ?? 10;
    routine = widget.task?.routine ?? 'Anytime';
    alarmDateTime = widget.task?.alarm;
  }

  Future<void> _pickAlarmTime() async {
    final now = DateTime.now();

    final pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(alarmDateTime ?? DateTime.now()),
    );
    if (pickedTime != null) {
      setState(() {
        alarmDateTime = DateTime(
          DateTime.now().year,
          DateTime.now().month,
          DateTime.now().day,
          pickedTime.hour,
          pickedTime.minute,
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final taskProvider = Provider.of<TaskProvider>(context, listen: false);

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Form(
        key: _formKey,
        child: Wrap(
          runSpacing: 12,
          children: [
            TextFormField(
              initialValue: taskName,
              decoration: const InputDecoration(labelText: "Title"),
              onSaved: (val) => taskName = val ?? '',
              validator: (val) => val!.isEmpty ? "Enter title" : null,
            ),
            DropdownButtonFormField<String>(
              decoration: const InputDecoration(labelText: "Difficulty"),
              value: difficulty,
              items: [
                'Easy',
                'Medium',
                'Hard',
              ].map((d) => DropdownMenuItem(value: d, child: Text(d))).toList(),
              onChanged: (val) => setState(() => difficulty = val!),
            ),
            TextFormField(
              decoration: const InputDecoration(labelText: "Reward (tokens)"),
              keyboardType: TextInputType.number,
              initialValue: reward.toString(),
              onSaved: (val) => reward = int.tryParse(val ?? '10') ?? 10,
            ),
            DropdownButtonFormField<String>(
              decoration: const InputDecoration(labelText: "Routine"),
              value: routine,
              items: [
                'Morning',
                'Afternoon',
                'Evening',
                'Anytime',
              ].map((r) => DropdownMenuItem(value: r, child: Text(r))).toList(),
              onChanged: (val) => setState(() => routine = val!),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text("Alarm Reminder"),
              subtitle: Text(
                alarmDateTime != null
                    ? "⏰ ${alarmDateTime!.hour.toString().padLeft(2, '0')}:${alarmDateTime!.minute.toString().padLeft(2, '0')}"
                    : "No alarm set",
              ),
              trailing: IconButton(
                icon: const Icon(Icons.access_time),
                onPressed: _pickAlarmTime,
              ),
            ),
            if (alarmDateTime != null)
              TextButton.icon(
                icon: const Icon(Icons.delete_forever, color: Colors.red),
                label: const Text("Remove Alarm"),
                onPressed: () => setState(() => alarmDateTime = null),
              ),
            const SizedBox(height: 16),
            Row(
              children: [
                if (widget.task != null)
                  TextButton.icon(
                    icon: const Icon(Icons.delete, color: Colors.red),
                    label: const Text("Delete"),
                    onPressed: () async {
                      final confirm = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text("Delete Task"),
                          content: const Text(
                            "Are you sure you want to delete this task?",
                          ),
                          actions: [
                            TextButton(
                              child: const Text("Cancel"),
                              onPressed: () => Navigator.pop(ctx, false),
                            ),
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.red,
                              ),
                              child: const Text("Delete"),
                              onPressed: () => Navigator.pop(ctx, true),
                            ),
                          ],
                        ),
                      );
                      if (confirm == true) {
                        await taskProvider.deleteTask(
                          widget.task!.id,
                          widget.parentId,
                          widget.childId,
                        );
                        Navigator.pop(context);
                      }
                    },
                  ),
                const Spacer(),
                ElevatedButton(
                  child: Text(
                    widget.task == null ? "Add Task" : "Save Changes",
                  ),
                  onPressed: () {
                    if (_formKey.currentState!.validate()) {
                      _formKey.currentState!.save();

                      final taskProvider = Provider.of<TaskProvider>(
                        context,
                        listen: false,
                      );

                      if (widget.task == null) {
                        // Creating a new task
                        final newTask = TaskModel(
                          id: DateTime.now().millisecondsSinceEpoch.toString(),
                          name: taskName,
                          difficulty: difficulty,
                          reward: reward,
                          routine: routine,
                          parentId: widget.parentId,
                          childId: widget.childId,
                          createdAt: DateTime.now(),
                          alarm: alarmDateTime,
                        );
                        taskProvider.addTask(newTask);
                      } else {
                        // Updating existing task — only send the changed fields
                        final updatedFields = TaskModel(
                          id: widget.task!.id,
                          name: taskName,
                          difficulty: difficulty,
                          reward: reward,
                          routine: routine,
                          parentId: widget.parentId,
                          childId: widget.childId,
                          createdAt: widget.task!.createdAt,
                          alarm: alarmDateTime,
                        );

                        taskProvider.updateTask(updatedFields);
                      }

                      Navigator.pop(context);
                    }
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
