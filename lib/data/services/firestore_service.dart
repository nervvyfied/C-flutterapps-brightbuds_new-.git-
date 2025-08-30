import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:hive/hive.dart';
import '../models/user_model.dart';

class FirestoreService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final String userBoxName = "users_box";

  FirestoreService() {
    // Open Hive box if not already open
    if (!Hive.isBoxOpen(userBoxName)) {
      Hive.openBox<UserModel>(userBoxName);
    }
  }

  // ---------------- CREATE ----------------
  Future<void> createUser(UserModel user) async {
    await _db.collection("users").doc(user.uid).set(user.toFirestore());

    // Save to Hive
    final box = Hive.box<UserModel>(userBoxName);
    await box.put(user.uid, user);
  }

  // ---------------- READ ----------------
  Future<UserModel?> getUser(String uid) async {
    final box = Hive.box<UserModel>(userBoxName);
    if (box.containsKey(uid)) {
      return box.get(uid);
    }

    final doc = await _db.collection("users").doc(uid).get();
    if (doc.exists) {
      final user = UserModel.fromFirestore(doc.data()!, doc.id);
      await box.put(uid, user); // cache it
      return user;
    }
    return null;
  }

  // ---------------- UPDATE ----------------
  Future<void> updateUser(UserModel user) async {
    await _db.collection("users").doc(user.uid).update(user.toFirestore());

    // Update Hive cache
    final box = Hive.box<UserModel>(userBoxName);
    await box.put(user.uid, user);
  }

  // ---------------- QUERY PARENT BY ACCESS CODE ----------------
  Future<UserModel?> getParentByAccessCode(String accessCode) async {
    final query = await _db
        .collection("users")
        .where("accessCode", isEqualTo: accessCode)
        .where("role", isEqualTo: "parent")
        .limit(1)
        .get();

    if (query.docs.isNotEmpty) {
      final doc = query.docs.first;
      final parent = UserModel.fromFirestore(doc.data(), doc.id);

      // Cache parent in Hive
      final box = Hive.box<UserModel>(userBoxName);
      await box.put(parent.uid, parent);

      return parent;
    }
    return null;
  }

  // ---------------- UPDATE ACCESS CODE ----------------
  Future<void> updateAccessCode(String uid, String code) async {
    await _db.collection("users").doc(uid).update({"accessCode": code});

    // Update Hive cache if exists
    final box = Hive.box<UserModel>(userBoxName);
    if (box.containsKey(uid)) {
      final user = box.get(uid)!;
      user.accessCode = code;
      await box.put(uid, user);
    }
  }
}
