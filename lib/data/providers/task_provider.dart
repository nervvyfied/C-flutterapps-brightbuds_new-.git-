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
  Box<DateTime>? _settingsBox;

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  StreamSubscription<QuerySnapshot>? _firestoreSubscription;

  /// Initialize Hive and start scheduler + Firestore listener
  Future<void> initHive() async {
    _settingsBox = await Hive.openBox('settingsBox');

    if (!Hive.isBoxOpen('tasksBox')) {
      _taskBox = await Hive.openBox<TaskModel>('tasksBox');
    } else {
      _taskBox = Hive.box<TaskModel>('tasksBox');
    }

    _lastResetDate = _settingsBox?.get('lastResetDate');
    startDailyResetScheduler();
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
      // Load local tasks immediately, prevent duplicates
      final localTasks = _taskBox?.values.toList() ?? [];
      final Map<String, TaskModel> taskMap = {
        for (var t in localTasks) t.id: t,
      };
      _tasks = taskMap.values.toList();

      notifyListeners(); // <-- UI updates immediately

      if (kIsWeb) NotificationService().startWebAlarmSimulation(_tasks);

      // Schedule alarms for all tasks that have alarms set
      for (var task in _tasks) {
        if (task.alarm != null) await scheduleTaskAlarm(task);
      }

      // Real-time sync: listen to Firestore changes
      if (parentId != null && parentId.isNotEmpty) {
        _startFirestoreListener(parentId, childId, isParent);
      }
      for (var task in _tasks) {
        if (!kIsWeb) await scheduleTaskAlarm(task); // only on mobile
      }

      if (kIsWeb) startWebDebugSimulation();
    } finally {
      await autoResetIfNeeded();
      _isLoading = false;
      notifyListeners();
      final uniqueMap = {for (var t in _tasks) t.id: t};
      _tasks = uniqueMap.values.toList();
      debugPrint('✅ Tasks fully loaded. Count: ${_tasks.length}');
    }
  }

  /// Firestore real-time listener for tasks
  void _startFirestoreListener(
    String parentId,
    String? childId,
    bool isParent,
  ) {
    _firestoreSubscription?.cancel();
    CollectionReference tasksRef;

    if (isParent) {
      tasksRef = _firestore
          .collection('users')
          .doc(parentId)
          .collection('tasks');
    } else if (childId != null && childId.isNotEmpty) {
      tasksRef = _firestore
          .collection('users')
          .doc(parentId)
          .collection('children')
          .doc(childId)
          .collection('tasks');
    } else {
      return;
    }

    _firestoreSubscription = tasksRef.snapshots().listen((snapshot) async {
      bool updated = false;

      for (var docChange in snapshot.docChanges) {
        final doc = docChange.doc;
        final data = doc.data() as Map<String, dynamic>?;
        if (data == null) continue;

        final task = TaskModel.fromMap(data);
        final index = _tasks.indexWhere((t) => t.id == task.id);

        if (docChange.type == DocumentChangeType.removed) {
          if (index != -1) {
            _tasks.removeAt(index);
            await _taskBox?.delete(task.id);
            updated = true;
          }
        } else {
          // Handle added or modified
          if (index != -1) {
            // Replace existing task with the new version
            _tasks[index] = task;
            await _taskBox?.put(task.id, task);
          } else {
            // Add new task
            _tasks.add(task);
            await _taskBox?.put(task.id, task);
          }
          updated = true;
        }
      }

      if (updated) {
        // Remove duplicates based on ID
        final unique = {for (var t in _tasks) t.id: t};
        _tasks = unique.values.toList();

        notifyListeners();
      }
    });
  }

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

      // Upsert into map to prevent duplicates
      final Map<String, TaskModel> merged = {for (var t in _tasks) t.id: t};
      for (var t in remoteTasks) merged[t.id] = t;

      _tasks = merged.values.toList()
        ..sort((a, b) {
          final aTime = a.lastUpdated ?? DateTime.fromMillisecondsSinceEpoch(0);
          final bTime = b.lastUpdated ?? DateTime.fromMillisecondsSinceEpoch(0);
          return bTime.compareTo(aTime);
        });

      // Save merged tasks locally
      for (var t in _tasks) {
        await _taskBox?.put(t.id, t);
      }

      notifyListeners();
      debugPrint('✅ Remote tasks merged: ${remoteTasks.length}');
    } catch (e) {
      debugPrint('⚠️ Firestore fetch failed: $e');
    }
  }

  Future<void> addTask(TaskModel task) async {
    final newTask = task.copyWith(
      id: task.id.isNotEmpty ? task.id : const Uuid().v4(),
      lastUpdated: DateTime.now(),
    );

    // Remove duplicate if exists
    _tasks.removeWhere((t) => t.id == newTask.id);
    _tasks.add(newTask);

    await _taskRepo.saveTask(newTask);
    await _taskBox?.put(newTask.id, newTask);

    notifyListeners();

    if (!kIsWeb) await scheduleTaskAlarm(newTask);

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

    if (!kIsWeb) {
      await cancelTaskAlarm(oldTask);
      if (mergedTask.alarm != null) await scheduleTaskAlarm(mergedTask);
    }

    if (await NetworkHelper.isOnline()) {
      try {
        await _firestore
            .collection('users')
            .doc(mergedTask.parentId)
            .collection('children')
            .doc(mergedTask.childId)
            .collection('tasks')
            .doc(mergedTask.id)
            .set(mergedTask.toMap(), SetOptions(merge: true));
      } catch (e) {
        debugPrint('⚠️ Firestore updateTask failed: $e');
      }
    }

    debugPrint(
      '📝 Task updated: ${mergedTask.name}, Alarm: ${mergedTask.alarm}',
    );
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

    if (task != null && !kIsWeb) await cancelTaskAlarm(task);

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

  // ---------------- MARK DONE ----------------
  Future<void> markTaskAsDone(String taskId, String childId) async {
    final index = _tasks.indexWhere((t) => t.id == taskId);
    if (index == -1) return;

    final task = _tasks[index];
    if (task.isDone) return; // Already done

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    // Calculate new streak
    final lastDone = task.lastCompletedDate != null
        ? DateTime(
            task.lastCompletedDate!.year,
            task.lastCompletedDate!.month,
            task.lastCompletedDate!.day,
          )
        : null;

    int newActiveStreak = 1;
    if (lastDone != null) {
      if (lastDone.add(const Duration(days: 1)).isAtSameMomentAs(today)) {
        newActiveStreak = task.activeStreak + 1;
      } else if (lastDone.isAtSameMomentAs(today)) {
        newActiveStreak = task.activeStreak;
      }
    }

    final updatedTask = task.copyWith(
      isDone: true,
      doneAt: now,
      lastCompletedDate: today,
      activeStreak: newActiveStreak,
      longestStreak: max(newActiveStreak, task.longestStreak),
      totalDaysCompleted: task.totalDaysCompleted + 1,
      lastUpdated: now,
    );

    // 1️⃣ Update local memory
    _tasks[index] = updatedTask;
    notifyListeners();

    // 2️⃣ Update Hive and local repo
    await _taskBox?.put(updatedTask.id, updatedTask);
    await _taskRepo.saveTaskLocal(updatedTask);

    // 3️⃣ Update Firestore
    try {
      await _firestore
          .collection('users')
          .doc(task.parentId)
          .collection('children')
          .doc(childId)
          .collection('tasks')
          .doc(task.id)
          .set(updatedTask.toMap(), SetOptions(merge: true));

      debugPrint('✅ Task marked done in Firestore: ${task.name}');
    } catch (e) {
      debugPrint('⚠️ Failed to update Firestore: $e');
    }

    // 4️⃣ Cancel alarm if exists
    if (!kIsWeb && task.alarm != null) {
      await cancelTaskAlarm(task);
    }

    // 5️⃣ Update streak repository
    await _streakRepo.updateStreak(childId, task.parentId, task.id);

    // 6️⃣ Notify parent
    try {
      final childSnapshot = await _firestore
          .collection('users')
          .doc(task.parentId)
          .collection('children')
          .doc(childId)
          .get();

      final childName = childSnapshot.data()?['name'] ?? 'Your child';

      await notifyParentCompletion(
        parentId: task.parentId,
        childName: childName,
        itemName: task.name,
        type: 'task_completed',
      );
    } catch (e) {
      debugPrint('⚠️ Failed to send notification to parent: $e');
    }
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

    if (scheduledDate.isBefore(now))
      scheduledDate = scheduledDate.add(const Duration(days: 1));

    await NotificationService().scheduleDailyNotification(
      id: alarmId,
      title: '🧩 Task Reminder!',
      body: task.name,
      hour: task.alarm!.hour,
      minute: task.alarm!.minute,
      payload: task.id,
    );

    debugPrint(
      '✅ Alarm scheduled for "${task.name}" at ${scheduledDate.hour}:${scheduledDate.minute}',
    );

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
          data: {
            'type': 'task_alarm',
            'taskId': task.id,
            'taskName': task.name,
          },
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
        await _taskRepo.saveTask(updated);

        final idx = _tasks.indexWhere((t) => t.id == task.id);
        if (idx != -1) _tasks[idx] = updated;
        if (await NetworkHelper.isOnline()) {
          try {
            await _firestore
                .collection('users')
                .doc(task.parentId)
                .collection('children')
                .doc(task.childId)
                .collection('tasks')
                .doc(task.id)
                .set(updated.toMap(), SetOptions(merge: true));
          } catch (e) {
            debugPrint('⚠️ Firestore resetDailyTasks failed: $e');
          }
        }
      }
    }

    await pushPendingChanges();
    _lastResetDate = todayDateOnly;
    await _settingsBox?.put('lastResetDate', _lastResetDate!);
    notifyListeners();
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

  bool _isSameTask(TaskModel a, TaskModel b) {
    return a.id == b.id &&
        a.lastUpdated == b.lastUpdated &&
        a.isDone == b.isDone &&
        a.verified == b.verified;
  }

  @override
  void dispose() {
    stopDailyResetScheduler();
    _firestoreSubscription?.cancel();
    super.dispose();
  }

  Future<void> autoResetIfNeeded() async {
    final today = DateTime.now();
    final todayDateOnly = DateTime(today.year, today.month, today.day);

    if (_lastResetDate == null || _lastResetDate!.isBefore(todayDateOnly)) {
      await resetDailyTasks();
    }
  }

  Future<void> notifyParentCompletion({
    required String parentId,
    required String childName,
    required String itemName,
    required String type,
  }) async {
    try {
      final parentSnapshot = await _firestore
          .collection('users')
          .doc(parentId)
          .get();
      final parentToken = parentSnapshot.data()?['fcmToken'];
      if (parentToken != null) {
        await FCMService.sendNotification(
          title: type == 'task_completed'
              ? '🎉 Task Completed'
              : '🧠 CBT Completed',
          body: '$childName finished $itemName!',
          token: parentToken,
          data: {'type': type, 'childName': childName, 'itemName': itemName},
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

          if (now.difference(alarmTime).inSeconds.abs() <= 5) {
            debugPrint(
              '🔔 [WEB SIM] Alarm triggered for "${task.name}" at ${now.hour}:${now.minute}:${now.second}',
            );
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
