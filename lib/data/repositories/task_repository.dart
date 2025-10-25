import 'package:brightbuds_new/data/repositories/streak_repository.dart';
import 'package:brightbuds_new/data/repositories/user_repository.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:uuid/uuid.dart';

import '../models/task_model.dart';

class TaskRepository {
  static const String hiveBoxName = 'tasksBox';
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  late final Box<TaskModel> _taskBox;
  final StreakRepository _streakRepo = StreakRepository();

  TaskRepository() {
    _taskBox = Hive.box<TaskModel>(hiveBoxName);
  }

  // ---------------- HIVE (LOCAL) ----------------
  Future<void> saveTaskLocal(TaskModel task) async {
    try {
      await _taskBox.put(task.id, task);
    } catch (e) {
      debugPrint('Error saving task to Hive: $e');
      rethrow;
    }
  }

  TaskModel? getTaskLocal(String id) => _taskBox.get(id);

  List<TaskModel> getAllTasksLocal() => _taskBox.values.toList();

  Future<void> deleteTaskLocal(String id) async {
    await _taskBox.delete(id);
  }

  // ---------------- FIRESTORE (REMOTE) ----------------
  CollectionReference _childTasksRef(String parentId, String childId) {
    if (parentId.isEmpty || childId.isEmpty) {
      throw ArgumentError("parentId and childId must not be empty");
    }
    return _firestore
        .collection('users')
        .doc(parentId)
        .collection('children')
        .doc(childId)
        .collection('tasks');
  }

  Future<void> saveTaskRemote(TaskModel task) async {
    await _childTasksRef(
      task.parentId,
      task.childId,
    ).doc(task.id).set(task.toFirestore(), SetOptions(merge: true));
  }

  Future<TaskModel?> getTaskRemote(
    String parentId,
    String childId,
    String id,
  ) async {
    final doc = await _childTasksRef(parentId, childId).doc(id).get();
    if (doc.exists && doc.data() != null) {
      return TaskModel.fromFirestore(
        doc.data() as Map<String, dynamic>,
        doc.id,
      );
    }
    return null;
  }

  Future<List<TaskModel>> getAllTasksRemote({
    required String parentId,
    required String childId,
  }) async {
    final snapshot = await _childTasksRef(parentId, childId).get();
    return snapshot.docs
        .map(
          (doc) => TaskModel.fromFirestore(
            doc.data() as Map<String, dynamic>,
            doc.id,
          ),
        )
        .toList();
  }

  Future<void> deleteTaskRemote(
    String parentId,
    String childId,
    String id,
  ) async {
    await _childTasksRef(parentId, childId).doc(id).delete();
  }

  // ---------------- SYNC HELPERS ----------------

  /// Save task both locally and remotely (always updates lastUpdated)
  Future<void> saveTask(TaskModel task) async {
    // 1️⃣ Validate parentId and childId
    if (task.parentId.isEmpty) {
      throw Exception("Cannot save task: parentId is empty.");
    }
    if (task.childId.isEmpty) {
      throw Exception("Cannot save task: childId is empty.");
    }

    // 2️⃣ Ensure task has a valid ID and timestamp
    final updatedTask = task.copyWith(
      id: task.id.isNotEmpty ? task.id : const Uuid().v4(),
      lastUpdated: DateTime.now(),
    );

    // 3️⃣ Save locally and remotely
    await saveTaskLocal(updatedTask);
    await saveTaskRemote(updatedTask);

    debugPrint("Task ${updatedTask.id} saved locally and remotely.");
  }

  Future<void> updateTask(TaskModel task) async {
    try {
      if (task.parentId.isEmpty || task.childId.isEmpty) {
        throw Exception("Cannot update task: parentId or childId is empty.");
      }

      // 1️⃣ Always refresh lastUpdated and preserve alarm field
      final existing = _taskBox.get(task.id);
      final updatedTask = task.copyWith(
        alarm: task.alarm ?? existing?.alarm,
        lastUpdated: DateTime.now(),
      );

      // 2️⃣ Save to local Hive
      await saveTaskLocal(updatedTask);

      // 3️⃣ Save to Firestore (merge = true so only changed fields overwrite)
      await _childTasksRef(
        task.parentId,
        task.childId,
      ).doc(task.id).set(updatedTask.toFirestore(), SetOptions(merge: true));

      debugPrint("✅ Task ${updatedTask.id} updated locally and remotely.");
    } catch (e) {
      debugPrint("❌ Error in updateTask: $e");
      rethrow;
    }
  }

  /// Delete task both locally and remotely
  Future<void> deleteTask(
    String taskId,
    String parentUid,
    String childId,
  ) async {
    try {
      // 1. Delete from local Hive
      await _taskBox.delete(taskId);

      // 2. Delete from Firestore
      final taskRef = FirebaseFirestore.instance
          .collection('users')
          .doc(parentUid)
          .collection('children')
          .doc(childId)
          .collection('tasks')
          .doc(taskId);

      await taskRef.delete();
    } catch (e) {
      print("Error deleting task: $e");
      rethrow;
    }
  }

  /// Pull tasks for parent (only one child, so this is enough)
  Future<void> pullParentTasks(String parentId) async {
    // Fetch that single child’s document
    final childSnapshot = await _firestore
        .collection('users')
        .doc(parentId)
        .collection('children')
        .get();

    if (childSnapshot.docs.isEmpty) return;

    // For safety, still loop — but you’ll only ever have 1
    for (var childDoc in childSnapshot.docs) {
      final childId = childDoc.id;

      final remoteTasks = await getAllTasksRemote(
        parentId: parentId,
        childId: childId,
      );

      await _mergeRemoteTasks(remoteTasks);
    }
  }

