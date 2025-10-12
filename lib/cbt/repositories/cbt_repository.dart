import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import '../models/assigned_cbt_model.dart';

class CBTRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final Box<AssignedCBT> _cbtBox = Hive.box<AssignedCBT>('assignedCBT');

  /// Add a single CBT (Hive + Firestore)
  Future<void> addAssignedCBT(String parentId, AssignedCBT cbt) async {
  try {
    final childRef = _firestore
        .collection('users')
        .doc(parentId)
        .collection('children')
        .doc(cbt.childId);

    // ensure child doc exists
    await childRef.set({}, SetOptions(merge: true));

    final cbtRef = childRef.collection('CBT').doc(cbt.id);

    await cbtRef.set(cbt.toMap());

    await _cbtBox.put(cbt.id, cbt);
    debugPrint('CBT successfully added for ${cbt.childId}');
  } catch (e, st) {
    debugPrint('Failed to add CBT: $e\n$st');
  }
}

  /// Add multiple CBTs
  Future<void> assignMultipleCBTs(
      String parentId, List<AssignedCBT> cbts) async {
    for (final cbt in cbts) {
      await addAssignedCBT(parentId, cbt);
    }
  }

  /// Fetch CBTs from Firestore for a specific week
  Future<List<AssignedCBT>> getAssignedCBTsForWeek(
      String parentId, String childId, int weekOfYear) async {
    final snapshot = await _firestore
        .collection('users')
        .doc(parentId)
        .collection('children')
        .doc(childId)
        .collection('CBT')
        .where('weekOfYear', isEqualTo: weekOfYear)
        .get();

    return snapshot.docs.map((d) => AssignedCBT.fromMap(d.data())).toList();
  }

  List<AssignedCBT> getLocalCBTs(String childId) {
    return _cbtBox.values.where((e) => e.childId == childId).toList();
  }

  Future<void> syncFromFirestore(String parentId, String childId) async {
    final snapshot = await _firestore
        .collection('users')
        .doc(parentId)
        .collection('children')
        .doc(childId)
        .collection('CBT')
        .get();

    for (var doc in snapshot.docs) {
      final cbt = AssignedCBT.fromMap(doc.data());
      await _cbtBox.put(cbt.id, cbt);
    }
  }

  /// Mark CBT as completed (Hive + Firestore)
  Future<void> updateCompletion(
      String parentId, String childId, String cbtId) async {
    final cbt = _cbtBox.get(cbtId);
    if (cbt != null) {
      cbt.completed = true;
      cbt.lastCompleted = DateTime.now();
      await _cbtBox.put(cbt.id, cbt);

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
