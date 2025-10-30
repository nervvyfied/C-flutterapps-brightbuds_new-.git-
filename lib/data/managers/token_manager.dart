import 'package:brightbuds_new/data/models/task_model.dart';
import 'package:brightbuds_new/data/providers/task_provider.dart';
import 'package:hive/hive.dart';

class TokenManager {
  final TaskProvider taskProvider;
  final Box settingsBox;
  final String childId;

  TokenManager({
    required this.taskProvider,
    required this.settingsBox,
    required this.childId,
  });

  List<TaskModel> checkNewTokens() {
    final lastSeenKey = 'lastSeenVerifiedTaskTimestamp_$childId';
    final lastSeen = settingsBox.get(lastSeenKey, defaultValue: 0);

    final newTasks = taskProvider.tasks.where((task) {
      final updatedTime = task.lastUpdated?.millisecondsSinceEpoch ?? 0;
      return (task.verified) && updatedTime > lastSeen;
    }).toList();

    if (newTasks.isNotEmpty) {
      final latestTimestamp = newTasks
          .map((t) => t.lastUpdated?.millisecondsSinceEpoch ?? 0)
          .reduce((a, b) => a > b ? a : b);
      settingsBox.put(lastSeenKey, latestTimestamp);
    }

    return newTasks;
  }
}
