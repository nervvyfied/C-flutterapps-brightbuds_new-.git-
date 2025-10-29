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
  late SelectedChildProvider _selectedChildProv;
  late TaskProvider _taskProvider;

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final taskProvider = context.read<TaskProvider>();
      _autoResetTimer = Timer.periodic(const Duration(minutes: 5), (_) {
        if (mounted) {
          taskProvider.autoResetIfNeeded();
        }
      });
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    // Cache providers once
    _selectedChildProv = Provider.of<SelectedChildProvider>(
      context,
      listen: false,
    );
    _taskProvider = Provider.of<TaskProvider>(context, listen: false);

    // Listen for changes in selected child
    _selectedChildProv.removeListener(_loadTasksForSelectedChild);
    _selectedChildProv.addListener(_loadTasksForSelectedChild);

    // Load tasks initially
    _loadTasksForSelectedChild();
  }

  void _loadTasksForSelectedChild() {
    if (!mounted) return;

    final childId = _selectedChildProv.selectedChild?['cid'];
    if (childId == null) return;

    final taskProvider =
        _taskProvider; // already cached in didChangeDependencies

    Future.microtask(() async {
      if (!mounted) return;
      try {
        await taskProvider.loadTasks(
          parentId: widget.parentId,
          childId: childId,
        );
      } catch (e) {
        if (mounted) debugPrint("Error loading tasks: $e");
      }
    });
  }

  @override
  void dispose() {
    _autoResetTimer?.cancel();
    _selectedChildProv.removeListener(_loadTasksForSelectedChild);
    super.dispose();
  }

  void _openTaskModal({TaskModel? task}) {
    final childId = _selectedChildProv.selectedChild?['cid'];
    if (childId == null) return;

    if (!mounted) return;

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

  Map<String, List<TaskModel>> _groupTasksByTime(List<TaskModel> tasks) {
    final Map<String, List<TaskModel>> grouped = {
      'Morning': [],
      'Afternoon': [],
      'Evening': [],
      'Anytime': [],
    };

    for (var task in tasks) {
      switch (task.routine.toLowerCase()) {
        case 'morning':
          grouped['Morning']!.add(task);
          break;
        case 'afternoon':
          grouped['Afternoon']!.add(task);
          break;
        case 'evening':
          grouped['Evening']!.add(task);
          break;
        default:
          grouped['Anytime']!.add(task);
      }
    }
    return grouped;
  }

  Color _getDifficultyColor(String difficulty) {
    switch (difficulty.toLowerCase()) {
      case 'easy':
        return const Color(0xFFA6C26F);
      case 'medium':
        return const Color(0xFFFECE00);
      case 'hard':
        return const Color(0xFFFD5C68);
      default:
        return Colors.grey;
    }
  }

  Widget _buildTaskGroup(String title, List<TaskModel> tasks) {
    if (tasks.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 16),
      child: Column(
        children: [
          // Title container
          Container(
            padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
            decoration: BoxDecoration(
              color: const Color(0xFF8657F3),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Center(
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          // Tasks
          Column(
            children: tasks.map((task) {
              Color cardColor = Colors.white;
              if (task.verified) {
                cardColor = const Color.fromARGB(255, 216, 248, 154); // Green
              } else if (task.isDone) {
                cardColor = const Color.fromARGB(255, 255, 234, 141); // Yellow
              }

              return Card(
                color: cardColor,
                margin: const EdgeInsets.symmetric(vertical: 6),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                child: ListTile(
                  title: Text(task.name),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: _getDifficultyColor(
                                task.difficulty ?? 'Easy',
                              ),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              task.difficulty ?? 'Easy',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Row(
                            children: [
                              Image.asset(
                                'assets/coin.png',
                                width: 16,
                                height: 16,
                              ),
                              const SizedBox(width: 4),
                              Text('${task.reward ?? 0}'),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      if (!task.verified && task.isDone)
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF8657F3),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                          ),
                          onPressed: () {
                            if (!mounted) return;
                            final taskProvider = Provider.of<TaskProvider>(
                              context,
                              listen: false,
                            );
                            taskProvider.verifyTask(task.id, task.childId);
                          },
                          child: const Text("Verify"),
                        )
                      else if (task.verified)
                        const Text(
                          "✅ Verified",
                          style: TextStyle(
                            color: Colors.green,
                            fontWeight: FontWeight.bold,
                          ),
                        )
                      else
                        const Text(
                          "⏳ Pending",
                          style: TextStyle(
                            color: Colors.orange,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                    ],
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.edit),
                    onPressed: () => _openTaskModal(task: task),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final selectedChildProv = Provider.of<SelectedChildProvider>(context);
    final childId = selectedChildProv.selectedChild?['cid'];
    final childName = selectedChildProv.selectedChild?['name'] ?? 'No Child';

    return Scaffold(
      body: Stack(
        children: [
          Image.asset(
            'assets/general_bg.png',
            fit: BoxFit.cover,
            width: double.infinity,
            height: double.infinity,
          ),
          Column(
            children: [
              const SizedBox(height: 40),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    Text(
                      'Quests for $childName',
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.black,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    vertical: 12,
                    horizontal: 12,
                  ),
                  decoration: const BoxDecoration(
                    color: Color.fromARGB(235, 255, 255, 255),
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(24),
                    ),
                  ),
                  child: Consumer<TaskProvider>(
                    builder: (context, taskProvider, _) {
                      final List<TaskModel> childTasks = childId != null
                          ? taskProvider.tasks
                                .where((t) => t.childId == childId)
                                .toList()
                          : <TaskModel>[];

                      if (taskProvider.isLoading)
                        return const Center(child: CircularProgressIndicator());
                      if (childTasks.isEmpty)
                        return Center(
                          child: Text("No quests assigned to $childName."),
                        );

                      final grouped = _groupTasksByTime(childTasks);

                      return RefreshIndicator(
                        onRefresh: () async => _loadTasksForSelectedChild(),
                        child: ListView(
                          children: [
                            _buildTaskGroup('Morning', grouped['Morning']!),
                            _buildTaskGroup('Afternoon', grouped['Afternoon']!),
                            _buildTaskGroup('Evening', grouped['Evening']!),
                            _buildTaskGroup('Anytime', grouped['Anytime']!),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openTaskModal(),
        backgroundColor: const Color(0xFF8657F3),
        foregroundColor: Colors.white,
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

  late final TextEditingController _rewardController = TextEditingController();

  final Map<String, int> defaultTokens = {'Easy': 3, 'Medium': 5, 'Hard': 25};

  @override
  void initState() {
    super.initState();
    taskName = widget.task?.name ?? '';
    difficulty = widget.task?.difficulty ?? 'Easy';
    reward = widget.task?.reward ?? defaultTokens[difficulty]!;
    routine = widget.task?.routine ?? 'Anytime';
    alarmDateTime = widget.task?.alarm;

    _rewardController.text = reward.toString();
  }

  @override
  void dispose() {
    _rewardController.dispose();
    super.dispose();
  }

  Future<void> _pickAlarmTime() async {
    final pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(alarmDateTime ?? DateTime.now()),
    );
    if (pickedTime != null) {
      if (!mounted) return; // safety check
      {
        alarmDateTime = DateTime(
          DateTime.now().year,
          DateTime.now().month,
          DateTime.now().day,
          pickedTime.hour,
          pickedTime.minute,
        );
      }
    }
  }

  Widget _buildDifficultyButton(String value, Color color) {
    final selected = difficulty == value;
    return GestureDetector(
      onTap: () {
        if (!mounted) return;
        setState(() {
          difficulty = value;
          reward = defaultTokens[difficulty]!; // auto-set tokens
          _rewardController.text = reward.toString(); // update field
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        margin: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(
          color: selected ? color : color.withOpacity(0.3),
          borderRadius: BorderRadius.circular(8),
          border: selected ? Border.all(color: Colors.black, width: 2) : null,
        ),
        child: Text(
          value,
          style: TextStyle(
            color: selected ? Colors.white : Colors.black87,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Widget _buildRoutineButton(String value) {
    final selected = routine == value;
    return GestureDetector(
      onTap: () {
        if (!mounted) return;
        setState(() => routine = value);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        margin: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF8657F3) : Colors.grey[300],
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          value,
          style: TextStyle(
            color: selected ? Colors.white : Colors.black87,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final taskProvider = Provider.of<TaskProvider>(context, listen: false);

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
        top: 0,
      ),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: const BoxDecoration(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment:
                  CrossAxisAlignment.center, // center everything
              children: [
                // Header
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF8657F3),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Center(
                    child: Text(
                      widget.task == null ? "Add Quest" : "Edit Quest",
                      style: const TextStyle(
                        fontSize: 20,
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Task Name
                TextFormField(
                  textAlign: TextAlign.center,
                  initialValue: taskName,
                  decoration: InputDecoration(
                    label: Align(
                      alignment: Alignment.center,
                      child: Text(
                        "Title",
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                  onSaved: (val) => taskName = val ?? '',
                  validator: (val) => val!.isEmpty ? "Enter title" : null,
                ),
                const SizedBox(height: 16),

                // Difficulty row
                Text(
                  "Difficulty",
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _buildDifficultyButton('Easy', const Color(0xFFA6C26F)),
                    _buildDifficultyButton('Medium', const Color(0xFFFECE00)),
                    _buildDifficultyButton('Hard', const Color(0xFFFD5C68)),
                  ],
                ),
                const SizedBox(height: 16),

                // Reward container
                Text(
                  "Reward (tokens)",
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Image.asset('assets/coin.png', width: 24, height: 24),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 80,
                      child: TextFormField(
                        controller: _rewardController,
                        textAlign: TextAlign.center,
                        keyboardType: TextInputType.number,
                        onSaved: (val) =>
                            reward = int.tryParse(val ?? '0') ?? 0,
                        decoration: const InputDecoration(
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Routine row
                Text("Routine", style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _buildRoutineButton('Morning'),
                    _buildRoutineButton('Afternoon'),
                    _buildRoutineButton('Evening'),
                    _buildRoutineButton('Anytime'),
                  ],
                ),
                const SizedBox(height: 12),

                // // Alarm
                // ListTile(
                //   contentPadding: EdgeInsets.zero,
                //   title: const Text("Alarm Reminder"),
                //   subtitle: Text(
                //     alarmDateTime != null
                //         ? "⏰ ${alarmDateTime!.hour.toString().padLeft(2, '0')}:${alarmDateTime!.minute.toString().padLeft(2, '0')}"
                //         : "No alarm set",
                //   ),
                //   trailing: IconButton(
                //     icon: const Icon(Icons.access_time),
                //     onPressed: _pickAlarmTime,
                //   ),
                // ),
                // if (alarmDateTime != null)
                //   TextButton.icon(
                //     icon: const Icon(Icons.delete_forever, color: Colors.red),
                //     label: const Text("Remove Alarm"),
                //     onPressed: () => setState(() => alarmDateTime = null),
                //   ),
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
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFA6C26F),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 12,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
                        widget.task == null ? "Add Quest" : "Save Changes",
                      ),
                      onPressed: () {
                        if (_formKey.currentState!.validate()) {
                          _formKey.currentState!.save();

                          if (widget.task == null) {
                            final newTask = TaskModel(
                              id: DateTime.now().millisecondsSinceEpoch
                                  .toString(),
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
                            final updatedTask = TaskModel(
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
                            taskProvider.updateTask(updatedTask);
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
        ),
      ),
    );
  }
}
