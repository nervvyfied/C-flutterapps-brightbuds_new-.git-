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
  CollectionReference get _tasksRef => _firestore.collection('tasks');

  Future<void> saveTaskRemote(TaskModel task) async {
    await _tasksRef
        .doc(task.id)
        .set(task.toFirestore(), SetOptions(merge: true));
  }

  Future<TaskModel?> getTaskRemote(String id) async {
    final doc = await _tasksRef.doc(id).get();
    if (doc.exists && doc.data() != null) {
      return TaskModel.fromFirestore(
          doc.data() as Map<String, dynamic>, doc.id);
    }
    return null;
  }

  Future<List<TaskModel>> getAllTasksRemote({
  String? parentId,
  String? childId,
}) async {
  Query query = _tasksRef;

  if (parentId != null) {
    query = query.where('parentId', isEqualTo: parentId);
  }
  if (childId != null) {
    query = query.where('childId', isEqualTo: childId);
  }

  final snapshot = await query.get();
  return snapshot.docs
      .map((doc) =>
          TaskModel.fromFirestore(doc.data() as Map<String, dynamic>, doc.id))
      .toList();
}


  Future<void> deleteTaskRemote(String id) async {
    await _tasksRef.doc(id).delete();
  }

  // ---------------- SYNC HELPERS ----------------

  /// Save task both locally and remotely (always updates lastUpdated)
  Future<void> saveTask(TaskModel task) async {
  final updatedTask = task.copyWith(
    id: task.id.isNotEmpty ? task.id : const Uuid().v4(),
    lastUpdated: DateTime.now(),
  );

  await saveTaskLocal(updatedTask);
  await saveTaskRemote(updatedTask);
}

  /// Delete task both locally and remotely
  Future<void> deleteTask(String id) async {
    await deleteTaskLocal(id);
    await deleteTaskRemote(id);
  }

  /// Pull tasks for parent (only one child, so this is enough)
  Future<void> pullParentTasks(String parentId) async {
    final remoteTasks = await getAllTasksRemote(parentId: parentId);
    await _mergeRemoteTasks(remoteTasks);
  }

  /// Pull tasks for child (optional, but useful on child login)
  Future<void> pullChildTasks(String childId) async {
  final remoteTasks = await getAllTasksRemote(childId: childId);
  await _mergeRemoteTasks(remoteTasks);
}


  /// Push local tasks that are newer than Firestore
  Future<void> pushPendingLocalChanges() async {
    final localTasks = getAllTasksLocal();

    for (final task in localTasks) {
      final remote = await getTaskRemote(task.id);

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
Future<void> markTaskAsDone(String taskId, String childUid) async {
  try {
    final local = getTaskLocal(taskId);
    if (local != null) {
      final updated = local.copyWith(
        isDone: true,
        doneAt: DateTime.now(),
        lastUpdated: DateTime.now(),
      );

      // Always update Hive first
      await saveTaskLocal(updated);

      // Try pushing to Firestore (safe if offline → retried later)
      await saveTaskRemote(updated);

      // Update streak locally too if you track streaks offline
      await _streakRepo.updateStreak(childUid);
    }
  } catch (e) {
    debugPrint('Error marking task as done: $e');
    rethrow;
  }
}

Future<void> verifyTask(String taskId, String childId) async {
  final localTask = getTaskLocal(taskId);
  if (localTask == null || localTask.verified) return;

  // 1️⃣ Mark task as verified
  final updatedTask = localTask.copyWith(
    verified: true,
    lastUpdated: DateTime.now(),
  );

  await saveTask(updatedTask); // save both Hive & Firestore

  // 2️⃣ Grant reward
  final userRepo = UserRepository();

  // fetch child to get correct parentUid
  final child = await userRepo.getCachedChild(childId);
  if (child != null) {
    await userRepo.updateChildBalance(child.parentUid, child.cid, localTask.reward);
  }
}




}
