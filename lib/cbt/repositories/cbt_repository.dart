import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:hive/hive.dart';
import '../models/assigned_cbt_model.dart';

class CBTRepository {
  final _firestore = FirebaseFirestore.instance;
  final _hiveBox = Hive.box<AssignedCBT>('assignedCBT');

  Future<void> addAssignedCBT(String parentId, AssignedCBT cbt) async {
    await _hiveBox.put(cbt.id, cbt);
    await _firestore
        .collection('users')
        .doc(parentId)
        .collection('child')
        .doc(cbt.childId)
        .collection('CBT')
        .doc(cbt.id)
        .set(cbt.toMap());
  }

  List<AssignedCBT> getLocalCBTs(String childId) {
    return _hiveBox.values.where((e) => e.childId == childId).toList();
  }

  Future<void> syncFromFirestore(String parentId, String childId) async {
    final snapshot = await _firestore
        .collection('users')
        .doc(parentId)
        .collection('child')
        .doc(childId)
        .collection('CBT')
        .get();

    for (var doc in snapshot.docs) {
      final cbt = AssignedCBT.fromMap(doc.data());
      await _hiveBox.put(cbt.id, cbt);
    }
  }

  Future<void> updateCompletion(String parentId, String childId, String cbtId) async {
    final box = Hive.box<AssignedCBT>('assignedCBT');
    final cbt = box.get(cbtId);
    if (cbt != null) {
      cbt.completed = true;
      cbt.lastCompleted = DateTime.now();
      await box.put(cbt.id, cbt);
      await _firestore
          .collection('users')
          .doc(parentId)
          .collection('child')
          .doc(childId)
          .collection('CBT')
          .doc(cbt.id)
          .update({
        'completed': true,
        'lastCompleted': Timestamp.fromDate(DateTime.now()),
      });
    }
  }
}
