import 'dart:math';
import 'package:brightbuds_new/data/repositories/user_repository.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '/data/services/firestore_service.dart';
import '/data/models/parent_model.dart';
import '/data/models/child_model.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirestoreService _firestore = FirestoreService();
  final UserRepository _userRepo = UserRepository();

  User? get currentUser => _auth.currentUser;
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  // ---------------- PARENT ----------------
  Future<ParentUser?> signUpParent(String name, String email, String password) async {
    if (name.isEmpty || email.isEmpty || password.isEmpty) {
      throw Exception("Name, email, and password cannot be empty");
    }

    final credential = await _auth.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );

    final parent = ParentUser(
  uid: credential.user!.uid,
  name: name,
  email: email,
  accessCode: "", // each child gets a unique code
  createdAt: DateTime.now(), // added createdAt
);


    await _firestore.createParent(parent);
    return parent;
  }

  Future<ParentUser?> loginParent(String email, String password) async {
    final credential = await _auth.signInWithEmailAndPassword(
      email: email,
      password: password,
    );

    return await _firestore.getParent(credential.user!.uid);
  }

  // ---------------- CHILD ----------------
  /// Generates a **unique access code** for a new child
  String generateChildAccessCode({int length = 6}) {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final rand = Random();
    return List.generate(length, (_) => chars[rand.nextInt(chars.length)]).join();
  }

  Future<ChildUser> childLogin(String accessCode) async {
  final normalizedCode = accessCode.trim().toUpperCase();
  final result = await _firestore.getParentByAccessCodeWithChild(normalizedCode);
  
  if (result == null) throw Exception("Invalid access code");

  final parent = result['parent'] as ParentUser;
  final child = result['child'] as ChildUser?;

  if (child == null) throw Exception("Child not found for this access code");

  await _userRepo.cacheParent(parent);
  await _userRepo.cacheChild(child);

  return child;
}

  // ---------------- SIGN OUT ----------------
  Future<void> signOut() async {
    await _auth.signOut();
  }
}
