import 'package:brightbuds_new/data/models/therapist_model.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import '/data/models/parent_model.dart';
import '/data/models/child_model.dart';
import '/data/services/firestore_service.dart';

class UserRepository {
  final FirestoreService _firestore = FirestoreService();

  final Box<ParentUser> _parentBox = Hive.box<ParentUser>('parentBox');
  final Box<ChildUser> _childBox = Hive.box<ChildUser>('childBox');
  final Box<TherapistUser> _therapistBox = Hive.box<TherapistUser>(
    'therapistBox',
  );

  // ---------------- PARENT ----------------
  Future<void> cacheParent(ParentUser parent) async =>
      await _parentBox.put(parent.uid, parent);

  ParentUser? getCachedParent(String uid) => _parentBox.get(uid);
  Future<bool> isParent(String uid) async {
    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .get();
    return doc.exists;
  }

  /// Get parent by access code (parent only, no child)
  Future<ParentUser?> getParentByAccessCode(String code) async {
    final parent = await _firestore.getParentByAccessCode(code);
    if (parent != null) await cacheParent(parent);
    return parent;
  }

  Future<void> linkChildByAccessCode({
    required String therapistUid,
    required String accessCode,
  }) async {
    try {
      // ✅ Call the Firestore service with correct parameters
      await _firestore.linkChildByAccessCode(
        accessCode: accessCode,
        therapistUid: therapistUid,
      );

      // After linking, refresh therapist cache to include the linked child
      final therapist = await fetchTherapistAndCache(therapistUid);
      if (therapist != null) {
        await cacheTherapist(therapist);
      }

      debugPrint('✅ Child linked successfully to therapist $therapistUid');
    } catch (e) {
      debugPrint('❌ Error linking child by access code: $e');
      rethrow;
    }
  }

  String? getCachedParentId() {
    if (_parentBox.isEmpty) return null;
    return _parentBox.values.first.uid;
  }

  /// Fetch parent from Firestore and cache locally
  Future<ParentUser?> fetchParentAndCache(String parentUid) async {
    try {
      final parent = await _firestore.getParent(parentUid);
      if (parent == null) return null;

      await cacheParent(parent);
      return parent;
    } catch (e) {
      debugPrint('Error fetching parent $parentUid: $e');
      return null;
    }
  }

  /// Fetch parents linked to a specific therapist
  Future<List<ParentUser>> fetchParentsByTherapist(String therapistUid) async {
    try {
      // This method should fetch parents whose children are linked to the therapist
      // First, get all children linked to this therapist
      final childrenStream = _firestore.streamTherapistChildren(therapistUid);

      // We need to collect parent UIDs from children
      final List<String> parentUids = [];

      // Since we can't easily convert stream to future in a simple way,
      // let's use first on the stream
      final children = await childrenStream.first;

      for (final item in children) {
        final parentUid = item['parentUid'] as String;

        if (!parentUids.contains(parentUid)) {
          parentUids.add(parentUid);
        }
      }

      // Now fetch each parent
      final List<ParentUser> parents = [];
      for (final parentUid in parentUids) {
        final parent = await fetchParentAndCache(parentUid);
        if (parent != null) {
          parents.add(parent);
        }
      }

      return parents;
    } catch (e) {
      debugPrint('Error fetching parents by therapist: $e');
      return [];
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

      final children = snapshot.docs
          .map((doc) => ChildUser.fromMap(doc.data(), doc.id))
          .toList();

      // Cache in Hive
      for (var child in children) {
        await cacheChild(child);
      }

      return children;
    } catch (e) {
      debugPrint('Error fetching children for parent $parentUid: $e');
      return [];
    }
  }

  // ---------------- THERAPIST ----------------
  Future<bool> isTherapist(String uid) async {
    final doc = await FirebaseFirestore.instance
        .collection('therapists')
        .doc(uid)
        .get();
    return doc.exists;
  }

  Future<void> cacheTherapist(TherapistUser therapist) async {
    // Deep copy and sanitize timestamps
    final sanitizedChildren = therapist.childrenAccessCodes?.map((key, value) {
      final mapValue = Map<String, dynamic>.from(value);
      if (mapValue['linkedAt'] is Timestamp) {
        mapValue['linkedAt'] = (mapValue['linkedAt'] as Timestamp).toDate();
      }
      return MapEntry(key, mapValue);
    });

    final sanitizedTherapist = TherapistUser(
      uid: therapist.uid,
      name: therapist.name,
      email: therapist.email,
      isVerified: therapist.isVerified,
      createdAt: therapist.createdAt,
      childId: therapist.childId,
      childrenAccessCodes: sanitizedChildren,
    );

    await _therapistBox.put(sanitizedTherapist.uid, sanitizedTherapist);
  }

