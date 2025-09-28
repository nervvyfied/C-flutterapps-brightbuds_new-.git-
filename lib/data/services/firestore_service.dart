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

  // In FirestoreService
Future<Map<String, dynamic>?> getParentByAccessCodeWithChild(String accessCode) async {
  // 1️⃣ Get all parents
  final parentsSnapshot = await _db.collection('users').get();

  for (var doc in parentsSnapshot.docs) {
    final data = doc.data();
    final childrenMap = Map<String, dynamic>.from(data['childrenAccessCodes'] ?? {});

    // 2️⃣ Check if any child has this access code
    final matchingEntry = childrenMap.entries.firstWhere(
      (entry) => entry.value == accessCode,
      orElse: () => const MapEntry('', ''),
    );

    if (matchingEntry.key.isNotEmpty) {
      final parent = ParentUser.fromMap(data, doc.id);

      // 3️⃣ Fetch the child
      final childDoc = await _db
          .collection('users')
          .doc(doc.id)
          .collection('children')
          .doc(matchingEntry.key)
          .get();

      if (!childDoc.exists) return {"parent": parent, "child": null};

      final child = ChildUser.fromMap(childDoc.data()!, childDoc.id);

      return {"parent": parent, "child": child};
    }
  }

  return null; // no match found
}


Future<ParentUser?> getParentByAccessCode(String code) async {
  final querySnapshot = await _db.collection('users').get();

  for (var doc in querySnapshot.docs) {
    final data = doc.data();

    // 1. Check activeAccessCode directly
    if (data['activeAccessCode'] == code) {
      return ParentUser.fromMap(data, doc.id);
    }

    // 2. Check childrenAccessCodes map
    final childrenMap = Map<String, dynamic>.from(data['childrenAccessCodes'] ?? {});
    if (childrenMap.values.contains(code)) {
      return ParentUser.fromMap(data, doc.id);
    }
  }

  return null;
}


  // ---------------- CHILD ----------------
  Future<void> createChild(String parentUid, ChildUser child, String accessCode) async {
  await _db
      .collection('users')
      .doc(parentUid)
      .collection('children')
      .doc(child.cid)
      .set(child.toMap());

  final parentRef = _db.collection('users').doc(parentUid);

  await _db.runTransaction((transaction) async {
    final snapshot = await transaction.get(parentRef);
    final currentData = snapshot.data() ?? {};

    final existingCodes = Map<String, String>.from(
      currentData['childrenAccessCodes'] ?? {},
    );

    existingCodes[child.cid] = accessCode;

    transaction.update(parentRef, {
      "activeAccessCode": accessCode,
      "childId": child.cid,
      "childrenAccessCodes": existingCodes,
    });
  });
}


  Future<ChildUser?> getChildByAccessCode(String parentUid, String accessCode) async {
  // 1. Get parent
  final parentDoc = await _db.collection('users').doc(parentUid).get();
  if (!parentDoc.exists) return null;

  final parentData = parentDoc.data()!;
  final codes = Map<String, dynamic>.from(parentData['childrenAccessCodes'] ?? {});

  // 2. Find childId by matching code
  final matchingEntry = codes.entries.firstWhere(
    (entry) => entry.value == accessCode,
    orElse: () => const MapEntry('', ''), // fallback if no match
  );

  if (matchingEntry.key.isEmpty) return null;

  // 3. Fetch the actual child doc
  final childDoc = await _db
      .collection('users')
      .doc(parentUid)
      .collection('children')
      .doc(matchingEntry.key)
      .get();

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
