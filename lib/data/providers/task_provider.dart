// ignore_for_file: unnecessary_null_comparison

import 'dart:async';
import 'package:brightbuds_new/aquarium/manager/achievement_manager.dart';
import 'package:brightbuds_new/aquarium/manager/unlockManager.dart';
import 'package:brightbuds_new/aquarium/notifiers/achievement_notifier.dart';
import 'package:brightbuds_new/aquarium/progression/level_calculator.dart';
import 'package:brightbuds_new/data/models/child_model.dart';
import 'package:brightbuds_new/notifications/fcm_service.dart';
import 'package:brightbuds_new/notifications/notification_service.dart';
import 'package:brightbuds_new/ui/pages/parent_view/parentHome_page.dart';
import 'package:brightbuds_new/utils/network_helper.dart';
import 'package:brightbuds_new/utils/xp_calculator.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart'
    show ScaffoldMessenger, Text, BuildContext, SnackBar, TimeOfDay;
import 'package:timezone/timezone.dart' as tz;
import 'package:uuid/uuid.dart';
import 'package:hive/hive.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/task_model.dart';
import '../repositories/task_repository.dart';
import '../repositories/user_repository.dart';
import '../repositories/streak_repository.dart';
import '../services/sync_service.dart';

enum _PendingActionType { balance }

class _PendingAction {
  final _PendingActionType type;
  final String?
  taskId; // optional: used if the action relates to a specific task

  _PendingAction(this.type, this.taskId);
}

class TaskProvider extends ChangeNotifier {
  final TaskRepository _taskRepo = TaskRepository();
  final UserRepository _userRepo = UserRepository();
  final StreakRepository _streakRepo = StreakRepository();
  final UnlockManager unlockManager;
  late final SyncService _syncService;
  late Box<ChildUser> _childBox;
  Function(int newXP)? onXPChanged;
    TaskProvider(this.unlockManager,) {
      _syncService = SyncService(_userRepo, _taskRepo, _streakRepo);
    }

  late ChildUser currentChild;

  final List<_PendingAction> _pendingActions = [];
  List<TaskModel> _tasks = [];
  List<TaskModel> get tasks => _tasks;
  set tasks(List<TaskModel> newTasks) {
    _tasks = newTasks;
    notifyListeners();
  }

  TaskModel? getTaskById(String id) {
    try {
      return _tasks.firstWhere((t) => t.id == id);
    } catch (_) {
      return null;
    }
  }

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  Timer? _midnightTimer;
  Box<TaskModel>? _taskBox;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _taskSubscription;
  double _timeOfDayToDouble(TimeOfDay t) => t.hour + (t.minute / 60.0);

  final Map<String, TimeOfDay> routineEndTimes = {
    'morning': const TimeOfDay(hour: 11, minute: 59),
    'afternoon': const TimeOfDay(hour: 17, minute: 59),
    'evening': const TimeOfDay(hour: 21, minute: 59),
    'anytime': const TimeOfDay(hour: 23, minute: 59), // never considered missed
  };

  Map<String, int> countTaskStatuses(List<TaskModel> tasks) {
    int done = 0;
    int notDone = 0;
    int missed = 0;

    final nowTod = TimeOfDay.fromDateTime(DateTime.now());

    for (final task in tasks) {
      // If task is marked done (today), count as done.
      // NOTE: You may further check lastCompletedDate to ensure "done today" if desired.
      if (task.isDone) {
        done++;
        continue;
      }

      // Not done
      notDone++;

      // Determine if it should be considered missed based on its routine window
      try {
        final routineKey = (task.routine ?? 'anytime').toLowerCase().trim();
        final end = routineEndTimes[routineKey];

        // If a known end time exists and it's not 'anytime', compare.
        if (end != null && routineKey != 'anytime') {
          if (_timeOfDayToDouble(nowTod) > _timeOfDayToDouble(end)) {
            // Current time is past the routine's end time => consider missed.
            missed++;
          }
        }
      } catch (e) {
        // Fail-safe: don't treat unknown routine as missed
        // optionally log debug here
      }
    }

    return {'done': done, 'notDone': notDone, 'missed': missed};
  }

  void Function(int newLevel)? onLevelUp;

  void _checkAchievements(ChildUser child) {
    final achievementManager = AchievementManager(
      achievementNotifier: AchievementNotifier(),
      currentChild: child,
    );
    achievementManager.checkAchievements();
  }

