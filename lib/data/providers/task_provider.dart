import 'package:brightbuds_new/data/models/child_model.dart';
import 'package:brightbuds_new/data/models/parent_model.dart';
import 'package:brightbuds_new/utils/network_helper.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import 'package:hive/hive.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/task_model.dart';
import '../repositories/task_repository.dart';
import '../repositories/user_repository.dart';
import '../repositories/streak_repository.dart';
import '../services/sync_service.dart';
import 'dart:async';

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

  Timer? _midnightTimer;
  DateTime? _lastResetDate;

  // ---------------- HIVE + FIRESTORE ----------------
  Box<TaskModel>? _taskBox;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Initialize Hive box (must be called before using tasks)
  Future<void> initHive() async {
    if (!Hive.isBoxOpen('tasksBox')) {
      _taskBox = await Hive.openBox<TaskModel>('tasksBox');
    } else {
      _taskBox = Hive.box<TaskModel>('tasksBox');
    }
  }

  // ---------------- LOAD TASKS ----------------
  Future<void> loadTasks({String? parentId, String? childId, bool isParent = false}) async {
    _isLoading = true;
    notifyListeners();

    try {
      // Load Hive cache first
      _tasks = _taskBox?.values.toList() ?? [];
      notifyListeners();

      // Load from repository
      if (isParent && parentId != null && parentId.isNotEmpty) {
        await _taskRepo.pullParentTasks(parentId);
        _tasks = _taskRepo
            .getAllTasksLocal()
            .where((t) => t.parentId == parentId)
            .toList();
      } else if (!isParent && parentId != null && childId != null && parentId.isNotEmpty && childId.isNotEmpty) {
        await _taskRepo.pullChildTasks(parentId, childId);
        _tasks = _taskRepo
            .getAllTasksLocal()
            .where((t) => t.parentId == parentId && t.childId == childId)
            .toList();
      } else {
        debugPrint("⚠️ loadTasks skipped: parentId=$parentId, childId=$childId");
        _tasks = [];
      }

      // Firestore sync if online
      if (childId != null && await NetworkHelper.isOnline()) {
        try {
          final snapshot = await _firestore
              .collection('users')
              .doc(parentId)
              .collection('children')
              .doc(childId)
              .collection('tasks')
              .get();
          final firestoreTasks = snapshot.docs
              .map((doc) => TaskModel.fromFirestore(doc.data(), doc.id))
              .toList();

          await _taskBox?.clear();
          await _taskBox?.addAll(firestoreTasks);

          _tasks = firestoreTasks;
          notifyListeners();
        } catch (e) {
          debugPrint('⚠️ Firestore task fetch failed: $e');
        }
      }
    } finally {
      await autoResetIfNeeded();
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

    // Hive
    await _taskBox?.add(newTask);

    // Firestore
    if (await NetworkHelper.isOnline()) {
      try {
        await _firestore
            .collection('users')
            .doc(newTask.parentId)
            .collection('children')
            .doc(newTask.childId)
            .collection('tasks')
            .doc(newTask.id)
            .set(newTask.toMap());
      } catch (e) {
        debugPrint('⚠️ Firestore addTask failed: $e');
      }
    }

    _tasks.add(newTask);
    notifyListeners();
  }

  Future<void> updateTask(TaskModel task) async {
    await _taskRepo.saveTask(task);

    // Hive update using key
    final key = _taskBox?.keys.firstWhere(
      (k) => _taskBox?.get(k)?.id == task.id,
      orElse: () => null,
    );
    if (key != null) await _taskBox?.put(key, task);

    // Firestore update
    if (await NetworkHelper.isOnline()) {
      try {
        await _firestore
            .collection('users')
            .doc(task.parentId)
            .collection('children')
            .doc(task.childId)
            .collection('tasks')
            .doc(task.id)
            .set(task.toMap());
      } catch (e) {
        debugPrint('⚠️ Firestore updateTask failed: $e');
      }
    }

    final updated = _taskRepo.getTaskLocal(task.id);
    if (updated != null) {
      final i = _tasks.indexWhere((t) => t.id == task.id);
      if (i != -1) _tasks[i] = updated;
    }
    notifyListeners();
  }

  Future<void> deleteTask(String taskId, String parentId, String childId) async {
    await _taskRepo.deleteTask(taskId, parentId, childId);

    // Hive delete using key
    final keyToDelete = _taskBox?.keys.firstWhere(
      (k) => _taskBox?.get(k)?.id == taskId,
      orElse: () => null,
    );
    if (keyToDelete != null) await _taskBox?.delete(keyToDelete);

    // Firestore delete
    if (await NetworkHelper.isOnline()) {
      try {
        await _firestore
            .collection('users')
            .doc(parentId)
            .collection('children')
            .doc(childId)
            .collection('tasks')
            .doc(taskId)
            .delete();
      } catch (e) {
        debugPrint('⚠️ Firestore deleteTask failed: $e');
      }
    }

    _tasks.removeWhere((t) => t.id == taskId);
    notifyListeners();
  }

  // ---------------- MARK DONE / VERIFY ----------------
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
        newActiveStreak = task.activeStreak + 1;
      } else if (lastDone == today) {
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

    await updateTask(updatedTask); // Hive + Firestore
  }

  Future<void> verifyTask(String taskId, String childId) async {
    final task = _taskRepo.getTaskLocal(taskId);
    if (task == null || task.verified) return;

    await _taskRepo.verifyTask(taskId, childId);

    final updatedTask = _taskRepo.getTaskLocal(taskId);
    if (updatedTask != null) await updateTask(updatedTask);
  }

  // ---------------- SYNC ----------------
  Future<void> syncOnLogin({
    String? uid,
    String? accessCode,
    required bool isParent,
  }) async {
    _isLoading = true;
    notifyListeners();

    try {
      await _syncService.syncOnLogin(uid: uid, accessCode: accessCode, isParent: isParent);

      if (isParent && uid != null) {
        await loadTasks(parentId: uid, isParent: true);
      } else if (!isParent && accessCode != null) {
        final result = await _userRepo.fetchParentAndChildByAccessCode(accessCode);
        if (result != null) {
          final parent = result['parent'] as ParentUser?;
          final child = result['child'] as ChildUser?;
          if (parent != null && child != null) {
            await loadTasks(parentId: parent.uid, childId: child.cid, isParent: false);
          }
        }
      }

      await resetDailyTasks();
      startDailyResetScheduler();
    } catch (e) {
      if (kDebugMode) print('Error during syncOnLogin: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> pushPendingChanges() async {
    await _syncService.syncAllPendingChanges();
    notifyListeners();
  }

  // ---------------- DAILY RESET ----------------
  Future<void> resetDailyTasks() async {
    final today = DateTime.now();
    final todayDateOnly = DateTime(today.year, today.month, today.day);

    for (var task in _tasks) {
      final lastDate = task.lastCompletedDate != null
          ? DateTime(task.lastCompletedDate!.year, task.lastCompletedDate!.month, task.lastCompletedDate!.day)
          : null;

      int updatedActiveStreak = task.activeStreak;
      if (lastDate != null &&
          lastDate.isBefore(todayDateOnly.subtract(const Duration(days: 1)))) {
        updatedActiveStreak = 0;
      }

      if (lastDate == null || lastDate.isBefore(todayDateOnly)) {
        final updated = task.copyWith(
          isDone: false,
          verified: false,
          activeStreak: updatedActiveStreak,
          lastUpdated: DateTime.now(),
        );
        await updateTask(updated); // Hive + Firestore
      }
    }

    await pushPendingChanges();
    notifyListeners();
  }

  // ---------------- MIDNIGHT SCHEDULER ----------------
  void startDailyResetScheduler() {
    _midnightTimer?.cancel();

    final now = DateTime.now();
    final nextMidnight = DateTime(now.year, now.month, now.day + 1);
    final duration = nextMidnight.difference(now);

    _midnightTimer = Timer(duration, () async {
      await resetDailyTasks();
      startDailyResetScheduler();
    });
  }

  void stopDailyResetScheduler() {
    _midnightTimer?.cancel();
    _midnightTimer = null;
  }

  @override
  void dispose() {
    stopDailyResetScheduler();
    super.dispose();
  }

  Future<void> autoResetIfNeeded() async {
    final today = DateTime.now();
    final todayDateOnly = DateTime(today.year, today.month, today.day);

    if (_lastResetDate == null || _lastResetDate!.isBefore(todayDateOnly)) {
      await resetDailyTasks();
      _lastResetDate = todayDateOnly;
    }
  }
}

extension TaskStats on TaskProvider {
  int get doneCount => _tasks.where((t) => t.isDone).length;
  int get notDoneCount => _tasks.where((t) => !t.isDone).length;
}
