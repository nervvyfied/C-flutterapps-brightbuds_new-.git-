import 'package:brightbuds_new/data/managers/token_manager.dart';
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:brightbuds_new/data/models/task_model.dart';

class TokenNotifier extends ChangeNotifier {
  final TokenManager tokenManager;
  final Box settingsBox;
  final String childId;

  List<TaskModel> _newTasks = [];
  List<TaskModel> get newTasks => _newTasks;

  TokenNotifier(this.tokenManager, {required this.settingsBox, required this.childId});

  /// Initialize lastSeen to prevent old tasks from triggering notifications
  void initLastSeen() {
    final lastSeenKey = 'lastSeenVerifiedTaskTimestamp_$childId';
    final lastSeen = settingsBox.get(lastSeenKey, defaultValue: 0);

    final allTasks = tokenManager.taskProvider.tasks;
    final latest = allTasks
        .where((t) => t.verified ?? false)
        .map((t) => t.lastUpdated?.millisecondsSinceEpoch ?? 0)
        .fold(lastSeen, (a, b) => a > b ? a : b);

    settingsBox.put(lastSeenKey, latest);
  }

  void clearNewTasks() {
  _newTasks.clear();
  notifyListeners();
}


  /// Check for newly verified tasks after init
  void checkAndNotify() {
    final allTasks = tokenManager.taskProvider.tasks;
    final lastSeenKey = 'lastSeenVerifiedTaskTimestamp_$childId';
    final lastSeen = settingsBox.get(lastSeenKey, defaultValue: 0);

    _newTasks = allTasks.where((task) {
      final updated = task.lastUpdated?.millisecondsSinceEpoch ?? 0;
      return (task.verified ?? false) && updated > lastSeen;
    }).toList();

    if (_newTasks.isNotEmpty) {
      final latest = _newTasks
          .map((t) => t.lastUpdated?.millisecondsSinceEpoch ?? 0)
          .reduce((a, b) => a > b ? a : b);

      settingsBox.put(lastSeenKey, latest); // mark new tasks as seen
      notifyListeners();
    }
  }
}