  // ---------------- FIRESTORE ----------------
  void startFirestoreSubscription({
    required String parentId,
    required String childId,
    bool isParentView = false,
  }) {
    // Cancel previous subscription if exists
    _taskSubscription?.cancel();

    final query = _firestore
        .collection('users')
        .doc(parentId)
        .collection('children')
        .doc(childId)
        .collection('tasks');

    _taskSubscription = query.snapshots().listen(
      (snapshot) async {
        bool updated = false;

        for (var change in snapshot.docChanges) {
          final data = change.doc.data();
          if (data == null) continue;

          final task = TaskModel.fromMap(data).copyWith(id: change.doc.id);
          final index = _tasks.indexWhere((t) => t.id == task.id);

          switch (change.type) {
            case DocumentChangeType.added:
              if (index == -1) {
                _tasks.add(task);
                await _taskBox?.put(task.id, task);
                updated = true;
              } else {
                // Update in-memory task instead of adding duplicate
                _tasks[index] = task;
                await _taskBox?.put(task.id, task);
                updated = true;
              }
              break;

            case DocumentChangeType.modified:
              if (index != -1) {
                // Only update if the incoming task is newer
                final localTask = _tasks[index];
                if (task.lastUpdated != null &&
                    (localTask.lastUpdated == null ||
                        task.lastUpdated!.isAfter(localTask.lastUpdated!))) {
                  _tasks[index] = task;
                  await _taskBox?.put(task.id, task);
                  updated = true;
                }
              } else {
                // New task from Firestore
                _tasks.add(task);
                await _taskBox?.put(task.id, task);
                updated = true;
              }
              break;

            case DocumentChangeType.removed:
              if (index != -1) {
                _tasks.removeAt(index);
                await _taskBox?.delete(task.id);
                updated = true;
              }
              break;
          }
        }

        if (updated) {
          _tasks.sort(
            (a, b) => (b.lastUpdated ?? DateTime(0)).compareTo(
              a.lastUpdated ?? DateTime(0),
            ),
          );
          notifyListeners();
          debugPrint(
            '🔄 Tasks updated from Firestore. Count: ${_tasks.length}',
          );
        }
      },
      onError: (e) {
        debugPrint('⚠️ Firestore subscription error: $e');
      },
    );
  }

  // ---------------- HIVE ----------------
  Future<void> initHive() async {
    _taskBox = Hive.isBoxOpen('tasksBox')
        ? Hive.box<TaskModel>('tasksBox')
        : await Hive.openBox<TaskModel>('tasksBox');
  }

  Future<void> loadTasks({
    required String parentId,
    String? childId,
    bool isParent = false,
  }) async {
    _setLoading(true);

    try {
      // 1️⃣ Open Hive first
      await initHive();

      // 2️⃣ Load tasks from local Hive
      _tasks = _taskBox?.values.toList() ?? [];
      notifyListeners();

      // 3️⃣ Start Firestore subscription early for real-time updates
      if (childId != null && childId.isNotEmpty) {
        startFirestoreSubscription(parentId: parentId, childId: childId);
      }

      // 5️⃣ Merge remote tasks if online
      if (await NetworkHelper.isOnline()) {
        await mergeRemoteTasks(
          parentId: parentId,
          childId: childId,
          isParent: isParent,
        );
      }
// 4️⃣ Save current task progress dynamically
{
  final Map<String, List<TaskModel>> childTasks = {};
  for (final task in _tasks) {
    if (!childTasks.containsKey(task.childId)) {
      childTasks[task.childId] = [];
    }
    childTasks[task.childId]!.add(task);
  }

  for (final entry in childTasks.entries) {
    final tasks = entry.value;
    final statusCounts = countTaskStatuses(tasks);

    final done = statusCounts['done'] ?? 0;
    final notDone = statusCounts['notDone'] ?? 0;
    final missed = statusCounts['missed'] ?? 0;

    try {
      final historyService = TaskHistoryService();
      await historyService.saveDailyTaskProgress(
        parentId: tasks.first.parentId,
        childId: entry.key,
        done: done,
        notDone: notDone,
        missed: missed,
      );
      debugPrint('📘 Saved daily progress for child ${entry.key}');
    } catch (e) {
      debugPrint('⚠️ Failed to save daily progress for ${entry.key}: $e');
    }
  }
}

// 5️⃣ Auto-reset if needed (old resetDailyTasks logic)
await autoResetIfNeeded();

      // 6️⃣ Reload tasks from local Hive after merge/reset
      _tasks = _taskBox?.values.toList() ?? [];
      notifyListeners();

      // 7️⃣ Schedule alarms for tasks (skip web)
      if (!kIsWeb) await _scheduleAllAlarms(_tasks);
    } finally {
      _setLoading(false);
    }
  }

