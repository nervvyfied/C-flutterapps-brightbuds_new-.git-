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

  bool isLoading = true;

  AuthProvider() {
    _taskRepo = TaskRepository();
    _parentBox = Hive.box<ParentUser>('parentBox');
    _childBox = Hive.box<ChildUser>('childBox');

    // Restore session at startup
    restoreSession();

    // Listen to Firebase auth changes
    _auth.authStateChanges.listen(_onAuthStateChanged);
  }

  // ---------------- AUTH STATE LISTENER ----------------
  Future<void> _onAuthStateChanged(User? user) async {
    firebaseUser = user;

    if (user != null) {
      // Already logged in as parent
      if (currentUserModel is ParentUser) return;

      // Try to get parent from cache
      currentUserModel = _userRepo.getCachedParent(user.uid) ??
          await _userRepo.fetchParentAndCache(user.uid);

      // Clear cached child
      await _childBox.clear();
    } else {
      // Signed out
      if (currentUserModel is ParentUser) currentUserModel = null;
    }

    notifyListeners();
  }

  // ---------------- RESTORE SESSION ----------------
  Future<void> restoreSession() async {
    isLoading = true;
    notifyListeners();

    try {
      // 1️⃣ Check Firebase parent session first
      firebaseUser = _auth.currentUser;
      if (firebaseUser != null) {
        var parent = _userRepo.getCachedParent(firebaseUser!.uid);
        parent ??= await _userRepo.fetchParentAndCache(firebaseUser!.uid);
        currentUserModel = parent;

        // Clear cached children
        await _childBox.clear();

        isLoading = false;
        notifyListeners();
        return;
      }

      // 2️⃣ Check cached child session
      final cachedChild =
          _childBox.values.isNotEmpty ? _childBox.values.first : null;
      if (cachedChild != null) {
        currentUserModel = cachedChild;
        firebaseUser = null; // child login doesn't use Firebase
      } else {
        currentUserModel = null;
      }
    } catch (e) {
      currentUserModel = null;
    }

    isLoading = false;
    notifyListeners();
  }

  // ---------------- PARENT METHODS ----------------
Future<void> signUpParent(String name, String email, String password) async {
  final parent = await _auth.signUpParent(name, email, password);
  if (parent != null) {
    firebaseUser = _auth.currentUser;

    // 🔹 Send verification email if not verified
    if (firebaseUser != null && !firebaseUser!.emailVerified) {
      await firebaseUser!.sendEmailVerification();
      // Keep parent cached so we can load it after verification
      currentUserModel = parent;
      await _userRepo.cacheParent(parent);
      await _parentBox.put(parent.uid, parent);
      notifyListeners();
      return; // exit here, let VerifyEmailScreen handle navigation
    }

    await _saveParentSession(parent);
  }
}


  Future<void> loginParent(String email, String password) async {
    final parent = await _auth.loginParent(email, password);
    firebaseUser = _auth.currentUser;

    // 🔹 Reload user to check latest email verification status
    await firebaseUser?.reload();
    firebaseUser = _auth.currentUser;

    // 🔹 Prevent login if not verified
    if (firebaseUser != null && !firebaseUser!.emailVerified) {
      await _auth.signOut();
      throw Exception("Please verify your email before logging in.");
    }

    if (parent != null) await _saveParentSession(parent);
  }

  Future<void> signInWithGoogle() async {
    try {
      final parent = await _auth.signInWithGoogle();
      if (parent != null) await _saveParentSession(parent);
    } catch (e) {
      throw Exception("Google sign-in failed: $e");
    }
  }

  Future<void> setPasswordForCurrentUser(String password) async {
    if (firebaseUser == null) throw Exception("No logged-in user");
    await firebaseUser!.updatePassword(password);
  }

  // 🔹 Resend email verification link
  Future<void> resendVerificationEmail() async {
    final user = _auth.currentUser;
    if (user != null && !user.emailVerified) {
      await user.sendEmailVerification();
    } else {
      throw Exception("Email is already verified or no user found.");
    }
  }
Future<void> setPasswordForGoogleUser(String password) async {
  if (firebaseUser == null) throw Exception("No logged-in user");

  try {
    // Update Firebase password
    await firebaseUser!.updatePassword(password);
    await firebaseUser!.reload(); // refresh user

    // Fetch parent model (or create if first time)
    var parent = await _userRepo.fetchParentAndCache(firebaseUser!.uid);
    if (parent != null) {
      // Save session
      await _saveParentSession(parent);
    }
  } catch (e) {
    throw Exception("Failed to set password: $e");
  }
}

  // 🔹 Manually check and refresh email verification status
  Future<void> checkEmailVerifiedStatus() async {
    await firebaseUser?.reload();
    if (firebaseUser != null && firebaseUser!.emailVerified) {
      final parent = await _userRepo.fetchParentAndCache(firebaseUser!.uid);
      if (parent != null) {
        await _saveParentSession(parent);
      }
    }
  }

  Future<void> _saveParentSession(ParentUser parent) async {
    currentUserModel = parent;
    firebaseUser = _auth.currentUser;
    await _userRepo.cacheParent(parent);
    await _parentBox.put(parent.uid, parent);
    // Clear cached children
    await _childBox.clear();
    notifyListeners();
  }

// Add this method to AuthProvider (public)
Future<void> saveParentAfterVerification(ParentUser parent) async {
  currentUserModel = parent;           // set current model
  await _userRepo.cacheParent(parent); // cache in repository
  await _parentBox.put(parent.uid, parent); // save in Hive
  notifyListeners();
}

  // ---------------- CHILD METHODS ----------------
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
      firstVisitUnlocked: false,
    );

    final createdChild = await _userRepo.createChild(parent.uid, child, code);
    if (createdChild != null) {
      await _childBox.put(createdChild.cid, createdChild);

      // Refresh parent data
      final updatedParent = await _userRepo.fetchParentAndCache(parent.uid);
      if (updatedParent != null) {
        currentUserModel = updatedParent;
        await _parentBox.put(updatedParent.uid, updatedParent);
      }
    }

    return createdChild;
  }

  Future<void> loginChild(String accessCode) async {
    final child = await _auth.childLogin(accessCode);
    if (child != null) {
      currentUserModel = child;
      await _userRepo.cacheChild(child);
      await _childBox.put(child.cid, child);
      firebaseUser = null; // child login doesn't use Firebase
      notifyListeners();
    }
  }

  Future<void> signOut() async {
    await _auth.signOut();
    firebaseUser = null;
    currentUserModel = null;
    // Clear all cached boxes
    await _childBox.clear();
    await _parentBox.clear();
    notifyListeners();
  }

  Future<void> logoutChild() async {
    if (currentUserModel is ChildUser) {
      final child = currentUserModel as ChildUser;
      currentUserModel = null;
      await _childBox.delete(child.cid);
      notifyListeners();
    }
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

  // ---------------- HELPERS ----------------
  bool get isLoggedIn => currentUserModel != null;
  bool get isParent => currentUserModel is ParentUser;
  bool get isChild => currentUserModel is ChildUser;
}
