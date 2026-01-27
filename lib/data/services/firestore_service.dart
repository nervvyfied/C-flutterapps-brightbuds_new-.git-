import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '/data/models/parent_model.dart';
import '/data/models/child_model.dart';
import '/data/models/therapist_model.dart';

class FirestoreService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // ---------------- CORE HELPERS ----------------

  CollectionReference<Map<String, dynamic>> collection(String path) {
    return _db.collection(path);
  }

  Future<T> runTransaction<T>(
    Future<T> Function(Transaction transaction) action,
  ) {
    return _db.runTransaction(action);
  }

  // ============================================================
  // ======================= PARENT =============================
  // ============================================================

  Future<void> createParent(ParentUser parent) async {
    await _db.collection('users').doc(parent.uid).set(parent.toMap());
  }

  Future<ParentUser?> getParent(String parentUid) async {
    final doc = await _db.collection('users').doc(parentUid).get();
    if (!doc.exists) return null;
    return ParentUser.fromMap(doc.data()!, doc.id);
  }

  /// Parent lookup via access code (parent OR child)
  Future<ParentUser?> getParentByAccessCode(String code) async {
    final snapshot = await _db.collection('users').get();

    for (final doc in snapshot.docs) {
      final data = doc.data();

      if (data['activeAccessCode'] == code) {
        return ParentUser.fromMap(data, doc.id);
      }

      final childrenAccessCodes = Map<String, dynamic>.from(
        data['childrenAccessCodes'] ?? {},
      );

      // Check if any child has this access code
      for (final entry in childrenAccessCodes.entries) {
        if (entry.value == code) {
          return ParentUser.fromMap(data, doc.id);
        }
      }
    }

    return null;
  }

  /// Parent + Child lookup via access code (child login)
  Future<Map<String, dynamic>?> getParentByAccessCodeWithChild(
    String accessCode,
  ) async {
    final parentsSnapshot = await _db.collection('users').get();

    for (final doc in parentsSnapshot.docs) {
      final parentData = doc.data();

      final childrenAccessCodes = Map<String, dynamic>.from(
        parentData['childrenAccessCodes'] ?? {},
      );

      String? childId;

      // Find which child has this access code
      for (final entry in childrenAccessCodes.entries) {
        if (entry.value == accessCode) {
          childId = entry.key;
          break;
        }
      }

      if (childId == null) continue;

      final parent = ParentUser.fromMap(parentData, doc.id);

      final childDoc = await _db
          .collection('users')
          .doc(doc.id)
          .collection('children')
          .doc(childId)
          .get();

      if (!childDoc.exists) {
        return {"parent": parent, "child": null};
      }

      final child = ChildUser.fromMap(childDoc.data()!, childDoc.id);

      return {"parent": parent, "child": child};
    }

    return null;
  }

  // ============================================================
  // ======================== CHILD ==============================
  // ============================================================

  Future<void> createChild(
    String parentUid,
    ChildUser child,
    String accessCode,
  ) async {
    final parentRef = _db.collection('users').doc(parentUid);
    final childRef = parentRef.collection('children').doc(child.cid);

    await childRef.set(child.toMap());

    // Add access code to parent's childrenAccessCodes
    await _db.runTransaction((transaction) async {
      final snapshot = await transaction.get(parentRef);
      final data = snapshot.data() ?? {};

      final existingCodes = Map<String, dynamic>.from(
        data['childrenAccessCodes'] ?? {},
      );

      // Store as: { childId: accessCode }
      existingCodes[child.cid] = accessCode;

      transaction.update(parentRef, {'childrenAccessCodes': existingCodes});
    });
  }

  Future<ChildUser?> getChildById(String parentUid, String childId) async {
    final doc = await _db
        .collection('users')
        .doc(parentUid)
        .collection('children')
        .doc(childId)
        .get();

    if (!doc.exists) return null;
    return ChildUser.fromMap(doc.data()!, doc.id);
  }

  Future<ChildUser?> getChildByAccessCode(
    String parentUid,
    String accessCode,
  ) async {
    final parentDoc = await _db.collection('users').doc(parentUid).get();
    if (!parentDoc.exists) return null;

    final childrenAccessCodes = Map<String, dynamic>.from(
      parentDoc.data()!['childrenAccessCodes'] ?? {},
    );

    String? childId;

    // Find which child has this access code
    for (final entry in childrenAccessCodes.entries) {
      if (entry.value == accessCode) {
        childId = entry.key;
        break;
      }
    }

    if (childId == null) return null;

    final childDoc = await _db
        .collection('users')
        .doc(parentUid)
        .collection('children')
        .doc(childId)
        .get();

    if (!childDoc.exists) return null;

    return ChildUser.fromMap(childDoc.data()!, childDoc.id);
  }

  // ---------------- HELPER: Find parent and child by access code ----------------
  Future<Map<String, dynamic>?> findParentAndChildByAccessCode(
    String accessCode,
  ) async {
    debugPrint('🔍 Finding parent and child by access code: $accessCode');

    try {
      // Query all parents
      final parentsSnap = await _db.collection('users').get();

      for (final parentDoc in parentsSnap.docs) {
        final parentData = parentDoc.data();
        final childrenAccessCodes = Map<String, dynamic>.from(
          parentData['childrenAccessCodes'] ?? {},
        );

        debugPrint('Checking parent ${parentDoc.id}: $childrenAccessCodes');

        // Look for the access code in this parent's children
        String? foundChildId;
        for (final entry in childrenAccessCodes.entries) {
          if (entry.value == accessCode) {
            foundChildId = entry.key;
            break;
          }
        }

        if (foundChildId != null) {
          // Fetch the child to verify
          final childRef = _db
              .collection('users')
              .doc(parentDoc.id)
              .collection('children')
              .doc(foundChildId);
          final childSnap = await childRef.get();

          if (childSnap.exists) {
            return {
              'parentUid': parentDoc.id,
              'parentData': parentData,
              'childId': foundChildId,
              'childData': childSnap.data(),
              'accessCode': accessCode,
            };
          }
        }
      }

      debugPrint('❌ No parent or child found for access code: $accessCode');
      return null;
    } catch (e) {
      debugPrint('❌ Error finding parent and child by access code: $e');
      return null;
    }
  }

  // ---------------- UPDATED: Link child by access code ----------------
  Future<void> linkChildByAccessCode({
    required String accessCode,
    required String therapistUid,
  }) async {
    debugPrint(
      '🔗 Linking child with access code: $accessCode to therapist: $therapistUid',
    );

    try {
      // 1️⃣ Find parent and child using the access code
      final parentChildInfo = await findParentAndChildByAccessCode(accessCode);

      if (parentChildInfo == null) {
        throw Exception(
          'No child found with access code: $accessCode. Please check the code and try again.',
        );
      }

      final foundParentUid = parentChildInfo['parentUid'] as String;
      final foundChildId = parentChildInfo['childId'] as String;
      final childData = parentChildInfo['childData'] as Map<String, dynamic>?;

      debugPrint('✅ Found child: $foundChildId under parent: $foundParentUid');

      // 2️⃣ Check if child is already linked to another therapist
      if (childData != null) {
        final existingTherapistUid = childData['therapistUid']?.toString();
        if (existingTherapistUid != null && existingTherapistUid.isNotEmpty) {
          // Check if it's already linked to THIS therapist
          if (existingTherapistUid == therapistUid) {
            throw Exception('This child is already linked to you.');
          } else {
            throw Exception(
              'This child is already linked to another therapist.',
            );
          }
        }
      }

      // 3️⃣ Validate child data
      if (childData == null) {
        throw Exception('Child data not found.');
      }

      final childName = childData['name']?.toString() ?? 'Unknown';
      debugPrint('📋 Child details: $childName ($foundChildId)');

      // 4️⃣ Update child document with therapist UID
      final childRef = _db
          .collection('users')
          .doc(foundParentUid)
          .collection('children')
          .doc(foundChildId);

      await childRef.update({
        'therapistUid': therapistUid,
        'linkedAt': FieldValue.serverTimestamp(),
      });
      debugPrint('✅ Updated child with therapist UID');

      // 5️⃣ Update therapist document - GET current data first
      final therapistRef = _db.collection('therapists').doc(therapistUid);

      // Get current therapist data
      final therapistSnap = await therapistRef.get();
      final therapistData = therapistSnap.data() ?? {};

      // Handle both possible structures: array of codes OR map with child data
      dynamic childrenAccessCodes = therapistData['childrenAccessCodes'];

      if (childrenAccessCodes is List) {
        // CASE 1: It's an array of access codes
        final existingAccessCodes = List<String>.from(childrenAccessCodes);

        // Add the new access code if not already present
        if (!existingAccessCodes.contains(accessCode)) {
          existingAccessCodes.add(accessCode);

          await therapistRef.update({
            'childrenAccessCodes': existingAccessCodes,
          });
          debugPrint('✅ Added access code $accessCode to therapist\'s array');
        } else {
          debugPrint(
            'ℹ️ Access code $accessCode already exists in therapist\'s array',
          );
        }
      } else {
        // CASE 2: It's a map with child data (backward compatibility)
        final existingTherapistChildren = Map<String, dynamic>.from(
          childrenAccessCodes ?? {},
        );

        // Add the child to therapist's childrenAccessCodes
        existingTherapistChildren[foundChildId] = {
          'parentUid': foundParentUid,
          'accessCode': accessCode,
          'linkedAt': FieldValue.serverTimestamp(),
          'childName': childName,
        };

        await therapistRef.set({
          'childrenAccessCodes': existingTherapistChildren,
        }, SetOptions(merge: true));
        debugPrint('✅ Added child $foundChildId to therapist\'s map structure');
      }

      debugPrint(
        '✅ Successfully linked child "$childName" ($foundChildId) to therapist $therapistUid',
      );

      // 6️⃣ Optional: Send notification to parent
      await _sendLinkNotificationToParent(
        foundParentUid,
        childName,
        therapistUid,
      );
    } catch (e) {
      debugPrint('❌ Failed to link child: $e');
      rethrow;
    }
  }

  // ---------------- HELPER: Check if access code is already linked ----------------
  Future<bool> isAccessCodeAlreadyLinked(
    String accessCode,
    String therapistUid,
  ) async {
    try {
      final therapistDoc = await _db
          .collection('therapists')
          .doc(therapistUid)
          .get();

      if (therapistDoc.exists) {
        final therapistData = therapistDoc.data()!;
        final childrenAccessCodes = therapistData['childrenAccessCodes'];

        if (childrenAccessCodes is List) {
          // Array of access codes
          return List<String>.from(childrenAccessCodes).contains(accessCode);
        } else if (childrenAccessCodes is Map) {
          // Map structure - check if any entry has this access code
          final mapCodes = Map<String, dynamic>.from(childrenAccessCodes);
          for (final entry in mapCodes.values) {
            if (entry is Map && entry['accessCode'] == accessCode) {
              return true;
            }
          }
        }
      }
      return false;
    } catch (e) {
      debugPrint('❌ Error checking if access code is linked: $e');
      return false;
    }
  }

  // ---------------- HELPER: Send notification to parent ----------------
  Future<void> _sendLinkNotificationToParent(
    String parentUid,
    String childName,
    String therapistUid,
  ) async {
    try {
      // Get therapist info
      final therapistDoc = await _db
          .collection('therapists')
          .doc(therapistUid)
          .get();
      final therapistData = therapistDoc.data();
      final therapistName = therapistData?['name']?.toString() ?? 'A therapist';

      // Create notification in parent's notifications collection
      final notificationRef = _db
          .collection('users')
          .doc(parentUid)
          .collection('notifications')
          .doc();

      await notificationRef.set({
        'type': 'child_linked',
        'title': 'Child Linked to Therapist',
        'message':
            'Your child $childName has been linked to therapist $therapistName.',
        'childName': childName,
        'therapistUid': therapistUid,
        'therapistName': therapistName,
        'timestamp': FieldValue.serverTimestamp(),
        'read': false,
      });

      debugPrint('📬 Sent link notification to parent: $parentUid');
    } catch (e) {
      debugPrint('⚠️ Failed to send notification to parent: $e');
    }
  }

  Future<List<ChildUser>> getChildrenByTherapist(
    String parentUid,
    String therapistUid,
  ) async {
    final snapshot = await _db
        .collection('users')
        .doc(parentUid)
        .collection('children')
        .where('therapistUid', isEqualTo: therapistUid)
        .get();

    return snapshot.docs
        .map((doc) => ChildUser.fromMap(doc.data(), doc.id))
        .toList();
  }

  // ============================================================
  // ====================== THERAPIST ===========================
  // ============================================================

  Future<void> createTherapist(TherapistUser therapist) async {
    await _db
        .collection('therapists')
        .doc(therapist.uid)
        .set(therapist.toMap());
  }