  void _setLoading(bool value) {
    _isLoading = value;
    notifyListeners();
  }

  Future<void> _scheduleAllAlarms(List<TaskModel> tasks) async {
    for (var task in tasks) {
      if (task.alarm != null && !kIsWeb) {
        await scheduleTaskAlarm(task);
      }
    }
  }

  // ---------------- MERGE REMOTE ----------------
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

      bool updated = false;
      final Map<String, TaskModel> merged = {for (var t in _tasks) t.id: t};

      for (var t in remoteTasks) {
        final existing = merged[t.id];
        if (existing == null ||
            (t.lastUpdated != null &&
                (existing.lastUpdated == null ||
                    t.lastUpdated!.isAfter(existing.lastUpdated!)))) {
          merged[t.id] = t;
          updated = true;
          await _taskBox?.put(t.id, t);
        }
      }

      _tasks = merged.values.toList();
      if (updated) notifyListeners();

      debugPrint('✅ Remote tasks merged: ${remoteTasks.length}');
    } catch (e) {
      debugPrint('⚠️ Firestore fetch failed: $e');
    }
  }

  Future<void> _syncToFirestore(TaskModel task) async {
    try {
      if (await NetworkHelper.isOnline()) {
        final docRef = _firestore
            .collection('users')
            .doc(task.parentId)
            .collection('children')
            .doc(task.childId)
            .collection('tasks')
            .doc(task.id);

        // Merge ensures partial updates are handled without duplicating
        await docRef.set(task.toMap(), SetOptions(merge: true));

        debugPrint('✅ Task synced to Firestore (merge only): ${task.name}');
      }
    } catch (e) {
      debugPrint('⚠️ Failed to sync task to Firestore: $e');
    }
  }

  // ---------------- CRUD ----------------
  Future<void> addTask(TaskModel task, BuildContext context) async {
    try {
      // Validate numeric field: reward
      final reward = task.reward;
      if (reward == null || reward.toString().isEmpty) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text("Reward cannot be empty")));
        return;
      }

      // Only allow positive integers
      final rewardInt = int.tryParse(reward.toString());
      if (rewardInt == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Reward must be a number")),
        );
        return;
      }

      if (rewardInt < 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Reward must be a positive number")),
        );
        return;
      }

      // Create a new task with ID and timestamp
      final newTask = task.copyWith(
        reward: rewardInt,
        id: task.id.isNotEmpty ? task.id : const Uuid().v4(),
        lastUpdated: DateTime.now(),
      );

      // Save locally
      _tasks.add(newTask);
      await _taskBox?.put(newTask.id, newTask);

      notifyListeners();

      // Save to repository
      await _taskRepo.saveTask(newTask);

      // Sync to Firestore
      await _syncToFirestore(newTask);

      // Schedule alarm (if applicable)
      if (!kIsWeb) scheduleTaskAlarm(newTask);

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Task added successfully!")));
    } catch (e) {
      debugPrint("Error adding task: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Failed to add task: ${e.toString()}")),
      );
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
    await _taskBox?.put(mergedTask.id, mergedTask);

    await _taskRepo.updateTask(mergedTask);
    await _syncToFirestore(mergedTask);

    notifyListeners();

    if (!kIsWeb) {
      await cancelTaskAlarm(oldTask);
      if (mergedTask.alarm != null) await scheduleTaskAlarm(mergedTask);
    }

    debugPrint('📝 Task updated: ${mergedTask.name}');
  }

  Future<void> deleteTask(
    String taskId,
    String parentId,
    String childId,
  ) async {
    final index = _tasks.indexWhere((t) => t.id == taskId);
    if (index == -1) return;

    final task = _tasks[index];

    // Remove locally (Hive + Repo)
    await _taskRepo.deleteTask(taskId, parentId, childId);
    await _taskBox?.delete(taskId);

    // Cancel alarm if exists
    if (!kIsWeb && task.alarm != null) {
      await cancelTaskAlarm(task);
    }

    // Remove from in-memory list and notify
    _tasks.removeAt(index);
    notifyListeners();

    // Firestore delete for real-time
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

  void loadCachedTasks(List<TaskModel> cachedTasks) {
    _tasks = cachedTasks;
    notifyListeners();
  }

  /// ---------------- TASK COMPLETION (XP LOGIC) ----------------
  Future<void> markTaskAsDone(String taskId, String childId) async {
    final index = _tasks.indexWhere((t) => t.id == taskId);
    if (index == -1) return;

    final task = _tasks[index];
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    // ✅ Handle streak
    final bool isYesterday =
        task.lastCompletedDate != null &&
        task.lastCompletedDate!.difference(today).inDays == -1;
    final newActiveStreak = isYesterday ? task.activeStreak + 1 : 1;

    final updatedTask = task.copyWith(
      isDone: true,
      doneAt: now,
      lastCompletedDate: today,
      activeStreak: newActiveStreak,
      longestStreak:
          newActiveStreak > (task.longestStreak) ? newActiveStreak : task.longestStreak,
      totalDaysCompleted: task.totalDaysCompleted + 1,
      lastUpdated: now,
    );

    _tasks[index] = updatedTask;
    await _taskBox?.put(updatedTask.id, updatedTask);
    await _taskRepo.saveTask(updatedTask);
    notifyListeners();

    // ✅ Cancel alarm if exists
    if (!kIsWeb && updatedTask.alarm != null) {
      await cancelTaskAlarm(updatedTask);
    }

    // ✅ Sync Firestore
    if (await NetworkHelper.isOnline()) {
      await _syncToFirestore(updatedTask);
      await _syncService.syncAllPendingChanges(
        parentId: updatedTask.parentId,
        childId: updatedTask.childId,
      );
    }

    // ✅ Update streak
    await _streakRepo.updateStreak(
      updatedTask.childId,
      updatedTask.parentId,
      updatedTask.id,
    );

    // ✅ Notify parent
    await _notifyParentCompletion(updatedTask, childId);
  }

  Future<void> markTaskAsUndone(String taskId, String childId) async {
    final index = _tasks.indexWhere((t) => t.id == taskId);
    if (index == -1) return;

    final task = _tasks[index];
    if (!task.isDone) return; // Already undone — nothing to do

    final now = DateTime.now();

    // ✅ Decrease totalDaysCompleted but don’t go below 0
    final newTotalDays = (task.totalDaysCompleted > 0)
        ? task.totalDaysCompleted - 1
        : 0;

    // ✅ Update local task
    final updatedTask = task.copyWith(
      isDone: false,
      doneAt: null,
      verified: false,
      lastUpdated: now,
      totalDaysCompleted: newTotalDays,
    );

    // ✅ Update local cache and in-memory
    _tasks[index] = updatedTask;
    await _taskBox?.put(updatedTask.id, updatedTask);

    // Persist via repository so repo/pending logic knows about change
    try {
      await _taskRepo.saveTask(updatedTask);
    } catch (e) {
      debugPrint('⚠️ _taskRepo.saveTask failed (mark undone): $e');
    }

    notifyListeners();

    // ✅ Try to sync immediately if online
    if (await NetworkHelper.isOnline()) {
      try {
        await _syncToFirestore(updatedTask);
        try {
          await _syncService.syncAllPendingChanges(
            parentId: updatedTask.parentId,
            childId: updatedTask.childId,
          );
        } catch (e) {
          debugPrint('⚠️ syncAllPendingChanges failed (after mark undone): $e');
        }
        debugPrint('↩️ Task marked as undone and synced: ${updatedTask.name}');
      } catch (e) {
        debugPrint('⚠️ Failed to sync undone task: $e');
      }
    } else {
      debugPrint('⚠️ Offline: will sync undone task later.');
    }

    // ✅ Clean duplicates and re-sort by lastUpdated
    final uniqueTasks = <String, TaskModel>{for (var t in _tasks) t.id: t};
    _tasks = uniqueTasks.values.toList()
      ..sort(
        (a, b) => (b.lastUpdated ?? DateTime(0)).compareTo(
          a.lastUpdated ?? DateTime(0),
        ),
      );

    notifyListeners();
  }

  Future<void> _notifyParentCompletion(TaskModel task, String childId) async {
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
      debugPrint('⚠️ Failed to notify parent: $e');
    }
  }

  Future<void> verifyTask(String taskId, String childId) async {
  final index = _tasks.indexWhere((t) => t.id == taskId);
  if (index == -1) return;

  final task = _tasks[index];

  // 🔒 Guard 1: Already verified → do nothing
  if (task.verified) {
    debugPrint('⚠️ Task already verified, skipping XP grant');
    return;
  }

  // 🔒 Guard 2: Task must be done first
  if (!task.isDone) {
    debugPrint('⚠️ Cannot verify task that is not done');
    return;
  }

  final now = DateTime.now();

  // 🧮 Calculate XP BASED ON DIFFICULTY (single source of truth)
  final levelCalculator = LevelCalculator();
  final earnedXP = levelCalculator.xpFromTask(task.difficulty ?? 'easy');

  // ✅ Update task: verified = true
  final verifiedTask = task.copyWith(
    verified: true,
    lastUpdated: now,
  );

  // --- LOCAL STATE ---
  _tasks[index] = verifiedTask;
  await _taskBox?.put(verifiedTask.id, verifiedTask);
  notifyListeners();

  // --- REPO ---
  await _taskRepo.verifyTask(taskId, childId);

  // --- XP GRANT (ONLY HERE) ---
  await _userRepo.updateChildXP(
  task.parentId,
  childId,
  earnedXP,
);

// 🔹 Update currentChild after fetchChildAndCache
currentChild = (await _userRepo.fetchChildAndCache(task.parentId, childId))!;

// 🔹 Trigger achievement check
unlockManager.checkAchievementUnlocks(tasks, currentChild);

// 🔹 Optional: notify UI about XP change
onXPChanged?.call(currentChild.xp);

  // --- FIRESTORE SYNC ---
  if (await NetworkHelper.isOnline()) {
    try {
      await _syncToFirestore(verifiedTask);
      await _syncService.syncAllPendingChanges(
        parentId: verifiedTask.parentId,
        childId: verifiedTask.childId,
      );
    } catch (e) {
      debugPrint('⚠️ Firestore sync failed after verification: $e');
    }
  }
  _checkAchievements(currentChild);

  debugPrint(
    '✅ Task verified: ${verifiedTask.name}, XP granted: $earnedXP',
  );
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

    if (scheduledDate.isBefore(now)) {
      scheduledDate = scheduledDate.add(const Duration(days: 1));
    }

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

    await _sendFcmAlarm(task);
  }

  Future<void> _sendFcmAlarm(TaskModel task) async {
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
    await NotificationService().cancelNotification(task.id.hashCode);
  }

  // ---------------- REAL-TIME SAFE DAILY RESET ----------------
  Future<void> resetDailyTasks() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    bool updated = false;

    debugPrint(
      '🕛 Starting daily task reset check for ${_tasks.length} tasks...',
    );

    // --- 🧩 Group tasks by childId ---
  final Map<String, List<TaskModel>> childTasks = {};
    for (final task in _tasks) {
      if (!childTasks.containsKey(task.childId)) {
        childTasks[task.childId] = [];
      }
      childTasks[task.childId]!.add(task);
    }

    for (final entry in childTasks.entries) {
    final tasks = entry.value;

    // Use provider's method (same logic as the chart)
    final statusCounts = countTaskStatuses(tasks);

    final done = statusCounts['done'] ?? 0;
    final notDone = statusCounts['notDone'] ?? 0;
    final missed = statusCounts['missed'] ?? 0;

    try {
      final historyService = TaskHistoryService();
      await historyService.saveDailyTaskProgress(
        parentId: tasks.first.parentId,
        childId: entry.key,
        done: done,
        notDone: notDone,
        missed: missed,
      );
      debugPrint('📘 Saved daily progress for child ${entry.key}');
    } catch (e) {
      debugPrint('⚠️ Failed to save daily progress for ${entry.key}: $e');
    }
  }

    for (var i = 0; i < _tasks.length; i++) {
      final task = _tasks[i];
      final lastDone = task.lastCompletedDate != null
          ? DateTime(
              task.lastCompletedDate!.year,
              task.lastCompletedDate!.month,
              task.lastCompletedDate!.day,
            )
          : null;

      // ✅ Reset if the task was done before today
      final shouldReset =
          task.isDone && (lastDone == null || lastDone.isBefore(today));

      if (shouldReset) {
        // ✅ Keep streak if task was done yesterday, else reset streak
        int updatedActiveStreak = 0;
        if (lastDone != null &&
            lastDone.isAfter(today.subtract(const Duration(days: 2)))) {
          updatedActiveStreak = task.activeStreak;
        }

        final updatedTask = task.copyWith(
          isDone: false,
          verified: false,
          activeStreak: updatedActiveStreak,
          lastUpdated: now,
        );

        debugPrint(
          '🔄 Resetting task "${updatedTask.name}" (was done on $lastDone)',
        );

        // --- LOCAL SAVE ---
        await _taskBox?.put(updatedTask.id, updatedTask);
        await _taskRepo.saveTask(updatedTask);
        _tasks[i] = updatedTask;
        updated = true;

        // --- FIRESTORE SYNC ---
        try {
          await _firestore
              .collection('users')
              .doc(updatedTask.parentId)
              .collection('children')
              .doc(updatedTask.childId)
              .collection('tasks')
              .doc(updatedTask.id)
              .set(updatedTask.toMap(), SetOptions(merge: true));

          debugPrint('✅ Firestore updated for ${updatedTask.name}');
        } catch (e) {
          debugPrint('⚠️ Firestore sync failed for ${updatedTask.name}: $e');
        }
      }
    }

    if (updated) {
      notifyListeners();
      debugPrint('✅ Daily tasks reset and synced successfully at $now');
    } else {
      debugPrint('⏳ No tasks needed resetting today.');
    }
  }

  // ---------------- AUTO RESET CHECK ----------------
  Future<void> autoResetIfNeeded() async {
    try {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final lastReset = await getLastResetDate();

      if (lastReset == null) {
        debugPrint('🆕 No last reset found — performing first daily reset...');
        await resetDailyTasks();
        await setLastResetDate(today);
        return;
      }

      final lastResetDay = DateTime(
        lastReset.year,
        lastReset.month,
        lastReset.day,
      );

      if (lastResetDay.isBefore(today)) {
        debugPrint(
          '🔄 Auto-reset triggered — last reset was $lastResetDay, today is $today.',
        );
        await resetDailyTasks();
        await setLastResetDate(today);
      } else {
        debugPrint(
          '✅ Daily tasks already reset today (${lastResetDay.toLocal()}).',
        );
      }
    } catch (e, stack) {
      debugPrint('❌ autoResetIfNeeded() failed: $e');
      debugPrint(stack.toString());
    }
  }

  // ---------------- DAILY RESET SCHEDULER ----------------
  void startDailyResetScheduler() {
    _midnightTimer?.cancel();

    final now = DateTime.now();
    final nextMidnight = DateTime(now.year, now.month, now.day + 1);

    final durationUntilMidnight = nextMidnight.difference(now);

    _midnightTimer = Timer(durationUntilMidnight, () async {
      await resetDailyTasks();
      await setLastResetDate(DateTime.now());

      // Schedule again for the next day
      startDailyResetScheduler();
    });

    debugPrint('⏰ Daily reset scheduled for ${nextMidnight.toLocal()}');
  }

  void stopDailyResetScheduler() {
    _midnightTimer?.cancel();
    _midnightTimer = null;
    debugPrint('⏹ Daily reset scheduler stopped');
  }

  // ---------------- SYNC ----------------
  Future<void> pushPendingChanges() async {
    await _syncService.syncAllPendingChanges();
    notifyListeners();
  }

  Future<DateTime?> getLastResetDate() async {
    final box = await Hive.openBox('appSettings');
    final millis = box.get('lastResetDate') as int?;
    return millis != null ? DateTime.fromMillisecondsSinceEpoch(millis) : null;
  }

  Future<void> setLastResetDate(DateTime date) async {
    final box = await Hive.openBox('appSettings');
    await box.put('lastResetDate', date.millisecondsSinceEpoch);
  }

  // ---------------- FCM PARENT ----------------
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
}

// ---------------- EXTENSIONS ----------------
extension TaskStats on TaskProvider {
  int get doneCount => _tasks.where((t) => t.isDone).length;
  int get notDoneCount => _tasks.where((t) => !t.isDone).length;
}

// ---------------- HELPERS ----------------
extension IterableHelper<E> on Iterable<E> {
  E? firstWhereOrNull(bool Function(E element) test) {
    for (var e in this) {
      if (test(e)) return e;
    }
    return null;
  }
}
