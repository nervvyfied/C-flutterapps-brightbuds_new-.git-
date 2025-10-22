import 'dart:async';
import 'dart:math';
import 'package:brightbuds_new/notifications/fcm_service.dart';
import 'package:brightbuds_new/notifications/notification_service.dart';
import 'package:brightbuds_new/utils/network_helper.dart';
import 'package:flutter/foundation.dart';
import 'package:timezone/timezone.dart' as tz;
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

      if (kIsWeb) NotificationService().startWebAlarmSimulation(_tasks);

      // Schedule alarms for all tasks that have alarms set
      for (var task in _tasks) {
        if (task.alarm != null) {
          await scheduleTaskAlarm(task);
        }
      }
      // Check online and merge remote tasks
      final online = await NetworkHelper.isOnline();
      if (online && parentId != null && parentId.isNotEmpty) {
        await mergeRemoteTasks(
          parentId: parentId,
          childId: childId,
          isParent: isParent,
        );

        for (var task in _tasks) {
          if (!kIsWeb) scheduleTaskAlarm(task); // only on mobile
        }
      }
      if (kIsWeb) {
        debugPrint('🌐 [WEB DEBUG] Child tasks loaded: ${_tasks.length}');
        for (var t in _tasks) {
          debugPrint(
              '🧩 Task: ${t.name} | Done: ${t.isDone} | Alarm: ${t.alarm?.hour}:${t.alarm?.minute}');
        }

        // Start simulation
        startWebDebugSimulation();
        
      }
      debugPrint("❌ Error loading tasks: $e");

    } finally {
      await autoResetIfNeeded();
      _isLoading = false;
      notifyListeners();
    }
    debugPrint('✅ Tasks fully loaded. Count: ${_tasks.length}');
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

  // Save locally
  await _taskRepo.saveTask(newTask);
  await _taskBox?.put(newTask.id, newTask);

  _tasks.add(newTask);
  notifyListeners();

  // Schedule alarm immediately
  if (!kIsWeb) await scheduleTaskAlarm(newTask);

  if (await NetworkHelper.isOnline()) {
    try {
      // Save to Firestore
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


  Future<void> updateTask(TaskModel updatedFields) async {
  final index = _tasks.indexWhere((t) => t.id == updatedFields.id);
  if (index == -1) return;

  final oldTask = _tasks[index];
  final mergedTask = oldTask.copyWith(
    name: updatedFields.name,
    difficulty: updatedFields.difficulty,
    reward: updatedFields.reward,
    routine: updatedFields.routine,
    alarm: updatedFields.alarm,
    lastUpdated: DateTime.now(),
  );

  _tasks[index] = mergedTask;

  await _taskRepo.updateTask(mergedTask);
  await _taskBox?.put(mergedTask.id, mergedTask);
  notifyListeners();

  // Cancel old alarm and reschedule if needed
  if (!kIsWeb) {
    await cancelTaskAlarm(oldTask);
    if (mergedTask.alarm != null) {
      await scheduleTaskAlarm(mergedTask);
    }
  }

  debugPrint('📝 Task updated: ${mergedTask.name}, Alarm: ${mergedTask.alarm}');
}
  

  Future<void> deleteTask(
    String taskId,
    String parentId,
    String childId,
  ) async {
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

    if (task != null && !kIsWeb) {
    await cancelTaskAlarm(task);
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
      ? DateTime(
          task.lastCompletedDate!.year,
          task.lastCompletedDate!.month,
          task.lastCompletedDate!.day,
        )
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

  // Save locally
  await _taskRepo.saveTaskLocal(updatedTask);
  await _taskBox?.put(updatedTask.id, updatedTask);

  // Update provider list
  final index = _tasks.indexWhere((t) => t.id == taskId);
  if (index != -1) {
    _tasks[index] = updatedTask;
  } else {
    _tasks.add(updatedTask);
  }
  notifyListeners();

  // Sync changes via your existing service
  await pushPendingChanges();

  // After marking done
if (!kIsWeb && task.alarm != null) {
  await cancelTaskAlarm(task);
}

  // Update Firestore streak for this task
  await _streakRepo.updateStreak(childId, task.parentId, taskId);

  // Fetch child name from Firestore
  final childSnapshot = await FirebaseFirestore.instance
      .collection('users')
      .doc(task.parentId)
      .collection('children')
      .doc(childId)
      .get();

  final childName = childSnapshot.data()?['name'] ?? 'Your child';

  // Send notification to parent
await notifyParentCompletion(
  parentId: task.parentId,
  childName: childName,
  itemName: task.name,
  type: 'task_completed',
);
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
  if (task.alarm == null || kIsWeb) return;

  final alarmId = task.id.hashCode;

  // Cancel any existing alarm
  await NotificationService().cancelNotification(alarmId);

  final now = tz.TZDateTime.now(tz.local);
  var scheduledDate = tz.TZDateTime(
    tz.local,
    now.year,
    now.month,
    now.day,
    task.alarm!.hour,
    task.alarm!.minute,
  );

  if (scheduledDate.isBefore(now)) scheduledDate = scheduledDate.add(const Duration(days: 1));

  // Schedule local daily notification
  await NotificationService().scheduleDailyNotification(
    id: alarmId,
    title: '🧩 Task Reminder!',
    body: task.name,
    hour: task.alarm!.hour,
    minute: task.alarm!.minute,
    payload: task.id,
  );

  debugPrint('✅ Alarm scheduled for "${task.name}" at ${scheduledDate.hour}:${scheduledDate.minute}');

  // FCM push to child (optional for mobile users)
  try {
    final childSnapshot = await _firestore
        .collection('users')
        .doc(task.parentId)
        .collection('children')
        .doc(task.childId)
        .get();

    final childToken = childSnapshot.data()?['fcmToken'];
    if (childToken != null) {
      await FCMService.sendNotification(
        title: '🧩 Task Reminder!',
        body: task.name,
        token: childToken,
        data: {'type': 'task_alarm', 'taskId': task.id, 'taskName': task.name},
      );
      debugPrint('📨 FCM alarm sent to child: ${task.name}');
    }
  } catch (e) {
    debugPrint('⚠️ Failed to send FCM alarm: $e');
  }
}



Future<void> cancelTaskAlarm(TaskModel task) async {
  final alarmId = task.id.hashCode;
  await NotificationService().cancelNotification(alarmId);
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
        ? DateTime(
            task.lastCompletedDate!.year,
            task.lastCompletedDate!.month,
            task.lastCompletedDate!.day,
          )
        : null;

    int updatedActiveStreak = task.activeStreak;

    // Reset streak if last done was before yesterday
    if (lastDate != null &&
        lastDate.isBefore(todayDateOnly.subtract(const Duration(days: 1)))) {
      updatedActiveStreak = 0;
    }

    // Only reset if not done today
    if (lastDate == null || lastDate.isBefore(todayDateOnly)) {
      final updated = task.copyWith(
        isDone: false,
        verified: false,
        activeStreak: updatedActiveStreak,
        lastUpdated: DateTime.now(),
      );

      // Update task (saves locally + remotely + reschedules alarm)
      await updateTask(updated);
    }
  }

  // Sync any pending changes after reset
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

  Future<void> notifyParentCompletion({
  required String parentId,
  required String childName,
  required String itemName,
  required String type, // "task_completed" or "cbt_completed"
}) async {
  try {
    // Use the _firestore instance defined in TaskProvider
    final parentSnapshot = await _firestore.collection('users').doc(parentId).get();
    final parentToken = parentSnapshot.data()?['fcmToken'];
    if (parentToken != null) {
      await FCMService.sendNotification(
        title: type == 'task_completed' ? '🎉 Task Completed' : '🧠 CBT Completed',
        body: '$childName finished $itemName!',
        token: parentToken,
        data: {
          'type': type,
          'childName': childName,
          'itemName': itemName,
        },
      );
      debugPrint('📨 FCM sent to parent: $childName completed $itemName');
    }
  } catch (e) {
    debugPrint('⚠️ Failed to send FCM to parent: $e');
  }
}


  void startWebDebugSimulation() {
  if (!kIsWeb) return;

  debugPrint('🌐 [WEB DEBUG] Starting task alarm simulation...');

  // Run periodically
  Future.doWhile(() async {
    final now = DateTime.now();

    for (final task in _tasks) {
      if (task.alarm != null) {
        final alarmTime = DateTime(
          now.year,
          now.month,
          now.day,
          task.alarm!.hour,
          task.alarm!.minute,
        );

        // Trigger if within ±5 seconds of scheduled time
        if (now.difference(alarmTime).inSeconds.abs() <= 5) {
          debugPrint(
              '🔔 [WEB SIM] Alarm triggered for "${task.name}" at ${now.hour}:${now.minute}:${now.second}');
        }
      }
    }

    await Future.delayed(const Duration(seconds: 1));
    return true;
  });
}

}

extension TaskStats on TaskProvider {
  int get doneCount => _tasks.where((t) => t.isDone).length;
  int get notDoneCount => _tasks.where((t) => !t.isDone).length;
}
