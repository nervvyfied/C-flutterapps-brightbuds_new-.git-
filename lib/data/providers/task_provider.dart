import 'dart:async';
import 'package:brightbuds_new/notifications/notification_service.dart';
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

  Box<TaskModel>? _taskBox;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Future<void> initHive() async {
    if (!Hive.isBoxOpen('tasksBox')) {
      _taskBox = await Hive.openBox<TaskModel>('tasksBox');
    } else {
      _taskBox = Hive.box<TaskModel>('tasksBox');
    }
  }

  /// Load local tasks first, then merge remote tasks asynchronously
  Future<void> loadTasks({
  String? parentId,
  String? childId,
  bool isParent = false,
}) async {
  _isLoading = true;
  notifyListeners();

  try {
    // Load local tasks immediately
    _tasks = _taskBox?.values.toList() ?? [];
    notifyListeners(); // <-- UI updates immediately

    // Schedule alarms asynchronously (non-blocking)
    for (var task in _tasks) {
      if (!kIsWeb) scheduleTaskAlarm(task); // only on mobile
    }

    // Check online and merge remote tasks
    final online = await NetworkHelper.isOnline();
    if (online && parentId != null && parentId.isNotEmpty) {
      await mergeRemoteTasks(parentId: parentId, childId: childId, isParent: isParent);

      for (var task in _tasks) {
        if (!kIsWeb) scheduleTaskAlarm(task); // only on mobile
      }
    }
  } finally {
    await autoResetIfNeeded();
    _isLoading = false;
    notifyListeners();
  }
}

  /// Merge remote tasks over local (offline-first)
  Future<void> mergeRemoteTasks({
    required String parentId,
    String? childId,
    bool isParent = false,
  }) async {
    try {
      List<TaskModel> remoteTasks = [];

      if (isParent) {
        await _taskRepo.pullParentTasks(parentId);
        remoteTasks = _taskRepo
            .getAllTasksLocal()
            .where((t) => t.parentId == parentId)
            .toList();
      } else if (childId != null && childId.isNotEmpty) {
        await _taskRepo.pullChildTasks(parentId, childId);
        remoteTasks = _taskRepo
            .getAllTasksLocal()
            .where((t) => t.parentId == parentId && t.childId == childId)
            .toList();
      }

      final Map<String, TaskModel> merged = {for (var t in _tasks) t.id: t};
      for (var t in remoteTasks) merged[t.id] = t;

      _tasks = merged.values.toList()
        ..sort((a, b) {
          final aTime = a.lastUpdated ?? DateTime.fromMillisecondsSinceEpoch(0);
          final bTime = b.lastUpdated ?? DateTime.fromMillisecondsSinceEpoch(0);
          return bTime.compareTo(aTime);
        });

      // Save merged tasks to Hive
      for (var t in merged.values) {
        await _taskBox?.put(t.id, t);
      }

      notifyListeners();
      debugPrint('✅ Remote tasks merged: ${remoteTasks.length}');
    } catch (e) {
      debugPrint('⚠️ Firestore fetch failed: $e');
    }
  }

  // ---------------- CRUD ----------------
  Future<void> addTask(TaskModel task) async {
    final newTask = task.copyWith(
      id: task.id.isNotEmpty ? task.id : const Uuid().v4(),
      lastUpdated: DateTime.now(),
    );

    await _taskRepo.saveTask(newTask);
    await _taskBox?.put(newTask.id, newTask);

    _tasks.add(newTask);
    notifyListeners();

    await scheduleTaskAlarm(task);

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
  }

  Future<void> updateTask(TaskModel task) async {
    await _taskRepo.saveTask(task);
    await _taskBox?.put(task.id, task);

    final index = _tasks.indexWhere((t) => t.id == task.id);
    if (index != -1) _tasks[index] = task;

    notifyListeners();

    // Reschedule alarm
    await scheduleTaskAlarm(task);

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
  }


  Future<void> deleteTask(String taskId, String parentId, String childId) async {
    TaskModel? task;
    try {
      task = _tasks.firstWhere((t) => t.id == taskId);
    } catch (_) {
      task = null;
    }
  
    await _taskRepo.deleteTask(taskId, parentId, childId);
    await _taskBox?.delete(taskId);

    _tasks.removeWhere((t) => t.id == taskId);
    notifyListeners();

    // Cancel scheduled alarm
    if (task != null) {
      cancelTaskAlarm(task);
    }

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
  }

  Future<void> markTaskAsDone(String taskId, String childId) async {
    final task = _taskRepo.getTaskLocal(taskId);
    if (task == null) return;

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final lastDone = task.lastCompletedDate != null
        ? DateTime(task.lastCompletedDate!.year,
            task.lastCompletedDate!.month, task.lastCompletedDate!.day)
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
      longestStreak: newActiveStreak > task.longestStreak
          ? newActiveStreak
          : task.longestStreak,
      totalDaysCompleted: task.totalDaysCompleted + 1,
      lastUpdated: now,
    );

    await updateTask(updatedTask);

      // Cancel alarm for today
    cancelTaskAlarm(task);
  }

  Future<void> verifyTask(String taskId, String childId) async {
    final task = _taskRepo.getTaskLocal(taskId);
    if (task == null || task.verified) return;

    await _taskRepo.verifyTask(taskId, childId);

    final updatedTask = _taskRepo.getTaskLocal(taskId);
    if (updatedTask != null) await updateTask(updatedTask);
  }

  // ---------------- ALARMS ----------------
Future<void> scheduleTaskAlarm(TaskModel task) async {
  if (task.alarm == null) return;

  // Web cannot schedule local notifications
  if (kIsWeb) return;

  final now = DateTime.now();

  // Use today's date but the alarm's hour & minute
  DateTime scheduledDate = DateTime(
    now.year,
    now.month,
    now.day,
    task.alarm!.hour,
    task.alarm!.minute,
  );

  // If time has passed today, schedule for tomorrow
  if (scheduledDate.isBefore(now)) {
    scheduledDate = scheduledDate.add(const Duration(days: 1));
  }

  // Schedule asynchronously (non-blocking)
  NotificationService()
      .scheduleNotification(
        id: task.hashCode,
        title: "Time for your task!",
        body: task.name,
        scheduledDate: scheduledDate,
        payload: '${task.id}|${task.childId}|${task.parentId}|${task.childId}',
      )
      .then((_) => debugPrint('✅ Alarm scheduled for ${task.name} at $scheduledDate'))
      .catchError((e) => debugPrint('⚠️ Failed to schedule alarm: $e'));
}

void cancelTaskAlarm(TaskModel task) {
  if (kIsWeb) return; // skip on web

  try {
    NotificationService().cancelNotification(task.hashCode);
    debugPrint('❌ Alarm cancelled for ${task.name}');
  } catch (e) {
    debugPrint('⚠️ Failed to cancel alarm for ${task.name}: $e');
  }
}

  // ---------------- SYNC ----------------
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
        ? DateTime(task.lastCompletedDate!.year,
            task.lastCompletedDate!.month, task.lastCompletedDate!.day)
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

      await updateTask(updated);

      // Cancel old alarm and schedule today's alarm (mobile only)
      cancelTaskAlarm(updated);
      if (!kIsWeb) scheduleTaskAlarm(updated);
    }
  }

  await pushPendingChanges();
}

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
