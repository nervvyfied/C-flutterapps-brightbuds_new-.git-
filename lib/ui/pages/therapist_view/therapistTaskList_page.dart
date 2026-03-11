// ignore_for_file: file_names, deprecated_member_use, use_build_context_synchronously

import 'dart:async';
import 'package:com.brightbuds/data/models/parent_model.dart';
import 'package:com.brightbuds/data/models/task_model.dart';
import 'package:com.brightbuds/data/models/therapist_model.dart';
import 'package:com.brightbuds/data/providers/auth_provider.dart';
import 'package:com.brightbuds/data/providers/task_provider.dart';
import 'package:com.brightbuds/data/providers/selected_child_provider.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class TherapistTaskListScreen extends StatefulWidget {
  final String parentId;
  final String therapistId;
  final String creatorId;
  final String creatorType;

  const TherapistTaskListScreen({
    required this.parentId,
    required this.therapistId,
    required this.creatorId,
    required this.creatorType,
    super.key,
  });

  @override
  State<TherapistTaskListScreen> createState() =>
      _TherapistTaskListScreenState();
}

enum TaskFilter { all, done, notDone }

class _TherapistTaskListScreenState extends State<TherapistTaskListScreen> {
  TaskFilter _currentFilter = TaskFilter.all;
  Timer? _autoResetTimer;
  late SelectedChildProvider _selectedChildProv;
  late TaskProvider _taskProvider;
  StreamSubscription<QuerySnapshot>? _tasksSubscription;
  bool _isDisposed = false;

  int _getXPForDifficulty(String difficulty) {
    switch (difficulty.toLowerCase()) {
      case 'easy':
        return 5;
      case 'medium':
        return 10;
      case 'hard':
        return 20;
      default:
        return 0;
    }
  }

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final taskProvider = context.read<TaskProvider>();
      _autoResetTimer = Timer.periodic(const Duration(minutes: 5), (_) {
        if (mounted && !_isDisposed) {
          taskProvider.autoResetIfNeeded();
        }
      });
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    if (_isDisposed) return;

    // Cache providers once
    _selectedChildProv = Provider.of<SelectedChildProvider>(
      context,
      listen: false,
    );
    _taskProvider = Provider.of<TaskProvider>(context, listen: false);

    // Listen for changes in selected child
    _selectedChildProv.removeListener(_onChildChanged);
    _selectedChildProv.addListener(_onChildChanged);

