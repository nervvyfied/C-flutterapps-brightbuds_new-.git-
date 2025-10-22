import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
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

    // Restore local session first (offline safe)
    restoreSession();

    // Listen for Firebase auth state only when online or signed in
    _auth.authStateChanges.listen(_onAuthStateChanged);
  }

  // ---------------- AUTH STATE LISTENER ----------------
  Future<void> _onAuthStateChanged(User? user) async {
    firebaseUser = user;

    // 🟢 Only handle if parent is logged in via Firebase
    if (user != null) {
      // If already loaded from cache, don’t refetch unnecessarily
      if (currentUserModel is ParentUser &&
          (currentUserModel as ParentUser).uid == user.uid) return;

      try {
        final cachedParent = _userRepo.getCachedParent(user.uid);
        if (cachedParent != null) {
          currentUserModel = cachedParent;
        } else {
          final fetchedParent = await _userRepo.fetchParentAndCache(user.uid);
          if (fetchedParent != null) currentUserModel = fetchedParent;
        }

        // Clear cached children (safety)
        await _childBox.clear();
      } catch (e) {
        debugPrint("Auth state sync failed: $e");
      }
    } else {
      // Signed out or Firebase lost connection
      firebaseUser = null;
      // Keep offline child session intact
      if (!(currentUserModel is ChildUser)) {
        currentUserModel = null;
      }
    }

    notifyListeners();
  }

  // ---------------- RESTORE SESSION ----------------
 Future<void> restoreSession() async {
  isLoading = true;

  // 1️⃣ Load any cached session immediately (offline first)
  final cachedChild = _childBox.values.isNotEmpty ? _childBox.values.first : null;
  final cachedParent = _parentBox.values.isNotEmpty ? _parentBox.values.first : null;

  if (cachedChild != null) {
    // Instant offline restore for child
    currentUserModel = cachedChild;
    firebaseUser = null;
  } else if (cachedParent != null) {
    // Instant offline restore for parent
    currentUserModel = cachedParent;
    firebaseUser = null;
  } else {
    currentUserModel = null;
    firebaseUser = null;
  }

  notifyListeners(); // Immediate UI update

  // 2️⃣ Verify Firebase session asynchronously
  try {
    final fbUser = _auth.currentUser;
    if (fbUser != null) {
      firebaseUser = fbUser;
      // Try cached parent first
      var parent = _userRepo.getCachedParent(fbUser.uid);
      if (parent == null) {
        parent = await _userRepo.fetchParentAndCache(fbUser.uid);
      }

      if (parent != null) {
        currentUserModel = parent;
        await _parentBox.put(parent.uid, parent);
        await _childBox.clear(); // Clear old child session
      }
    }
  } catch (e) {
    debugPrint("Restore session verification failed: $e");
  }

  isLoading = false;
  notifyListeners(); // Update UI after verification
}

  // ---------------- PARENT METHODS ----------------
  Future<void> signUpParent(String name, String email, String password) async {
    final parent = await _auth.signUpParent(name, email, password);
    if (parent != null) {
      firebaseUser = _auth.currentUser;

      if (firebaseUser != null && !firebaseUser!.emailVerified) {
        await firebaseUser!.sendEmailVerification();
        currentUserModel = parent;
        await _userRepo.cacheParent(parent);
        await _parentBox.put(parent.uid, parent);
        notifyListeners();
        return;
      }

      await _saveParentSession(parent);
    }
  }

  Future<void> loginParent(String email, String password) async {
    final parent = await _auth.loginParent(email, password);
    firebaseUser = _auth.currentUser;

    await firebaseUser?.reload();
    firebaseUser = _auth.currentUser;

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
      await firebaseUser!.updatePassword(password);
      await firebaseUser!.reload();
      var parent = await _userRepo.fetchParentAndCache(firebaseUser!.uid);
      if (parent != null) await _saveParentSession(parent);
    } catch (e) {
      throw Exception("Failed to set password: $e");
    }
  }

  Future<void> checkEmailVerifiedStatus() async {
    await firebaseUser?.reload();
    if (firebaseUser != null && firebaseUser!.emailVerified) {
      final parent = await _userRepo.fetchParentAndCache(firebaseUser!.uid);
      if (parent != null) await _saveParentSession(parent);
    }
  }

  Future<void> _saveParentSession(ParentUser parent) async {
    currentUserModel = parent;
    firebaseUser = _auth.currentUser;
    await _userRepo.cacheParent(parent);
    await _parentBox.put(parent.uid, parent);
    await _childBox.clear();
    notifyListeners();
  }

  Future<void> saveParentAfterVerification(ParentUser parent) async {
    currentUserModel = parent;
    await _userRepo.cacheParent(parent);
    await _parentBox.put(parent.uid, parent);
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
      firebaseUser = null;
      notifyListeners();
    }
  }

  // ---------------- SIGN OUT / LOGOUT ----------------
  Future<void> signOut() async {
    await _auth.signOut();
    firebaseUser = null;
    currentUserModel = null;
    await _childBox.clear();
    await _parentBox.clear();
    notifyListeners();
  }

  Future<void> logoutChild() async {
    if (currentUserModel is ChildUser) {
      final child = currentUserModel as ChildUser;
      await _childBox.delete(child.cid);
      currentUserModel = null;
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

  // ---------------- FCM TOKEN HANDLING ----------------
Future<void> saveFcmToken() async {
  final token = await FirebaseMessaging.instance.getToken();
  if (token == null) return;

  try {
    if (currentUserModel is ParentUser) {
      final parent = currentUserModel as ParentUser;
      await FirebaseFirestore.instance
          .collection('users')
          .doc(parent.uid)
          .update({'fcmToken': token});

      debugPrint('✅ Parent FCM token saved: $token');

    } else if (currentUserModel is ChildUser) {
      final child = currentUserModel as ChildUser;
      await FirebaseFirestore.instance
          .collection('users')
          .doc(child.parentUid)
          .collection('children')
          .doc(child.cid)
          .set({'fcmToken': token}, SetOptions(merge: true));

      debugPrint('✅ Child FCM token saved: $token');
    }
  } catch (e) {
    debugPrint('⚠️ Failed to save FCM token: $e');
  }
}


  // ---------------- HELPERS ----------------
  bool get isLoggedIn => currentUserModel != null;
  bool get isParent => currentUserModel is ParentUser;
  bool get isChild => currentUserModel is ChildUser;
}
