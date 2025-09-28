import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '/data/models/parent_model.dart';
import '/data/models/child_model.dart';
import '/data/services/auth_service.dart';
import '/data/repositories/user_repository.dart';
import '/data/repositories/task_repository.dart';

class AuthProvider extends ChangeNotifier {
  final AuthService _auth = AuthService();
  final UserRepository _userRepo = UserRepository();
  late final TaskRepository _taskRepo;

  dynamic currentUserModel; // ParentUser or ChildUser
  User? firebaseUser;

  late final Box<ParentUser> _parentBox;
  late final Box<ChildUser> _childBox;

  AuthProvider() {
    _taskRepo = TaskRepository();

    _parentBox = Hive.box<ParentUser>('parentBox');
    _childBox = Hive.box<ChildUser>('childBox');

    // Listen for Firebase auth changes (for parents only)
    _auth.authStateChanges.listen(_onAuthStateChanged);
  }

  // ---------------- AUTH STATE ----------------
  Future<void> _onAuthStateChanged(User? user) async {
    firebaseUser = user;

    // If user is null, do not clear child login; only parent
    if (user == null && currentUserModel is ParentUser) {
      currentUserModel = null;
      notifyListeners();
      return;
    }

    if (user != null) {
      // Try to get cached parent first
      var parent = _userRepo.getCachedParent(user.uid);
      if (parent != null) {
        currentUserModel = parent;
      } else {
        currentUserModel = await _userRepo.fetchParentAndCache(user.uid);
      }
      notifyListeners();
    }
  }

  // ---------------- PARENT ----------------
  Future<void> signUpParent(String name, String email, String password) async {
    final parent = await _auth.signUpParent(name, email, password);
    if (parent != null) {
      await _setParentSession(parent);
    }
  }

  Future<void> loginParent(String email, String password) async {
    final parent = await _auth.loginParent(email, password);
    if (parent != null) {
      await _setParentSession(parent);
    }
  }

  Future<void> signInWithGoogle() async {
    try {
      final parent = await _auth.signInWithGoogle();
      if (parent == null) return; // User canceled
      await _setParentSession(parent);
    } catch (e) {
      throw Exception("Google sign-in failed: $e");
    }
  }

  Future<void> _setParentSession(ParentUser parent) async {
    currentUserModel = parent;
    firebaseUser = _auth.currentUser;

    // Cache parent locally
    await _userRepo.cacheParent(parent);
    await _parentBox.put(parent.uid, parent);

    notifyListeners();
  }

  Future<void> setPasswordForCurrentUser(String password) async {
    if (firebaseUser == null) throw Exception("No logged-in user");
    await firebaseUser!.updatePassword(password);
  }

  Future<ChildUser?> addChild(String name) async {
    if (currentUserModel == null || currentUserModel is! ParentUser) return null;

    final parent = currentUserModel as ParentUser;
    final code = _auth.generateChildAccessCode();

    final child = ChildUser(
      cid: DateTime.now().millisecondsSinceEpoch.toString(),
      parentUid: parent.uid,
      name: name,
      balance: 0,
      streak: 0,
    );

    final createdChild = await _userRepo.createChild(parent.uid, child, code);

    if (createdChild != null) {
      await _childBox.put(createdChild.cid, createdChild);

      // Refresh parent data
      final updatedParent = await _userRepo.fetchParentAndCache(parent.uid);
      if (updatedParent != null) {
        currentUserModel = updatedParent;
        await _parentBox.put(updatedParent.uid, updatedParent);

        print(
          "Child '${createdChild.name}' added, accessCode: ${updatedParent.accessCode}",
        );
      }
    }

    return createdChild;
  }

  // ---------------- CHILD ----------------
  Future<void> loginChild(String accessCode) async {
    final child = await _auth.childLogin(accessCode);
    if (child == null) throw Exception("Invalid access code");

    currentUserModel = child;
    firebaseUser = null; // Child doesn't use Firebase auth

    await _userRepo.cacheChild(child);
    await _childBox.put(child.cid, child);

    notifyListeners();
  }

  // ---------------- UPDATE USER ----------------
  Future<void> updateCurrentUserModel(dynamic updatedUser) async {
    if (updatedUser is ParentUser) {
      currentUserModel = updatedUser;
      await _userRepo.cacheParent(updatedUser);
      await _parentBox.put(updatedUser.uid, updatedUser);
    } else if (updatedUser is ChildUser) {
      currentUserModel = updatedUser;
      await _userRepo.cacheChild(updatedUser);
      await _childBox.put(updatedUser.cid, updatedUser);
    }
    notifyListeners();
  }

  // ---------------- SIGN OUT ----------------
  Future<void> signOut() async {
    // If parent is logged in, sign out from Firebase
    if (firebaseUser != null) {
      await _auth.signOut();
    }

    // Clear current session (both parent or child)
    currentUserModel = null;
    firebaseUser = null;

    notifyListeners();
  }
}
