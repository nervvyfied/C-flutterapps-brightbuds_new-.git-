import 'package:brightbuds_new/data/managers/token_manager.dart';
import 'package:brightbuds_new/data/models/task_model.dart';
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';

class TokenNotifier extends ChangeNotifier {
  final TokenManager tokenManager;
  final Box settingsBox;
  final String childId;

  List<TaskModel> _newTasks = [];
  List<TaskModel> get newTasks => _newTasks;

  TokenNotifier(this.tokenManager, {required this.settingsBox, required this.childId});

  /// ✅ Detects tasks newly verified by the parent that the child hasn’t seen yet
  Future<List<TaskModel>> checkAndNotify() async {
  final unseenKey = 'seen_verified_tasks_$childId';
  List<String> seenIds = List<String>.from(settingsBox.get(unseenKey, defaultValue: []));

  final verifiedTasks = tokenManager.taskProvider.tasks
      .where((t) => t.verified == true && t.childId == childId)
      .toList();

  final unseenTasks = verifiedTasks.where((t) => !seenIds.contains(t.id)).toList();

  if (unseenTasks.isEmpty) return [];

  _newTasks = [..._newTasks, ...unseenTasks];
  notifyListeners(); // triggers popup

  return unseenTasks; // ✅ return them so we can mark them seen later
}


  /// ✅ Safely add tasks manually (for Firestore listener)
  void addNewlyVerifiedTasks(List<TaskModel> tasks) {
    if (tasks.isEmpty) return;

    // Merge with any existing tasks to show in the popup
    _newTasks = [
      ..._newTasks,
      ...tasks.where((t) => !_newTasks.any((nt) => nt.id == t.id)),
    ];
    notifyListeners();
  }

  /// ✅ Clear only the _newTasks cache (not seen IDs)
  void clearNewTasks() {
    _newTasks = [];
    notifyListeners();
  }
}
