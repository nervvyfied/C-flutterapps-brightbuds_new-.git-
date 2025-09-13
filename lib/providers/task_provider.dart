import 'package:brightbuds_new/data/models/child_model.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../data/models/task_model.dart';
import '../data/repositories/task_repository.dart';
import '../data/repositories/user_repository.dart';
import '../data/repositories/streak_repository.dart';
import '../data/services/sync_service.dart';

class TaskProvider extends ChangeNotifier {
  final TaskRepository _taskRepo = TaskRepository();
  final UserRepository _userRepo = UserRepository();
  final StreakRepository _streakRepo = StreakRepository();

  late final SyncService _syncService;

  TaskProvider() {
    _syncService = SyncService(_userRepo, _taskRepo, _streakRepo);
  }

  List<TaskModel> _tasks = [];
  List<TaskModel> get tasks => _tasks;

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  // ---------------- LOAD TASKS ----------------
  Future<void> loadTasks({String? parentId, String? childId}) async {
    _isLoading = true;
    notifyListeners();

    try {
      if (parentId != null) {
        await _taskRepo.pullParentTasks(parentId);
        _tasks = _taskRepo
            .getAllTasksLocal()
            .where((t) => t.parentId == parentId)
            .toList();
      } else if (childId != null) {
        await _taskRepo.pullChildTasks(childId);
        if (childId == null || childId.isEmpty) {
  _tasks = [];
} else {
  _tasks = _taskRepo.getAllTasksLocal()
      .where((t) => t.childId == childId)
      .toList();
}

      }
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // ---------------- TASK CRUD ----------------
  Future<void> addTask(TaskModel task) async {
  final newTask = task.copyWith(
    id: task.id.isNotEmpty ? task.id : const Uuid().v4(),
    lastUpdated: DateTime.now(),
  );

  await _taskRepo.saveTask(newTask);

  _tasks.add(newTask);
  notifyListeners();
}

  Future<void> updateTask(TaskModel task) async {
    await _taskRepo.saveTask(task);
    final updated = _taskRepo.getTaskLocal(task.id);
    if (updated != null) {
      final idx = _tasks.indexWhere((t) => t.id == task.id);
      if (idx != -1) _tasks[idx] = updated;
      notifyListeners();
    }
  }

  Future<void> deleteTask(String taskId) async {
    await _taskRepo.deleteTask(taskId);
    _tasks.removeWhere((t) => t.id == taskId);
    notifyListeners();
  }

  Future<void> markTaskAsDone(String taskId, String childId) async {
  final task = _taskRepo.getTaskLocal(taskId);
  if (task == null) return;

  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final lastDone = task.lastCompletedDate != null
      ? DateTime(task.lastCompletedDate!.year, task.lastCompletedDate!.month, task.lastCompletedDate!.day)
      : null;

  int newActiveStreak = 1;

  if (lastDone != null) {
    if (lastDone.add(const Duration(days: 1)) == today) {
      // consecutive
      newActiveStreak = task.activeStreak + 1;
    } else if (lastDone == today) {
      // already done today
      newActiveStreak = task.activeStreak;
    }
  }

  final updatedTask = task.copyWith(
    isDone: true,
    doneAt: now,
    lastCompletedDate: today,
    activeStreak: newActiveStreak,
    longestStreak: newActiveStreak > task.longestStreak ? newActiveStreak : task.longestStreak,
    totalDaysCompleted: task.totalDaysCompleted + 1,
    lastUpdated: now,
  );

  await _taskRepo.saveTask(updatedTask);

  final idx = _tasks.indexWhere((t) => t.id == taskId);
  if (idx != -1) _tasks[idx] = updatedTask;
  notifyListeners();
}


  Future<void> verifyTask(String taskId, String childId) async {
  final task = _taskRepo.getTaskLocal(taskId);
  if (task == null || task.verified) return;

  await _taskRepo.verifyTask(taskId, childId);

  // Update local list after verification
  final updatedTask = _taskRepo.getTaskLocal(taskId);
  if (updatedTask != null) {
    final idx = _tasks.indexWhere((t) => t.id == taskId);
    if (idx != -1) _tasks[idx] = updatedTask;
  }

  notifyListeners();
}


  // ---------------- SYNC ----------------
  /// Call when user logs in
  Future<void> syncOnLogin({
  String? uid,
  String? accessCode,
  required bool isParent,
}) async {
  _isLoading = true;
  notifyListeners();

  try {
    // Perform sync via SyncService
    await _syncService.syncOnLogin(
      uid: uid,
      accessCode: accessCode,
      isParent: isParent,
    );

    // Reload tasks locally after sync
    if (isParent && uid != null) {
      // Parent login: load tasks by parentId
      await loadTasks(parentId: uid);
    } else if (!isParent && accessCode != null) {
      // Child login: get parent & child info first
      final result = await _userRepo.fetchParentAndChildByAccessCode(accessCode);
ChildUser? child;
if (result != null) {
  child = result['child'] as ChildUser?;
}

if (child != null) {
  await loadTasks(childId: child.cid);
}

    }
  } catch (e) {
    if (kDebugMode) {
      print('Error during syncOnLogin: $e');
    }
  } finally {
    _isLoading = false;
    notifyListeners();
  }
}


  /// Optional: manually push pending changes to Firestore
  Future<void> pushPendingChanges() async {
    await _syncService.syncAllPendingChanges();
    notifyListeners();
  }

  Future<void> resetDailyTasks() async {
  final today = DateTime.now();
  final todayDateOnly = DateTime(today.year, today.month, today.day);

  for (var task in _tasks) {
    final lastDate = task.lastCompletedDate != null
        ? DateTime(task.lastCompletedDate!.year, task.lastCompletedDate!.month, task.lastCompletedDate!.day)
        : null;

    int updatedActiveStreak = task.activeStreak;

    // missed a day → reset streak
    if (lastDate != null && lastDate.isBefore(todayDateOnly.subtract(const Duration(days: 1)))) {
      updatedActiveStreak = 0;
    }

    if (lastDate == null || lastDate.isBefore(todayDateOnly)) {
      final updated = task.copyWith(
        isDone: false,
        verified: false,
        activeStreak: updatedActiveStreak,
      );
      await _taskRepo.saveTask(updated);
      final idx = _tasks.indexWhere((t) => t.id == task.id);
      if (idx != -1) _tasks[idx] = updated;
    }
  }
  notifyListeners();
}


}
