import 'package:brightbuds_new/aquarium/manager/unlockManager.dart';
import 'package:brightbuds_new/data/models/task_model.dart';
import 'package:brightbuds_new/data/providers/auth_provider.dart';
import 'package:brightbuds_new/data/providers/task_provider.dart';
import 'package:brightbuds_new/ui/pages/role_page.dart';
import 'package:brightbuds_new/utils/network_helper.dart';
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
  bool _isOffline = false;
  bool _isSyncing = false;

  @override
  void initState() {
    super.initState();
    _loadTasksOnce();
  }

  Future<void> _checkConnectivity() async {
    final online = await NetworkHelper.isOnline();
    if (!mounted) return;
    setState(() => _isOffline = !online);
  }

  Future<void> _loadTasksOnce() async {
    final taskProvider = Provider.of<TaskProvider>(context, listen: false);

    await taskProvider.initHive();

    await taskProvider.loadTasks(
        parentId: widget.parentId, childId: widget.childId);

    await _checkConnectivity();

    if (!_isOffline) {
      setState(() => _isSyncing = true);

      await taskProvider.pushPendingChanges();

      await taskProvider.mergeRemoteTasks(
        parentId: widget.parentId,
        childId: widget.childId,
      );

      if (mounted) setState(() => _isSyncing = false);
    }
  }

  /// Group tasks by time of day
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

  Widget _buildTaskGroupCard(String title, List<TaskModel> tasks,
      UnlockManager unlockManager, bool isOffline) {
    if (tasks.isEmpty) return const SizedBox.shrink();

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      child: ExpansionTile(
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        children: tasks.map((task) {
          return ListTile(
            title: Text(task.name),
            subtitle: Text("Routine: ${task.routine} • Reward: ${task.reward} tokens"),
            trailing: task.isDone
                ? (task.verified
                    ? const Icon(Icons.verified, color: Colors.blue)
                    : const Icon(Icons.check, color: Colors.green))
                : ElevatedButton(
                    onPressed: () async {
                      await Provider.of<TaskProvider>(context, listen: false)
                          .markTaskAsDone(task.id, widget.childId);
                      unlockManager.checkUnlocks();

                      if (!isOffline) {
                        await Provider.of<TaskProvider>(context, listen: false)
                            .pushPendingChanges();
                      }
                    },
                    child: const Text("Done"),
                  ),
          );
        }).toList(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final unlockManager = context.read<UnlockManager>();

    return Scaffold(
      appBar: AppBar(
        title: Text("Hello, ${widget.childName}"),
        automaticallyImplyLeading: false,
        backgroundColor: _isOffline ? Colors.grey : null,
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
      body: Column(
        children: [
          if (_isOffline)
            Container(
              width: double.infinity,
              color: Colors.redAccent,
              padding: const EdgeInsets.all(8),
              child: const Text(
                "You're offline. Changes will sync automatically when online.",
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white, fontSize: 13),
              ),
            ),
          Expanded(
            child: Consumer<TaskProvider>(
              builder: (context, taskProvider, _) {
                final childTasks = taskProvider.tasks
                    .where((task) => task.childId == widget.childId && task.name.isNotEmpty)
                    .toList();

                if (childTasks.isEmpty) {
                  return const Center(child: Text("No tasks to display"));
                }

                final groupedTasks = _groupTasksByTime(childTasks);

                return RefreshIndicator(
                  onRefresh: _loadTasksOnce,
                  child: ListView(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    children: [
                      _buildTaskGroupCard(
                          'Morning', groupedTasks['Morning']!, unlockManager, _isOffline),
                      _buildTaskGroupCard('Afternoon', groupedTasks['Afternoon']!,
                          unlockManager, _isOffline),
                      _buildTaskGroupCard(
                          'Evening', groupedTasks['Evening']!, unlockManager, _isOffline),
                      _buildTaskGroupCard(
                          'Anytime', groupedTasks['Anytime']!, unlockManager, _isOffline),
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