    // Load tasks initially
    _loadTasksForSelectedChild();
  }

  void _onChildChanged() {
    if (_isDisposed || !mounted) return;
    _loadTasksForSelectedChild();
    _setupRealtimeListener();
  }

  void _setupRealtimeListener() {
    if (_isDisposed || !mounted) return;

    final childId = _selectedChildProv.selectedChild?['cid'];
    if (childId == null) return;

    // Cancel previous subscription
    _tasksSubscription?.cancel();

    // Create new subscription for real-time updates
    _tasksSubscription = FirebaseFirestore.instance
        .collection('users')
        .doc(widget.parentId)
        .collection('children')
        .doc(childId)
        .collection('tasks')
        .snapshots()
        .listen((snapshot) {
          if (_isDisposed || !mounted) return;

          for (var change in snapshot.docChanges) {
            switch (change.type) {
              case DocumentChangeType.added:
              case DocumentChangeType.modified:
              case DocumentChangeType.removed:
                // Trigger a refresh of tasks
                _loadTasksForSelectedChild();
                break;
            }
          }
        }, onError: (error) {});
  }

  void _loadTasksForSelectedChild() {
    if (_isDisposed || !mounted) return;

    final childId = _selectedChildProv.selectedChild?['cid'];
    if (childId == null) return;

    Future.microtask(() async {
      if (_isDisposed || !mounted) return;
      try {
        await _taskProvider.loadTasks(
          parentId: widget.parentId,
          childId: childId,
        );
      } catch (e) {
        if (mounted && !_isDisposed) {}
      }
    });
  }

  @override
  void dispose() {
    _isDisposed = true;
    _autoResetTimer?.cancel();
    _tasksSubscription?.cancel();
    _selectedChildProv.removeListener(_onChildChanged);
    super.dispose();
  }

  void _openTaskModal({TaskModel? task}) {
    if (_isDisposed || !mounted) return;

    final childId = _selectedChildProv.selectedChild?['cid'];
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
          therapistId: widget.therapistId,
          creatorType: widget.creatorType,
          creatorId: widget.creatorId,
          task: task,
        ),
      ),
    );
  }

  void _showVerifyModal(TaskModel task) {
    if (_isDisposed || !mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (modalContext) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(modalContext).viewInsets.bottom,
          ),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
              color: Colors.white,
            ),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF8657F3),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Center(
                      child: Text(
                        "Verify Quest",
                        style: TextStyle(
                          fontSize: 20,
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildDetailRow("Task Name", task.name),
                  _buildDetailRow(
                    "Time Completed",
                    task.doneAt != null
                        ? "${task.doneAt!.hour.toString().padLeft(2, '0')}:${task.doneAt!.minute.toString().padLeft(2, '0')}"
                        : "N/A",
                  ),
                  _buildDetailRow("Difficulty", task.difficulty),
                  _buildDetailRow(
                    "XP Gained",
                    "${_getXPForDifficulty(task.difficulty)} XP",
                  ),
                  _buildDetailRow(
                    "Active Streak",
                    task.activeStreak.toString(),
                  ),
                  _buildDetailRow(
                    "Longest Streak",
                    task.longestStreak.toString(),
                  ),
                  _buildDetailRow(
                    "Days Completed",
                    task.totalDaysCompleted.toString(),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      ElevatedButton(
                        onPressed: () {
                          Navigator.pop(modalContext);
                          _showRejectReasonModal(task);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 12,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text(
                          "Not Verified",
                          style: TextStyle(fontSize: 16),
                        ),
                      ),
                      ElevatedButton(
                        onPressed: () async {
                          final taskProvider = Provider.of<TaskProvider>(
                            modalContext,
                            listen: false,
                          );

                          await taskProvider.verifyTask(task.id, task.childId);
                          if (mounted && !_isDisposed) {
                            Navigator.pop(modalContext);
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 12,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text(
                          "Verify",
                          style: TextStyle(fontSize: 16),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _showRejectReasonModal(TaskModel task) {
    if (_isDisposed || !mounted) return;

    final reasonController = TextEditingController();
    final reminderController = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (modalContext) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(modalContext).viewInsets.bottom,
          ),
          child: Container(
            padding: const EdgeInsets.all(16),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "Not Verified",
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  const Text("Reason"),
                  const SizedBox(height: 6),
                  TextField(
                    controller: reasonController,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      hintText: "Explain why this task was not verified...",
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text("Reminder Message (optional)"),
                  const SizedBox(height: 6),
                  TextField(
                    controller: reminderController,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      hintText: "Encourage the child to try again...",
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Center(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 12,
                        ),
                      ),
                      onPressed: () async {
                        final reason = reasonController.text.trim();
                        final reminder = reminderController.text.trim();

                        if (reason.isEmpty) {
                          ScaffoldMessenger.of(modalContext).showSnackBar(
                            const SnackBar(
                              content: Text("Please provide a reason."),
                            ),
                          );
                          return;
                        }

                        final taskProvider = Provider.of<TaskProvider>(
                          modalContext,
                          listen: false,
                        );

                        await taskProvider.rejectTaskWithMessage(
                          taskId: task.id,
                          childId: task.childId,
                          reason: reason,
                          reminder: reminder,
                          showToChild: true,
                        );

                        if (mounted && !_isDisposed) {
                          Navigator.pop(modalContext);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text("Feedback sent to child."),
                            ),
                          );
                        }
                      },
                      child: const Text("Send"),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            "$label:",
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          Text(value, style: const TextStyle(fontSize: 16)),
        ],
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
          Column(
            children: tasks.map((task) {
              Color cardColor = Colors.white;
              if (task.verified == true) {
                cardColor = const Color.fromARGB(255, 216, 248, 154);
              } else if (task.isDone == true) {
                cardColor = const Color.fromARGB(255, 255, 234, 141);
              }
              final auth = context.read<AuthProvider>();
              final currentUserId = auth.currentUserModel?.uid ?? '';
              final currentUserType = auth.currentUserModel is ParentUser
                  ? 'parent'
                  : 'therapist';

              final canEdit =
                  task.creatorId == currentUserId &&
                  task.creatorType == currentUserType;

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
                              color: _getDifficultyColor(task.difficulty),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              task.difficulty,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Row(
                            children: [
                              const Icon(
                                Icons.flash_on,
                                size: 16,
                                color: Colors.orange,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '+${_getXPForDifficulty(task.difficulty)} XP',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      if (task.isAccepted != true)
                        Row(
                          children: [
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.blue,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 6,
                                ),
                              ),
                              onPressed: () => _showAcceptTaskModal(task),
                              child: const Text("Accept"),
                            ),
                            const SizedBox(width: 8),
                          ],
                        )
                      else if (task.verified != true && task.isDone == true)
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
                          onPressed: () => _showVerifyModal(task),
                          child: const Text("Verify"),
                        )
                      else if (task.verified == true)
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
                  trailing: canEdit
                      ? IconButton(
                          icon: const Icon(Icons.edit),
                          onPressed: () => _openTaskModal(task: task),
                        )
                      : null,
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  void _showAcceptTaskModal(TaskModel task) {
    if (_isDisposed || !mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (modalContext) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(modalContext).viewInsets.bottom,
          ),
          child: Container(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "Accept Task",
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                _buildDetailRow("Task Name", task.name),
                _buildDetailRow("Difficulty", task.difficulty),
                _buildDetailRow("Routine", task.routine),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    ElevatedButton(
                      onPressed: () {
                        Navigator.pop(modalContext);
                        _showRejectionModal(task);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 12,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        "Reject Task",
                        style: TextStyle(fontSize: 16),
                      ),
                    ),
                    ElevatedButton(
                      onPressed: () async {
                        final taskProvider = Provider.of<TaskProvider>(
                          modalContext,
                          listen: false,
                        );

                        await taskProvider.acceptTask(task.id, task.childId);
                        if (mounted && !_isDisposed) {
                          Navigator.pop(modalContext);
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 12,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        "Accept Task",
                        style: TextStyle(fontSize: 16),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showRejectionModal(TaskModel task) {
    if (_isDisposed || !mounted) return;

    final reasonController = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (modalContext) {
        final taskProvider = Provider.of<TaskProvider>(
          modalContext,
          listen: false,
        );

        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(modalContext).viewInsets.bottom,
          ),
          child: Container(
            padding: const EdgeInsets.all(16),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "Reject Task",
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  const Text("Reason for Rejection"),
                  const SizedBox(height: 6),
                  TextField(
                    controller: reasonController,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      hintText: "Explain why the task is being rejected...",
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Center(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 12,
                        ),
                      ),
                      onPressed: () async {
                        final reason = reasonController.text.trim();

                        await taskProvider.rejectTaskWithMessageForParent(
                          taskId: task.id,
                          childId: task.childId,
                          reason: reason,
                          showToChild: false,
                        );

                        if (mounted && !_isDisposed) {
                          Navigator.pop(modalContext);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                "Task rejected and parent notified.",
                              ),
                            ),
                          );
                        }
                      },
                      child: const Text("Reject Task"),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildFilterButton(String label, TaskFilter filter) {
    final selected = _currentFilter == filter;
    return GestureDetector(
      onTap: () {
        if (mounted && !_isDisposed) {
          setState(() {
            _currentFilter = filter;
          });
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF8657F3) : Colors.grey[300],
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : Colors.black87,
            fontWeight: FontWeight.bold,
            fontSize: 14,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isDisposed) return const SizedBox.shrink();

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
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                child: Text(
                  'Quests for $childName',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.black,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 4,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _buildFilterButton("All", TaskFilter.all),
                    const SizedBox(width: 6),
                    _buildFilterButton("Not Done", TaskFilter.notDone),
                    const SizedBox(width: 6),
                    _buildFilterButton("Done", TaskFilter.done),
                  ],
                ),
              ),
              const SizedBox(height: 8),
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
                      List<TaskModel> childTasks = childId != null
                          ? taskProvider.tasks
                                .where((t) => t.childId == childId)
                                .toList()
                          : <TaskModel>[];

                      switch (_currentFilter) {
                        case TaskFilter.notDone:
                          childTasks = childTasks
                              .where((t) => t.isDone != true)
                              .toList();
                          break;
                        case TaskFilter.done:
                          childTasks = childTasks
                              .where((t) => t.isDone == true)
                              .toList();
                          break;
                        case TaskFilter.all:
                          break;
                      }

                      if (taskProvider.isLoading && childTasks.isEmpty) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      if (childTasks.isEmpty) {
                        return Center(
                          child: Text("No quests assigned to $childName."),
                        );
                      }

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
  final String therapistId;
  final TaskModel? task;
  final String creatorId;
  final String creatorType;

  const TaskFormModal({
    required this.parentId,
    required this.childId,
    required this.therapistId,
    required this.creatorId,
    required this.creatorType,
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
  late String routine;
  DateTime? alarmDateTime;
  bool _isDisposed = false;

  @override
  void initState() {
    super.initState();
    taskName = widget.task?.name ?? '';
    difficulty = widget.task?.difficulty ?? 'Easy';
    routine = widget.task?.routine ?? 'Anytime';
    alarmDateTime = widget.task?.alarm;
  }

  @override
  void dispose() {
    _isDisposed = true;
    super.dispose();
  }

  Widget _buildDifficultyButton(String value, Color color) {
    final selected = difficulty == value;
    return GestureDetector(
      onTap: () {
        if (!mounted || _isDisposed) return;
        setState(() {
          difficulty = value;
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
        if (!mounted || _isDisposed) return;
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
    if (_isDisposed) return const SizedBox.shrink();

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
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
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
                          if (confirm == true && mounted && !_isDisposed) {
                            await taskProvider.deleteTask(
                              widget.task!.id,
                              widget.parentId,
                              widget.childId,
                            );
                            if (mounted && !_isDisposed) {
                              Navigator.pop(context);
                            }
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

                          final auth = context.read<AuthProvider>();

                          final isParent = auth.currentUserModel is ParentUser;
                          final isTherapist =
                              auth.currentUserModel is TherapistUser;

                          final creatorId = isParent
                              ? (auth.currentUserModel as ParentUser).uid
                              : (auth.currentUserModel as TherapistUser).uid;

                          final creatorType = isParent ? 'parent' : 'therapist';

                          final therapistId = isTherapist
                              ? creatorId
                              : widget.therapistId;

                          final task = TaskModel(
                            id:
                                widget.task?.id ??
                                DateTime.now().millisecondsSinceEpoch
                                    .toString(),
                            name: taskName,
                            difficulty: difficulty,
                            reward: 0,
                            routine: routine,
                            parentId: widget.parentId,
                            childId: widget.childId,
                            createdAt: widget.task?.createdAt ?? DateTime.now(),
                            alarm: alarmDateTime,
                            therapistId: therapistId,
                            creatorId: creatorId,
                            creatorType: creatorType,
                            isAccepted: false,
                          );

                          if (widget.task == null) {
                            taskProvider.addTask(task, context);
                          } else {
                            taskProvider.updateTask(task);
                          }

                          if (mounted && !_isDisposed) {
                            Navigator.pop(context);
                          }
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