  /// Pull tasks for child (optional, but useful on child login)
  Future<void> pullChildTasks(String parentId, String childId) async {
    final remoteTasks = await getAllTasksRemote(
      parentId: parentId,
      childId: childId,
    );

    // Clear local tasks for this child first
    final existing = getAllTasksLocal()
        .where((t) => t.parentId == parentId && t.childId == childId)
        .toList();
    for (final t in existing) {
      await deleteTaskLocal(t.id);
    }

    await _mergeRemoteTasks(remoteTasks);
  }

  /// Push local tasks that are newer than Firestore
  Future<void> pushPendingLocalChanges() async {
    final localTasks = getAllTasksLocal();

    for (final task in localTasks) {
      final remote = await getTaskRemote(task.parentId, task.childId, task.id);

      if (remote == null) {
        await saveTaskRemote(task);
      } else {
        // Conflict resolution by lastUpdated
        final localUpdated =
            task.lastUpdated ?? DateTime.fromMillisecondsSinceEpoch(0);
        final remoteUpdated =
            remote.lastUpdated ?? DateTime.fromMillisecondsSinceEpoch(0);

        if (localUpdated.isAfter(remoteUpdated)) {
          await saveTaskRemote(task);
        }
      }
    }
  }

  /// Merge remote tasks into local Hive (respecting lastUpdated)
  Future<void> _mergeRemoteTasks(List<TaskModel> remoteTasks) async {
    for (final remote in remoteTasks) {
      final local = getTaskLocal(remote.id);

      if (local == null) {
        await saveTaskLocal(remote);
      } else {
        final localUpdated =
            local.lastUpdated ?? DateTime.fromMillisecondsSinceEpoch(0);
        final remoteUpdated =
            remote.lastUpdated ?? DateTime.fromMillisecondsSinceEpoch(0);

        if (remoteUpdated.isAfter(localUpdated)) {
          await saveTaskLocal(remote);
        }
      }
    }
  }

  // ---------------- STATUS UPDATES ----------------
  Future<void> markTaskAsDone(String taskId, String childId) async {
    try {
      // 1️⃣ Get local task
      final localTask = getTaskLocal(taskId);
      if (localTask == null) {
        debugPrint("Task $taskId not found locally.");
        return;
      }

      // 2️⃣ Check childId validity
      if (childId.isEmpty) {
        debugPrint("Cannot mark task as done: childId is empty.");
        return;
      }

      // 3️⃣ Mark task as done
      final updatedTask = localTask.copyWith(
        activeStreak: localTask.activeStreak,
        isDone: true,
        doneAt: DateTime.now(),
      );

      // 4️⃣ Save locally first
      await saveTaskLocal(updatedTask);
      debugPrint("Task $taskId marked as done locally.");

      // 5️⃣ Save remotely
      final parentId = localTask.parentId;
      if (parentId.isEmpty) {
        debugPrint("Cannot push task to remote: parentId is empty.");
      } else {
        await saveTaskRemote(updatedTask);
        debugPrint("Task $taskId marked as done remotely.");
      }

      // 6️⃣ Update streak (safe check for child existence)
      final userRepo = UserRepository();
      var child = userRepo.getCachedChild(childId);
      if (child == null && parentId.isNotEmpty) {
        child = await userRepo.fetchChildAndCache(parentId, childId);
      }

      if (child != null) {
        await _streakRepo.updateStreak(child.cid, parentId, taskId);
        debugPrint("Streak updated for child ${child.cid}.");
      } else {
        debugPrint("Cannot update streak: child $childId not found.");
      }
    } catch (e, st) {
      debugPrint('Error in markTaskAsDone: $e\n$st');
      rethrow;
    }
  }

  Future<void> verifyTask(String taskId, String childId) async {
    try {
      // 1️⃣ Get local task
      final localTask = getTaskLocal(taskId);
      if (localTask == null) {
        debugPrint("Task $taskId not found locally.");
        return;
      }

      if (localTask.verified) {
        debugPrint("Task $taskId is already verified.");
        return;
      }

      final parentId = localTask.parentId;
      if (parentId.isEmpty || childId.isEmpty) {
        debugPrint(
          "Cannot verify task: parentId or childId is empty. parentId='$parentId', childId='$childId'",
        );
        return;
      }

      // 2️⃣ Mark task as verified
      final updatedTask = localTask.copyWith(verified: true);

      await saveTask(updatedTask); // saves both locally + remotely
      debugPrint("Task $taskId marked as verified locally and remotely.");

      // 3️⃣ Get or fetch child
      final userRepo = UserRepository();
      var child = userRepo.getCachedChild(childId);

      if (child == null) {
        child = await userRepo.fetchChildAndCache(parentId, childId);

        if (child == null) {
          debugPrint("Child $childId under parent $parentId not found.");
          return; // exit early if child cannot be fetched
        }
      }

      // 4️⃣ Ensure child has a valid parentUid
      final childParentUid = child.parentUid.isNotEmpty
          ? child.parentUid
          : parentId;

      // 5️⃣ Update child balance
      await userRepo.updateChildBalance(
        childParentUid,
        child.cid,
        updatedTask.reward,
      );

      debugPrint(
        "Task $taskId verified and child ${child.cid} balance updated successfully.",
      );
    } catch (e, st) {
      debugPrint('Error in verifyTask: $e\n$st');
      rethrow;
    }
  }
}