  TherapistUser? getCachedTherapist(String uid) {
    return _therapistBox.get(uid);
  }

  /// Fetch therapist from Firestore and cache
  Future<TherapistUser?> fetchTherapistAndCache(String therapistUid) async {
    try {
      final therapist = await _firestore.getTherapist(therapistUid);
      if (therapist == null) return null;

      await cacheTherapist(therapist);
      return therapist;
    } catch (e) {
      debugPrint('Error fetching therapist $therapistUid: $e');
      return null;
    }
  }

  /// Get therapist's linked children with full details
  Future<List<Map<String, dynamic>>> getTherapistChildrenWithDetails(
    String therapistUid,
  ) async {
    try {
      return await _firestore.getTherapistChildrenWithDetails(therapistUid);
    } catch (e) {
      debugPrint('Error getting therapist children with details: $e');
      return [];
    }
  }

  /// Unlink child from therapist
  /// Unlink child from therapist
  Future<void> unlinkChildFromTherapist({
    required String childId,
    required String therapistUid,
    required String parentUid,
    required String accessCode, // ADD THIS PARAMETER
  }) async {
    try {
      await _firestore.unlinkChildFromTherapist(
        childId: childId,
        therapistUid: therapistUid,
        parentUid: parentUid,
        accessCode: accessCode, // ADD THIS LINE
      );

      // Refresh therapist cache
      final therapist = await fetchTherapistAndCache(therapistUid);
      if (therapist != null) {
        await cacheTherapist(therapist);
      }

      debugPrint('✅ Child $childId unlinked from therapist $therapistUid');
    } catch (e) {
      debugPrint('Error unlinking child: $e');
      rethrow;
    }
  }

  // ---------------- CHILD ----------------
  Future<void> cacheChild(ChildUser child) async =>
      await _childBox.put(child.cid, child);

  ChildUser? getCachedChild(String id) => _childBox.get(id);

  /// Create child + refresh parent (so access code is updated)
  Future<ChildUser?> createChild(
    String parentUid,
    ChildUser child,
    String accessCode,
  ) async {
    await _firestore.createChild(parentUid, child, accessCode);
    await cacheChild(child);

    // 🔑 Refresh parent cache to include new accessCode mapping
    final updatedParent = await _firestore.getParent(parentUid);
    if (updatedParent != null) {
      await cacheParent(updatedParent);
    }

    return child;
  }

  Future<List<ChildUser>> fetchChildren(String parentUid) async {
    try {
      final snapshot = await _firestore
          .collection('users')
          .doc(parentUid)
          .collection('children')
          .get();

      return snapshot.docs
          .map((doc) => ChildUser.fromMap(doc.data(), doc.id))
          .toList();
    } catch (e) {
      debugPrint('Error fetching children for parent $parentUid: $e');
      return [];
    }
  }

  Future<ChildUser?> fetchChildAndCache(
    String parentUid,
    String childId,
  ) async {
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

    return snapshot.docs
        .map((doc) => ChildUser.fromMap(doc.data(), doc.id))
        .toList();
  }

  Future<Map<String, dynamic>?> fetchParentAndChildByAccessCode(
    String accessCode,
  ) async {
    try {
      final result = await _firestore.getParentByAccessCodeWithChild(
        accessCode,
      );

      if (result == null) return null;

      final parent = result['parent'] as ParentUser;
      final child = result['child'] as ChildUser?;

      await cacheParent(parent);
      if (child != null) {
        await cacheChild(child);
      }

      return {'parent': parent, 'child': child};
    } catch (e) {
      debugPrint('Error fetching parent/child by accessCode: $e');
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
      debugPrint('Error fetching child by ID $childId: $e');
      return null;
    }
  }

  Future<void> clearAllCachedData() async {
    await _parentBox.clear();
    await _childBox.clear();
    await _therapistBox.clear();
  }

  Future<void> updateChildXP(
  String parentUid,
  String childId,
  int xpAmount,
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

    final currentXP = (snapshot.data()?['xp'] ?? 0) as int;
    final newXP = currentXP + xpAmount;

      transaction.update(childRef, {'balance': newBalance});
    });

    await fetchChildAndCache(parentUid, childId);
  }
}
