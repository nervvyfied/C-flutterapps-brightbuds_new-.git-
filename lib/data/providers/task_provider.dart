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
import 'package:flutter/widgets.dart';
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

enum UserType { parent, therapist }

class CurrentUser {
  final String uid; // Firestore UID
  final UserType type;

  CurrentUser({required this.uid, required this.type});
}

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
  final AchievementNotifier achievementNotifier;
  late final SyncService _syncService;

  late Box<ChildUser> _childBox;
  Function(int newXP)? onXPChanged;
  TaskProvider(this.unlockManager, this.achievementNotifier) {
    _syncService = SyncService(_userRepo, _taskRepo, _streakRepo);
  }

  final List<_PendingAction> _pendingActions = [];
  List<TaskModel> _tasks = [];
  List<TaskModel> get tasks => _tasks;
  set tasks(List<TaskModel> newTasks) {
    _tasks = newTasks;
    notifyListeners();
    // Initialize child box
    _initChildBox();
  }

  Future<void> _initChildBox() async {
    _childBox = Hive.isBoxOpen('childrenBox')
        ? Hive.box<ChildUser>('childrenBox')
        : await Hive.openBox<ChildUser>('childrenBox');
  }

  CurrentUser? currentUser; // ✅ Who is using this provider
  String? _currentUserId;
  UserType? _currentUserType;

  void setCurrentUser(String uid, UserType type) {
    currentUser = CurrentUser(uid: uid, type: type);
    debugPrint('👤 Current user set: $uid (${type.name})');
  }

  void clearCurrentUser() {
    currentUser = null;
    notifyListeners();
  }

  String? get currentUserId => currentUser?.uid;
  UserType? get currentUserType => currentUser?.type;

  ChildUser? currentChild;
  bool canManageTask(TaskModel task) {
    if (currentUser == null) return false;

    if (currentUser!.type == UserType.therapist) {
      return true; // Therapist can manage anything
    } else if (currentUser!.type == UserType.parent) {
      return true; // Parent only their own tasks
    }

    return false;
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
      if (task.isDone) {
        done++;
        continue;
      }

      notDone++;

      try {
        final routineKey = (task.routine ?? 'anytime').toLowerCase().trim();
        final end = routineEndTimes[routineKey];

        if (end != null && routineKey != 'anytime') {
          if (_timeOfDayToDouble(nowTod) > _timeOfDayToDouble(end)) {
            missed++;
          }
        }
      } catch (e) {
        // Fail-safe
      }
    }

    return {'done': done, 'notDone': notDone, 'missed': missed};
  }

  void Function(int newLevel)? onLevelUp;

  void _checkAchievements(ChildUser child) {
    final achievementManager = AchievementManager(
      achievementNotifier: achievementNotifier, // ✅ shared instance
      child: child,
    );

    achievementManager.checkAchievements();
  }

  // ---------------- FIRESTORE ----------------
  void startFirestoreSubscription({
    required String parentId,
    required String childId,
    bool isParentView = false,
  }) async {
    // Cancel previous subscription if exists
    _taskSubscription?.cancel();

    // ✅ Get actual parent ID for subscription
    String actualParentId = parentId;
    if (currentUser?.type == UserType.therapist) {
      final fetchedParentId = await _getParentIdForChild(childId);
      if (fetchedParentId != null) {
        actualParentId = fetchedParentId;
      } else {
        debugPrint(
          '⚠️ Cannot subscribe: parentId not found for child $childId',
        );
        return;
      }
    }

    final query = _firestore
        .collection('users')
        .doc(actualParentId)
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
                _tasks[index] = task;
                await _taskBox?.put(task.id, task);
                updated = true;
              }
              break;

            case DocumentChangeType.modified:
              if (index != -1) {
                final localTask = _tasks[index];
                if (task.lastUpdated != null &&
                    (localTask.lastUpdated == null ||
                        task.lastUpdated!.isAfter(localTask.lastUpdated!))) {
                  _tasks[index] = task;
                  await _taskBox?.put(task.id, task);
                  updated = true;
                }
              } else {
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

  // Add this flag to prevent multiple resets
  bool _hasCheckedDailyReset = false;

  // Add this method to check and perform daily reset on app launch
  Future<void> checkAndPerformDailyResetOnLaunch() async {
    // Prevent checking multiple times
    if (_hasCheckedDailyReset) return;

    try {
      debugPrint('🚀 Checking for daily reset on app launch...');

      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final lastReset = await getLastResetDate();

      debugPrint('📅 Last reset date: $lastReset');
      debugPrint('📅 Today: $today');

      // Case 1: First time ever running the app
      if (lastReset == null) {
        debugPrint('🆕 First app launch - performing initial reset');
        await resetDailyTasks();
        await setLastResetDate(today);
        _hasCheckedDailyReset = true;
        return;
      }

      // Case 2: Normal case - check if we need to reset
      final lastResetDay = DateTime(
        lastReset.year,
        lastReset.month,
        lastReset.day,
      );

      if (lastResetDay.isBefore(today)) {
        debugPrint(
          '🔄 New day detected! Last reset: $lastResetDay, Today: $today',
        );
        debugPrint('🔄 Performing daily reset on app launch...');

        await resetDailyTasks();
        await setLastResetDate(today);

        debugPrint('✅ Daily reset completed on app launch');
      } else {
        debugPrint('✅ Already reset today, no action needed');
      }

      _hasCheckedDailyReset = true;
    } catch (e, stack) {
      debugPrint('⚠️ Error in checkAndPerformDailyResetOnLaunch: $e');
      debugPrint(stack.toString());
    }
  }

  // Modify initHive to check on app launch
  Future<void> initHive() async {
    _taskBox = Hive.isBoxOpen('tasksBox')
        ? Hive.box<TaskModel>('tasksBox')
        : await Hive.openBox<TaskModel>('tasksBox');

    // Check for daily reset immediately when Hive is initialized
    await checkAndPerformDailyResetOnLaunch();

    debugPrint('📦 Hive initialized and daily reset checked');
  }

  // Also check when loading tasks (backup check)
  Future<void> loadTasks({
    required String parentId,
    String? childId,
    bool isParent = false,
  }) async {
    // Check daily reset again when loading tasks (just in case)
    await checkAndPerformDailyResetOnLaunch();

    _setLoading(true);

    try {
      await initHive();
      _tasks = _taskBox?.values.toList() ?? [];
      notifyListeners();

      // ✅ Ensure current child is set
      if (childId != null && currentChild == null) {
        await _loadCurrentChild(childId);
      }

      // ✅ Get actual parent ID for loading
      String actualParentId = parentId;
      if (currentUser?.type == UserType.therapist && childId != null) {
        final fetchedParentId = await _getParentIdForChild(childId);
        if (fetchedParentId != null) {
          actualParentId = fetchedParentId;
        } else {
          debugPrint(
            '⚠️ Cannot load tasks: parentId not found for child $childId',
          );
          return;
        }
      }

      if (childId != null && childId.isNotEmpty) {
        startFirestoreSubscription(parentId: actualParentId, childId: childId);
      }

      if (await NetworkHelper.isOnline()) {
        if (currentUser?.type == UserType.parent) {
          await _taskRepo.pullParentTasks(actualParentId);
        } else if (currentUser?.type == UserType.therapist && childId != null) {
          await _taskRepo.pullChildTasks(actualParentId, childId);
        }

        await mergeRemoteTasks(
          parentId: actualParentId,
          childId: childId,
          isParent: isParent,
        );
      }
    } finally {
      _setLoading(false);
    }
  }

  // Helper to load current child
  Future<void> _loadCurrentChild(String childId) async {
    try {
      currentChild = await _userRepo.fetchChildAndCacheById(childId);
      if (currentChild != null) {
        debugPrint('👶 Current child loaded: ${currentChild!.name}');
      }
    } catch (e) {
      debugPrint('⚠️ Failed to load current child: $e');
    }
  }

  void _setLoading(bool value) {
    _isLoading = value;
    notifyListeners();
  }

  // ---------------- MERGE REMOTE ----------------
  Future<void> mergeRemoteTasks({
    required String parentId,
    String? childId,
    bool isParent = false,
  }) async {
    try {
      // ✅ Get actual parent ID for merging
      String actualParentId = parentId;
      if (currentUser?.type == UserType.therapist && childId != null) {
        final fetchedParentId = await _getParentIdForChild(childId);
        if (fetchedParentId != null) {
          actualParentId = fetchedParentId;
        } else {
          debugPrint(
            '⚠️ Cannot merge remote tasks: parentId not found for child $childId',
          );
          return;
        }
      }

      List<TaskModel> remoteTasks = [];

      if (isParent) {
        await _taskRepo.pullParentTasks(actualParentId);
        remoteTasks = _taskRepo
            .getAllTasksLocal()
            .where((t) => t.parentId == actualParentId)
            .toList();
      } else if (childId != null && childId.isNotEmpty) {
        await _taskRepo.pullChildTasks(actualParentId, childId);
        remoteTasks = _taskRepo
            .getAllTasksLocal()
            .where((t) => t.parentId == actualParentId && t.childId == childId)
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

  // ---------------- GET PARENT ID FOR CHILD ----------------
  Future<String?> _getParentIdForChild(String childId) async {
    if (currentUser?.type != UserType.therapist) {
      return null;
    }

    try {
      final therapistDoc = await _firestore
          .collection('therapists')
          .doc(currentUser!.uid)
          .get();

      if (therapistDoc.exists) {
        final data = therapistDoc.data();
        if (data != null && data['childrenAccessCodes'] != null) {
          final childrenMap = Map<String, dynamic>.from(
            data['childrenAccessCodes'],
          );
          if (childrenMap.containsKey(childId)) {
            final childEntry = Map<String, dynamic>.from(childrenMap[childId]);
            return childEntry['parentUid'] as String?;
          }
        }
      }
    } catch (e) {
      debugPrint('⚠️ Failed to fetch parentUid from therapist map: $e');
    }

    return null;
  }

  // ---------------- ADD TASK ----------------
  Future<void> addTask(TaskModel task, BuildContext context) async {
    try {
      // ✅ Validate reward
      final rewardInt = int.tryParse(task.reward.toString());
      if (rewardInt == null || rewardInt < 0) {
        _showSnackBar(context, "Reward must be a positive number");
        return;
      }

      String actualParentId = task.parentId;

      // 🔐 If therapist, resolve parent ID for child
      if (currentUser?.type == UserType.therapist) {
        final fetchedParentId = await _getParentIdForChild(task.childId);
        if (fetchedParentId != null) {
          actualParentId = fetchedParentId;
        } else {
          _showSnackBar(
            context,
            "Therapist does not have access to this child's parent.",
          );
          return;
        }
      }

      // ✅ Create the new task
      final newTask = task.copyWith(
        reward: rewardInt,
        id: task.id.isNotEmpty ? task.id : const Uuid().v4(),
        lastUpdated: DateTime.now(),
        creatorId: currentUser?.uid ?? actualParentId,
        creatorType: currentUser?.type.name.toLowerCase() ?? 'parent',
        therapistId: currentUser?.type == UserType.therapist
            ? currentUser!.uid
            : null,
        parentId: actualParentId,
        // Therapist auto-accepts
        isAccepted: currentUser?.type == UserType.therapist,
      );

      // Add to local state
      _tasks.add(newTask);
      await _taskBox?.put(newTask.id, newTask);
      notifyListeners();

      // Save to repository
      await _taskRepo.saveTask(newTask);

      // Schedule alarm if not web
      if (!kIsWeb) {
        await scheduleTaskAlarm(newTask);
      }

      // Show success
      _showSnackBar(context, "Task submitted successfully!");

      // Sync to Firestore
      await _syncToFirestore(newTask, parentIdOverride: actualParentId);
    } catch (e) {
      debugPrint("⚠️ Error adding task: $e");
      _showSnackBar(context, "Failed to add task: ${e.toString()}");
    }
  }

  // Helper method to safely show SnackBar
  void _showSnackBar(BuildContext context, String message) {
    if (context.mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        resetDailyTasks();
        if (context.mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(message)));
        }
      });
    }
  }

  // ---------------- SYNC TO FIRESTORE ----------------
  Future<void> _syncToFirestore(
    TaskModel task, {
    String? parentIdOverride,
  }) async {
    try {
      if (await NetworkHelper.isOnline()) {
        // Use the task's parentId or override
        final actualParentId = parentIdOverride ?? task.parentId;

        // Actor info (who is making the change)
        final actorId = currentUser?.uid ?? 'unknown';
        final actorType = currentUser?.type.name ?? 'parent';

        // Firestore path: always under the correct parent
        final docRef = _firestore
            .collection('users')
            .doc(actualParentId)
            .collection('children')
            .doc(task.childId)
            .collection('tasks')
            .doc(task.id);

        final data = task.toMap();
        data['lastModifiedBy'] = actorId;
        data['lastModifiedByType'] = actorType;
        data['parentId'] =
            actualParentId; // Ensure correct parentId in document

        await docRef.set(data, SetOptions(merge: true));
        debugPrint(
          '✅ Task synced to Firestore by $actorType ($actorId) under parent $actualParentId',
        );
      }
    } catch (e, stack) {
      debugPrint('⚠️ Failed to sync task to Firestore: $e');
      debugPrint(stack.toString());
    }
  }

  Future<void> rejectTaskWithMessage({
    required String taskId,
    required String childId,
    required String reason,
    required String reminder,
  }) async {
    final index = _tasks.indexWhere((t) => t.id == taskId);
    if (index == -1) return;

    final task = _tasks[index];

    // Update task locally
    final updatedTask = task.copyWith(
      isDone: false,
      verified: false,
      rejectionReason: reason.isNotEmpty ? reason : "No reason provided",
      reminderMessage: reminder.isNotEmpty
          ? reminder
          : "Task was not verified. Reason: ${reason.isNotEmpty ? reason : 'No reason provided'}",
      lastUpdated: DateTime.now(),
    );

    _tasks[index] = updatedTask;

    // Save locally
    await _taskBox?.put(updatedTask.id, updatedTask);

    // Update backend / Firestore
    await _taskRepo.updateTask(updatedTask);
    await _syncToFirestore(updatedTask);

    notifyListeners();

    debugPrint("❌ Task '${task.name}' rejected and updated in Firestore");
  }

  Future<void> acceptTask(String taskId, String childId) async {
    try {
      final index = _tasks.indexWhere(
        (t) => t.id == taskId && t.childId == childId,
      );
      if (index == -1) return;

      final task = _tasks[index];

      // ✅ Create a new TaskModel with therapist acceptance
      final updatedTask = task.copyWith(
        isAccepted: true,
        lastUpdated: DateTime.now(),
      );

      // ✅ Use the centralized updateTask method
      await updateTask(updatedTask);

      debugPrint('✅ Task accepted by therapist: ${task.name}');
    } catch (e) {
      debugPrint("⚠️ Error accepting task: $e");
    }
  }

  // ---------------- UPDATE TASK ----------------
  Future<void> updateTask(TaskModel updatedFields) async {
    final index = _tasks.indexWhere((t) => t.id == updatedFields.id);
    if (index == -1) return;

    final oldTask = _tasks[index];

    // 🔐 Permission check
    if (!canManageTask(oldTask)) {
      debugPrint('⚠️ User not allowed to update task ${oldTask.id}');
      return;
    }

    bool? updatedAcceptance = oldTask.isAccepted;

    // ✅ ONLY therapist can approve
    if (currentUser?.type == UserType.therapist) {
      updatedAcceptance = updatedFields.isAccepted;
    }

    final mergedTask = oldTask.copyWith(
      name: updatedFields.name,
      difficulty: updatedFields.difficulty,
      reward: updatedFields.reward,
      routine: updatedFields.routine,
      alarm: updatedFields.alarm,
      isAccepted: updatedAcceptance,
      lastUpdated: DateTime.now(),
    );

    _tasks[index] = mergedTask;

    await _taskBox?.put(mergedTask.id, mergedTask);
    await _taskRepo.updateTask(mergedTask);

    String actualParentId = mergedTask.parentId;

    if (currentUser?.type == UserType.therapist) {
      final fetchedParentId = await _getParentIdForChild(mergedTask.childId);
      if (fetchedParentId != null) {
        actualParentId = fetchedParentId;
      }
    }

    await _syncToFirestore(mergedTask, parentIdOverride: actualParentId);

    notifyListeners();

    if (!kIsWeb) {
      await cancelTaskAlarm(oldTask);

      if (mergedTask.alarm != null) {
        await scheduleTaskAlarm(mergedTask);
      }
    }

    debugPrint('📝 Task updated: ${mergedTask.name}');
  }

  // ---------------- DELETE TASK ----------------
  Future<void> deleteTask(
    String taskId,
    String parentId,
    String childId,
  ) async {
    final index = _tasks.indexWhere((t) => t.id == taskId);
    if (index == -1) return;

    final task = _tasks[index];

    if (!canManageTask(task)) {
      debugPrint('⚠️ User not allowed to delete task ${task.id}');
      return;
    }

    // ✅ Ensure current child is set for this operation
    if (currentChild == null || currentChild!.cid != childId) {
      await _loadCurrentChild(childId);
    }

    // ✅ Get actual parent ID for deletion
    String actualParentId = parentId;
    if (currentUser?.type == UserType.therapist) {
      final fetchedParentId = await _getParentIdForChild(childId);
      if (fetchedParentId != null) {
        actualParentId = fetchedParentId;
      }
    }

    _tasks.removeAt(index);
    await _taskBox?.delete(taskId);
    await _taskRepo.deleteTask(taskId, actualParentId, childId);

    if (!kIsWeb && task.alarm != null) await cancelTaskAlarm(task);

    try {
      await _firestore
          .collection('users')
          .doc(actualParentId)
          .collection('children')
          .doc(childId)
          .collection('tasks')
          .doc(taskId)
          .delete();
      debugPrint('🗑 Task deleted from Firestore: ${task.name}');
    } catch (e) {
      debugPrint('⚠️ Firestore deleteTask failed: $e');
    }

    notifyListeners();
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
    // 🚨 IMPORTANT: Create date with no time component for streak tracking
    final today = DateTime(now.year, now.month, now.day);

    // ✅ Ensure current child is set for this operation
    if (currentChild == null || currentChild!.cid != childId) {
      await _loadCurrentChild(childId);
    }

    // ✅ Handle streak
    final bool isYesterday =
        task.lastCompletedDate != null &&
        _isSameDay(
          task.lastCompletedDate!,
          today.subtract(const Duration(days: 1)),
        );

    final newActiveStreak = isYesterday ? task.activeStreak + 1 : 1;

    // ✅ Get actual parent ID
    String actualParentId = task.parentId;
    if (currentUser?.type == UserType.therapist) {
      final fetchedParentId = await _getParentIdForChild(childId);
      if (fetchedParentId != null) {
        actualParentId = fetchedParentId;
      }
    }

    final updatedTask = task.copyWith(
      isDone: true,
      doneAt: now,
      // 🚨 CRITICAL: Set lastCompletedDate to today (date only, no time)
      lastCompletedDate: today,
      activeStreak: newActiveStreak,
      longestStreak: newActiveStreak > (task.longestStreak)
          ? newActiveStreak
          : task.longestStreak,
      totalDaysCompleted: (task.totalDaysCompleted) + 1,
      lastUpdated: now,
      parentId: actualParentId, // Ensure correct parentId
    );

    _tasks[index] = updatedTask;
    await _taskBox?.put(updatedTask.id, updatedTask);
    // Persist via repository so repo/pending logic knows about change
    try {
      await _taskRepo.saveTask(updatedTask);
    } catch (e) {
      debugPrint('⚠️ _taskRepo.saveTask failed (mark done): $e');
    }

    notifyListeners();

    // ✅ Cancel alarm if exists
    if (!kIsWeb && updatedTask.alarm != null) {
      await cancelTaskAlarm(updatedTask);
    }

    // ✅ Try to sync immediately if online (push this single change)
    if (await NetworkHelper.isOnline()) {
      try {
        await _syncToFirestore(updatedTask);
        // Also ensure syncService flushes any other pending changes for this child
        try {
          await _syncService.syncAllPendingChanges(
            parentId: updatedTask.parentId,
            childId: updatedTask.childId,
          );
        } catch (e) {
          debugPrint('⚠️ syncAllPendingChanges failed (after mark done): $e');
        }
        debugPrint('✅ Task marked done and synced: ${updatedTask.name}');
      } catch (e) {
        debugPrint('⚠️ Firestore sync failed (mark done): $e');
      }
    } else {
      debugPrint('⚠️ Offline: will sync later (mark done).');
    }

    // ✅ Update streak
    await _streakRepo.updateStreak(
      updatedTask.childId,
      actualParentId,
      updatedTask.id,
    );

    // ✅ Notify parent
    await _notifyParentCompletion(updatedTask, childId, actualParentId);

    // ✅ Deduplicate any local duplicates after Firestore resync
    final uniqueTasks = <String, TaskModel>{for (var t in _tasks) t.id: t};
    _tasks = uniqueTasks.values.toList()
      ..sort(
        (a, b) => (b.lastUpdated ?? DateTime(0)).compareTo(
          a.lastUpdated ?? DateTime(0),
        ),
      );

    notifyListeners();
  }

  Future<void> markTaskAsUndone(String taskId, String childId) async {
    final index = _tasks.indexWhere((t) => t.id == taskId);
    if (index == -1) return;

    final task = _tasks[index];
    if (!task.isDone) return;

    final now = DateTime.now();

    // ✅ Ensure current child is set for this operation
    if (currentChild == null || currentChild!.cid != childId) {
      await _loadCurrentChild(childId);
    }

    // ✅ Get actual parent ID
    String actualParentId = task.parentId;
    if (currentUser?.type == UserType.therapist) {
      final fetchedParentId = await _getParentIdForChild(childId);
      if (fetchedParentId != null) {
        actualParentId = fetchedParentId;
      }
    }

    // ✅ Decrease totalDaysCompleted but don't go below 0
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
      parentId: actualParentId, // Ensure correct parentId
    );

    // ✅ Update local cache and in-memory
    _tasks[index] = updatedTask;
    await _taskBox?.put(updatedTask.id, updatedTask);

    try {
      await _taskRepo.saveTask(updatedTask);
    } catch (e) {
      debugPrint('⚠️ _taskRepo.saveTask failed (mark undone): $e');
    }

    notifyListeners();

    // ✅ Try to sync immediately if online
    if (await NetworkHelper.isOnline()) {
      try {
        await _syncToFirestore(updatedTask, parentIdOverride: actualParentId);

        try {
          await _syncService.syncAllPendingChanges(
            parentId: actualParentId,
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

  Future<void> _notifyParentCompletion(
    TaskModel task,
    String childId,
    String parentId,
  ) async {
    try {
      final childSnapshot = await _firestore
          .collection('users')
          .doc(parentId)
          .collection('children')
          .doc(childId)
          .get();

      final childName = childSnapshot.data()?['name'] ?? 'Your child';

      await notifyParentCompletion(
        parentId: parentId,
        childName: childName,
        itemName: task.name,
        type: 'task_completed',
      );
    } catch (e) {
      debugPrint('⚠️ Failed to notify parent: $e');
    }
  }

  // ---------------- VERIFY TASK ----------------
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
    final earnedXP = levelCalculator.xpFromTask(task.difficulty);

    // ✅ Update task: verified = true
    final verifiedTask = task.copyWith(verified: true, lastUpdated: now);

    // --- LOCAL STATE ---
    _tasks[index] = verifiedTask;
    await _taskBox?.put(verifiedTask.id, verifiedTask);
    notifyListeners();

    // --- REPO ---
    await _taskRepo.verifyTask(taskId, childId);

    // --- XP GRANT (ONLY HERE) ---
    await _userRepo.updateChildXP(task.parentId, childId, earnedXP);

    // 🔹 Update currentChild after fetchChildAndCache
    currentChild = (await _userRepo.fetchChildAndCache(
      task.parentId,
      childId,
    ))!;

    // 🔹 Optional: notify UI about XP change
    onXPChanged?.call(currentChild!.xp);

    _checkAchievements(currentChild!);

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
    _checkAchievements(currentChild!);

    debugPrint('✅ Task verified: ${verifiedTask.name}, XP granted: $earnedXP');
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

    for (var i = 0; i < _tasks.length; i++) {
      final task = _tasks[i];

      // Reset unverified done tasks
      if (task.isDone && !task.verified) {
        final updatedTask = task.copyWith(
          isDone: false,
          doneAt: null,
          lastUpdated: now,
        );
        _tasks[i] = updatedTask;
        await _taskBox?.put(updatedTask.id, updatedTask);
        await _taskRepo.saveTask(updatedTask);
        updated = true;
        continue;
      }

      // Reset verified tasks if lastCompletedDate not today
      if (task.isDone && task.verified && task.lastCompletedDate != null) {
        final lastDone = task.lastCompletedDate!;
        final yesterday = today.subtract(const Duration(days: 1));
        final newActiveStreak = _isSameDay(lastDone, yesterday)
            ? task.activeStreak
            : 0;

        if (!_isSameDay(lastDone, today)) {
          final updatedTask = task.copyWith(
            isDone: false,
            verified: false,
            doneAt: null,
            activeStreak: newActiveStreak,
            lastUpdated: now,
          );
          _tasks[i] = updatedTask;
          await _taskBox?.put(updatedTask.id, updatedTask);
          await _taskRepo.saveTask(updatedTask);
          updated = true;
        }
      }

      // Fix inconsistent state: doneAt set but isDone false
      if (!task.isDone && task.doneAt != null) {
        final updatedTask = task.copyWith(doneAt: null, lastUpdated: now);
        _tasks[i] = updatedTask;
        await _taskBox?.put(updatedTask.id, updatedTask);
        await _taskRepo.saveTask(updatedTask);
        updated = true;
      }
    }

    // Sync to Firestore if online
    if (updated && await NetworkHelper.isOnline()) {
      for (final task in _tasks) {
        await _firestore
            .collection('users')
            .doc(task.parentId)
            .collection('children')
            .doc(task.childId)
            .collection('tasks')
            .doc(task.id)
            .set(task.toMap(), SetOptions(merge: true));
      }
    }

    if (updated) notifyListeners();
  }

  bool _isResetting = false;

  Box get _settingsBox => Hive.box('appSettings');

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
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
    final tomorrow = now.add(const Duration(days: 1));
    final nextMidnight = DateTime(tomorrow.year, tomorrow.month, tomorrow.day);
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
    final millis = _settingsBox.get('lastResetDate') as int?;
    return millis != null ? DateTime.fromMillisecondsSinceEpoch(millis) : null;
  }

  Future<void> setLastResetDate(DateTime date) async {
    await _settingsBox.put('lastResetDate', date.millisecondsSinceEpoch);
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

  // ---------------- CLEANUP ----------------
  @override
  void dispose() {
    _taskSubscription?.cancel();
    _midnightTimer?.cancel();
    super.dispose();
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
