import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import '/data/models/parent_model.dart';
import '/data/models/child_model.dart';
import '/data/services/firestore_service.dart';

class UserRepository {
  final FirestoreService _firestore = FirestoreService();

  final Box<ParentUser> _parentBox = Hive.box<ParentUser>('parentBox');
  final Box<ChildUser> _childBox = Hive.box<ChildUser>('childBox');

  // ---------------- PARENT ----------------
  Future<void> cacheParent(ParentUser parent) async =>
      await _parentBox.put(parent.uid, parent);

  ParentUser? getCachedParent(String uid) => _parentBox.get(uid);

  /// Get parent by access code (parent only, no child)
  Future<ParentUser?> getParentByAccessCode(String code) async {
    final parent = await _firestore.getParentByAccessCode(code);
    if (parent != null) await cacheParent(parent);
    return parent;
  }

  /// Fetch parent from Firestore and cache locally
  Future<ParentUser?> fetchParentAndCache(String parentUid) async {
    try {
      final parent = await _firestore.getParent(parentUid);
      if (parent == null) return null;

      await cacheParent(parent);
      return parent;
    } catch (e) {
      print('Error fetching parent: $e');
      return null;
    }
  }

  /// Fetch all children for a parent
  Future<List<ChildUser>> fetchChildrenAndCache(String parentUid) async {
    try {
      final snapshot = await _firestore
          .collection('users')
          .doc(parentUid)
          .collection('children')
          .get();

      final children =
          snapshot.docs.map((doc) => ChildUser.fromMap(doc.data(), doc.id)).toList();

      // Cache in Hive
      for (var child in children) {
        await cacheChild(child);
      }

      return children;
    } catch (e) {
      if (kDebugMode) {
        print('Error fetching children: $e');
      }
      return [];
    }
  }

  // ---------------- CHILD ----------------
  Future<void> cacheChild(ChildUser child) async =>
      await _childBox.put(child.cid, child);

  ChildUser? getCachedChild(String id) => _childBox.get(id);

  /// Create child + refresh parent (so access code is updated)
  Future<ChildUser?> createChild(String parentUid, ChildUser child, String code) async {
    await _firestore.createChild(parentUid, child, code);
    await cacheChild(child);

    // 🔑 Refresh parent cache to include new accessCode mapping
    final updatedParent = await _firestore.getParent(parentUid);
    if (updatedParent != null) {
      await cacheParent(updatedParent);
    }

    return child;
  }

  Future<ChildUser?> fetchChildAndCache(String parentUid, String childId) async {
  final child = await _firestore.getChildById(parentUid, childId);
  if (child != null) {
    // Ensure parentUid is correct
    final updatedChild = child.copyWith(parentUid: parentUid);
    await cacheChild(updatedChild);
    return updatedChild;
  }
  return null;
}


  Future<ChildUser?> getChildByAccessCode(String parentUid, String code) async {
    final child = await _firestore.getChildByAccessCode(parentUid, code);
    if (child != null) await cacheChild(child);
    return child;
  }

  Future<List<ChildUser>> getChildrenByParent(String parentUid) async {
  final snapshot = await _firestore
      .collection('users')
      .doc(parentUid)
      .collection('children')
      .get();

  return snapshot.docs.map((doc) => ChildUser.fromMap(doc.data(), doc.id)).toList();
}

  Future<Map<String, dynamic>?> fetchParentAndChildByAccessCode(
      String accessCode) async {
    try {
      final result =
          await _firestore.getParentByAccessCodeWithChild(accessCode);

      if (result == null) return null;

      final parent = result['parent'] as ParentUser;
      final child = result['child'] as ChildUser?;

      await cacheParent(parent);
          if (child != null) {
        await cacheChild(child);
      }

      return {
        'parent': parent,
        'child': child,
      };
    } catch (e) {
      if (kDebugMode) {
        print('Error fetching parent/child by accessCode: $e');
      }
      return null;
    }
  }

  Future<ChildUser?> fetchChildAndCacheById(String childId) async {
  try {
    // 🔍 Search across all parents
    final parentSnapshot = await _firestore.collection('users').get();

    for (var parentDoc in parentSnapshot.docs) {
      final childDoc = await _firestore
          .collection('users')
          .doc(parentDoc.id)
          .collection('children')
          .doc(childId)
          .get();

      if (childDoc.exists) {
        final child = ChildUser.fromMap(childDoc.data()!, childDoc.id);
        await cacheChild(child);
        return child;
      }
    }

    return null;
  } catch (e) {
    print("Error fetching child by id: $e");
    return null;
  }
}


  Future<void> updateChildBalance(
  String parentUid,
  String childId,
  int amount,
) async {
  if (parentUid.isEmpty || childId.isEmpty) {
    throw ArgumentError("parentUid and childId cannot be empty.");
  }

  final childRef = _firestore
      .collection('users')
      .doc(parentUid)
      .collection('children')
      .doc(childId);

  await _firestore.runTransaction((transaction) async {
    final snapshot = await transaction.get(childRef);
    if (!snapshot.exists) {
      throw Exception("Child $childId not found under parent $parentUid");
    }

    final current = (snapshot.data()?['balance'] ?? 0) as int;
    final newBalance = current + amount;

    transaction.update(childRef, {
      'balance': newBalance,
    });
  });

  await fetchChildAndCache(parentUid, childId);
}

}

