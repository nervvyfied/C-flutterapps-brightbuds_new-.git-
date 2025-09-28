import 'package:cloud_firestore/cloud_firestore.dart';
import '/data/models/parent_model.dart';
import '/data/models/child_model.dart';

class FirestoreService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> collection(String path) {
    return _db.collection(path);
  }

  Future<T> runTransaction<T>(
    Future<T> Function(Transaction transaction) action,
  ) {
    return _db.runTransaction(action);
  }

  // ---------------- PARENT ----------------

  Future<void> createParent(ParentUser parent) async {
    await _db.collection('users').doc(parent.uid).set(parent.toMap());
  }

  Future<ParentUser?> getParent(String uid) async {
    final doc = await _db.collection('users').doc(uid).get();
    if (!doc.exists) return null;
    return ParentUser.fromMap(doc.data()!, doc.id);
  }

  Future<Map<String, dynamic>?> getParentByAccessCodeWithChild(String accessCode) async {
    // 🔎 Use a query instead of fetching all users
    final querySnapshot = await _db
        .collection('users')
        .where('activeAccessCode', isEqualTo: accessCode)
        .limit(1)
        .get();

    if (querySnapshot.docs.isEmpty) return null;

    final parentDoc = querySnapshot.docs.first;
    final parent = ParentUser.fromMap(parentDoc.data(), parentDoc.id);

    // ✅ Try to resolve the child from childrenAccessCodes
    final childrenMap = Map<String, String>.from(parentDoc['childrenAccessCodes'] ?? {});
    final matchingEntry = childrenMap.entries.firstWhere(
      (entry) => entry.value == accessCode,
      orElse: () => const MapEntry('', ''),
    );

    if (matchingEntry.key.isEmpty) {
      return {"parent": parent, "child": null};
    }

    final childDoc = await parentDoc.reference.collection('children').doc(matchingEntry.key).get();
    if (!childDoc.exists) return {"parent": parent, "child": null};

    final child = ChildUser.fromMap(childDoc.data()!, childDoc.id);
    return {"parent": parent, "child": child};
  }

  Future<ParentUser?> getParentByAccessCode(String code) async {
    // 🔎 Query by activeAccessCode first
    final querySnapshot = await _db
        .collection('users')
        .where('activeAccessCode', isEqualTo: code)
        .limit(1)
        .get();

    if (querySnapshot.docs.isNotEmpty) {
      final doc = querySnapshot.docs.first;
      return ParentUser.fromMap(doc.data(), doc.id);
    }

    // If not found, scan childrenAccessCodes
    final usersSnapshot = await _db.collection('users').get();
    for (var doc in usersSnapshot.docs) {
      final data = doc.data();
      final childrenMap = Map<String, String>.from(data['childrenAccessCodes'] ?? {});
      if (childrenMap.values.contains(code)) {
        return ParentUser.fromMap(data, doc.id);
      }
    }

    return null;
  }

  // ---------------- CHILD ----------------

  Future<void> createChild(String parentUid, ChildUser child, String accessCode) async {
    final parentRef = _db.collection('users').doc(parentUid);

    await _db.runTransaction((transaction) async {
      final parentSnap = await transaction.get(parentRef);
      final currentData = parentSnap.data() ?? {};

      final existingCodes = Map<String, String>.from(
        currentData['childrenAccessCodes'] ?? {},
      );

      existingCodes[child.cid] = accessCode;

      // ✅ Write child doc
      final childRef = parentRef.collection('children').doc(child.cid);
      transaction.set(childRef, child.toMap());

      // ✅ Update parent doc
      transaction.update(parentRef, {
        "activeAccessCode": accessCode,
        "childrenAccessCodes": existingCodes,
      });
    });
  }

  Future<ChildUser?> getChildByAccessCode(String parentUid, String accessCode) async {
    final parentDoc = await _db.collection('users').doc(parentUid).get();
    if (!parentDoc.exists) return null;

    final parentData = parentDoc.data()!;
    final codes = Map<String, String>.from(parentData['childrenAccessCodes'] ?? {});

    final matchingEntry = codes.entries.firstWhere(
      (entry) => entry.value == accessCode,
      orElse: () => const MapEntry('', ''),
    );

    if (matchingEntry.key.isEmpty) return null;

    final childDoc = await parentDoc.reference.collection('children').doc(matchingEntry.key).get();
    if (!childDoc.exists) return null;

    return ChildUser.fromMap(childDoc.data()!, childDoc.id);
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
}
