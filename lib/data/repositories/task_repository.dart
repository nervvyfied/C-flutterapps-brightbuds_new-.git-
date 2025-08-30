/*import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:hive/hive.dart';
import '../models/task_model.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

class TaskRepository {
  final _db = FirebaseFirestore.instance;
  final _box = Hive.box<TaskModel>('tasksBox');

  // local CRUD
  Future<void> addTaskLocal(TaskModel task) async {
    await _box.put(task.id, task);
    await _tryPushTask(task);
  }

  Future<void> updateTaskLocal(TaskModel task) async {
    await _box.put(task.id, task);
    await _tryPushTask(task);
  }

  Future<void> deleteTaskLocal(String id) async {
    await _box.delete(id);
    // remove from firestore if online
    if (await _isOnline()) {
      await _db.collection('tasks').doc(id).delete().catchError((_) {});
    }
  }

  List<TaskModel> getAllLocal() => _box.values.toList();

  // push single task when online
  Future<void> _tryPushTask(TaskModel task) async {
    if (!await _isOnline()) return;
    await _db.collection('tasks').doc(task.id).set(task.toFirestore(), SetOptions(merge: true));
  }

  Future<bool> _isOnline() async {
    final conn = await (Connectivity().checkConnectivity());
    return conn != ConnectivityResult.none;
  }

  // Sync: pull tasks for the user (child or parent) and store in Hive
  Future<void> pullTasksForUser(String uid, {bool asParent = false}) async {
    Query query;
    if (asParent) {
      query = _db.collection('tasks').where('createdBy', isEqualTo: uid);
    } else {
      // child sees tasks assigned to them
      query = _db.collection('tasks').where('assignedTo', isEqualTo: uid);
    }
    final snap = await query.get();
    for (final doc in snap.docs) {
      final t = TaskModel.fromFirestore(doc.data(), doc.id);
      await _box.put(t.id, t);
    }
  }

  // push all local tasks to Firestore (used on login)
  Future<void> pushAllLocalToFirestore() async {
    if (!await _isOnline()) return;
    for (final task in _box.values) {
      await _db.collection('tasks').doc(task.id).set(task.toFirestore(), SetOptions(merge: true));
    }
  }
}
*/