Stream<List<Map<String, dynamic>>> streamTherapistChildren(
  String therapistUid,
) {
  return _db
      .collectionGroup('children')
      .where('therapistUid', isEqualTo: therapistUid)
      .snapshots()
      .map((snapshot) {
        return snapshot.docs.map((doc) {
          final parentUid = doc.reference.parent.parent?.id ?? '';

          final child = ChildUser.fromMap(doc.data(), doc.id);

          return {
            'parentUid': parentUid,
            'childId': child.cid,
            'child': child,
          };
        }).toList();
      });
}
Future<List<Map<String, dynamic>>> getTherapistAssignedChildren(
  String therapistUid,
) async {
  final snapshot = await _db
      .collectionGroup('children')
      .where('therapistUid', isEqualTo: therapistUid)
      .get();

  return snapshot.docs.map((doc) {
    final parentUid = doc.reference.parent.parent!.id;
    final child = ChildUser.fromMap(doc.data(), doc.id);

    return {
      'parentUid': parentUid,
      'childId': child.cid,
      'child': child,
    };
  }).toList();
}


  Future<TherapistUser?> getTherapist(String therapistUid) async {
    final doc = await _db.collection('therapists').doc(therapistUid).get();
    if (!doc.exists) return null;

    return TherapistUser.fromMap(doc.data()!, doc.id);
  }

  // Get therapist's linked children with their details (works with both structures)
  Future<List<Map<String, dynamic>>> getTherapistChildrenWithDetails(
    String therapistUid,
  ) async {
    try {
      final therapistDoc = await _db
          .collection('therapists')
          .doc(therapistUid)
          .get();
      if (!therapistDoc.exists) {
        debugPrint('❌ Therapist document not found: $therapistUid');
        return [];
      }

      final therapistData = therapistDoc.data()!;
      final childrenAccessCodes = therapistData['childrenAccessCodes'];
      final List<Map<String, dynamic>> childrenWithDetails = [];

      if (childrenAccessCodes is List) {
        // CASE 1: Array of access codes
        final accessCodes = List<String>.from(childrenAccessCodes);
        for (final accessCode in accessCodes) {
          final parentChildInfo = await findParentAndChildByAccessCode(
            accessCode,
          );
          if (parentChildInfo == null) continue;

          final childData =
              parentChildInfo['childData'] as Map<String, dynamic>?;
          final parentData =
              parentChildInfo['parentData'] as Map<String, dynamic>?;

          if (childData == null || parentData == null) continue;

          // Convert Timestamps to DateTime
          final linkedAt = childData['linkedAt'] is Timestamp
              ? (childData['linkedAt'] as Timestamp).toDate()
              : childData['linkedAt'] as DateTime?;

          childrenWithDetails.add({
            'cid': childData['cid'] ?? '',
            'name': childData['name'] ?? 'Child',
            'balance': (childData['balance'] as num?)?.toInt() ?? 0,
            'streak': (childData['streak'] as num?)?.toInt() ?? 0,
            'parentUid': parentData['uid'] ?? '',
            'parentName': parentData['name'] ?? 'Parent',
            'accessCode': accessCode,
            'linkedAt': linkedAt,
            'therapistUid': therapistData['uid'] ?? '',
          });
        }
      } else if (childrenAccessCodes is Map) {
        // CASE 2: Map structure with child data
        final mapCodes = Map<String, dynamic>.from(childrenAccessCodes);

        for (final entry in mapCodes.entries) {
          final childId = entry.key;
          final childInfo = Map<String, dynamic>.from(entry.value);
          final parentUid = childInfo['parentUid']?.toString();
          final accessCode = childInfo['accessCode']?.toString();

          if (parentUid == null || parentUid.isEmpty) continue;

          // Get child document
          final childDoc = await _db
              .collection('users')
              .doc(parentUid)
              .collection('children')
              .doc(childId)
              .get();
          final parentDoc = await _db.collection('users').doc(parentUid).get();

          if (!childDoc.exists || !parentDoc.exists) continue;

          final child = ChildUser.fromMap(childDoc.data()!, childId);
          final parent = ParentUser.fromMap(parentDoc.data()!, parentUid);

          // Convert linkedAt Timestamp to DateTime
          final linkedAt = childInfo['linkedAt'] is Timestamp
              ? (childInfo['linkedAt'] as Timestamp).toDate()
              : childInfo['linkedAt'] as DateTime?;

          childrenWithDetails.add({
            'child': child,
            'parent': parent,
            'cid': child.cid,
            'name': child.name,
            'streak': child.streak,
            'parentUid': parent.uid,
            'parentName': parent.name,
            'accessCode': accessCode,
            'linkedAt': linkedAt,
            'therapistUid': therapistUid,
          });
        }
      }

      debugPrint(
        '✅ Found ${childrenWithDetails.length} children for therapist',
      );
      return childrenWithDetails;
    } catch (e, st) {
      debugPrint('❌ Error getting therapist children with details: $e\n$st');
      return [];
    }
  }

  // ---------------- HELPER: Unlink child from therapist (works with both structures) ----------------
  Future<void> unlinkChildFromTherapist({
    required String childId,
    required String therapistUid,
    required String parentUid,
    required String accessCode, // Required for array structure
  }) async {
    try {
      // 1️⃣ Remove therapistUid from child
      await _db
          .collection('users')
          .doc(parentUid)
          .collection('children')
          .doc(childId)
          .update({
            'therapistUid': FieldValue.delete(),
            'linkedAt': FieldValue.delete(),
          });

      // 2️⃣ Remove from therapist's childrenAccessCodes
      final therapistRef = _db.collection('therapists').doc(therapistUid);

      await _db.runTransaction((transaction) async {
        final therapistSnap = await transaction.get(therapistRef);

        if (therapistSnap.exists) {
          final therapistData = therapistSnap.data()!;
          final childrenAccessCodes = therapistData['childrenAccessCodes'];

          if (childrenAccessCodes is List) {
            // CASE 1: Array of access codes
            final existingAccessCodes = List<String>.from(childrenAccessCodes);
            existingAccessCodes.remove(accessCode);

            transaction.update(therapistRef, {
              'childrenAccessCodes': existingAccessCodes,
            });
          } else if (childrenAccessCodes is Map) {
            // CASE 2: Map structure
            final existingMap = Map<String, dynamic>.from(childrenAccessCodes);
            existingMap.remove(childId);

            transaction.update(therapistRef, {
              'childrenAccessCodes': existingMap,
            });
          }
        }
      });

      debugPrint(
        '✅ Successfully unlinked child $childId from therapist $therapistUid',
      );
    } catch (e) {
      debugPrint('❌ Error unlinking child: $e');
      rethrow;
    }
  }

  // ---------------- HELPER: Get all access codes for therapist ----------------
  Future<List<String>> getTherapistAccessCodes(String therapistUid) async {
    try {
      final therapistDoc = await _db
          .collection('therapists')
          .doc(therapistUid)
          .get();

      if (therapistDoc.exists) {
        final therapistData = therapistDoc.data()!;
        final childrenAccessCodes = therapistData['childrenAccessCodes'];

        if (childrenAccessCodes is List) {
          return List<String>.from(childrenAccessCodes);
        } else if (childrenAccessCodes is Map) {
          // Extract access codes from map structure
          final mapCodes = Map<String, dynamic>.from(childrenAccessCodes);
          final accessCodes = <String>[];

          for (final entry in mapCodes.values) {
            if (entry is Map && entry['accessCode'] is String) {
              accessCodes.add(entry['accessCode'] as String);
            }
          }

          return accessCodes;
        }
      }
      return [];
    } catch (e) {
      debugPrint('❌ Error getting therapist access codes: $e');
      return [];
    }
  }

  // ---------------- HELPER: Get child by access code with parent info ----------------
  Future<Map<String, dynamic>?> getChildByAccessCodeWithParent(
    String accessCode,
  ) async {
    try {
      final parentChildInfo = await findParentAndChildByAccessCode(accessCode);

      if (parentChildInfo == null) return null;

      final parentUid = parentChildInfo['parentUid'] as String;
      final childId = parentChildInfo['childId'] as String;
      final childData = parentChildInfo['childData'] as Map<String, dynamic>?;
      final parentData = parentChildInfo['parentData'] as Map<String, dynamic>?;

      return {
        'parentUid': parentUid,
        'parentName': parentData?['name']?.toString() ?? 'Parent',
        'parentEmail': parentData?['email']?.toString() ?? '',
        'childId': childId,
        'childName': childData?['name']?.toString() ?? 'Child',
        'childData': childData,
        'accessCode': accessCode,
        'isLinked': childData?['therapistUid'] != null,
        'linkedTherapistUid': childData?['therapistUid']?.toString(),
      };
    } catch (e) {
      debugPrint('❌ Error getting child by access code: $e');
      return null;
    }
  }
}
