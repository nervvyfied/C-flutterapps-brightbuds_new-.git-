import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:hive/hive.dart';
import '../models/user_model.dart';

class UserRepository {
  final _db = FirebaseFirestore.instance;
  final _box = Hive.box<UserModel>('usersBox');

  Future<void> createOrUpdateUser(UserModel user) async {
    await _db.collection('users').doc(user.uid).set(user.toFirestore(), SetOptions(merge: true));
    await _box.put(user.uid, user);
  }

  Future<UserModel?> fetchUserAndCache(String uid) async {
    // try cache first
    if (_box.containsKey(uid)) return _box.get(uid);

    final doc = await _db.collection('users').doc(uid).get();
    if (!doc.exists) return null;
    final user = UserModel.fromFirestore(doc.data()!, doc.id);
    await _box.put(uid, user);
    return user;
  }

  UserModel? getCachedUser(String uid) {
    return _box.get(uid);
  }
}
