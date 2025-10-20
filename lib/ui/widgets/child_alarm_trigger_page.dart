import 'package:brightbuds_new/notifications/notification_service.dart';
import 'package:brightbuds_new/ui/pages/child_view/childTaskView_page.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '/data/models/task_model.dart';
import '/data/providers/task_provider.dart';

class ChildAlarmTriggerPage extends StatelessWidget {
  final TaskModel task;
  final String childId;
  final String parentId;
  final String childName;

  const ChildAlarmTriggerPage({
    required this.task,
    required this.childId,
    required this.parentId,
    required this.childName,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final taskProvider = context.read<TaskProvider>();
    final actualTask = taskProvider.tasks.firstWhere(
      (t) => t.id == task.id,
      orElse: () => task,
    );

    return Scaffold(
      backgroundColor: Colors.blue.shade100,
      body: SafeArea(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.alarm, size: 100, color: Colors.orangeAccent),
            const SizedBox(height: 20),
            const Text(
              "Time for your task!",
              style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            Text(
              actualTask.name,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 10),
            Text(
              "Routine: ${actualTask.routine} • Reward: ${actualTask.reward} tokens",
              style: const TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 40),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton(
                    onPressed: () async {
                      final snoozeTime = DateTime.now().add(const Duration(minutes: 5));
                      await NotificationService().scheduleNotification(
                        id: task.hashCode,
                        title: "Time for your task!",
                        body: task.name,
                        scheduledDate: snoozeTime,
                        payload: '${task.id}|${childId}|${parentId}',
                      );
                      Navigator.pop(context);
                    },
                    child: const Text("Snooze 5 min"),
                  ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green.shade600,
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  ),
                  onPressed: () {
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ChildQuestsPage(
                          parentId: parentId,
                          childId: childId,
                          childName: childName,
                        ),
                      ),
                    );
                  },
                  child: const Text("Do Now"),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
