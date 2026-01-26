import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '/data/models/parent_model.dart';
import '/data/models/child_model.dart';
import '/data/services/auth_service.dart';
import '/data/repositories/user_repository.dart';

class AuthProvider extends ChangeNotifier {
  final AuthService _auth = AuthService();
  final UserRepository _userRepo = UserRepository();

  dynamic currentUserModel; // ParentUser or ChildUser
  User? firebaseUser;

  late final Box<ParentUser> _parentBox;
  late final Box<ChildUser> _childBox;

  bool isLoading = true;

  StreamSubscription<User?>? _authStateSub;

  AuthProvider() {

    // IMPORTANT: Assume caller has opened boxes already (same as before).
    // If boxes may not be open, you should open them before constructing provider.
    _parentBox = Hive.box<ParentUser>('parentBox');
    _childBox = Hive.box<ChildUser>('childBox');

    // Use an async initializer to avoid races
    _init();
  }

  Future<void> _init() async {
    // 1) Restore local session (synchronous UI update)
    await restoreSession();

    // 2) Attach auth state listener AFTER restoreSession to avoid races
    _authStateSub = _auth.authStateChanges.listen(_onAuthStateChanged);
  }

  // ---------------- AUTH STATE LISTENER ----------------
  Future<void> _onAuthStateChanged(User? user) async {
    // Save previous state to detect changes
    final previousUserModel = currentUserModel;
    firebaseUser = user;

    if (user != null) {
      // If parent is already loaded from cache and matches uid, do nothing
      if (currentUserModel is ParentUser &&
          (currentUserModel as ParentUser).uid == user.uid) {
        // still update firebaseUser and return
        firebaseUser = user;
        notifyListeners();
        return;
      }

      try {
        // Try to load cached parent first
        final cachedParent = _userRepo.getCachedParent(user.uid);
        if (cachedParent != null) {
          currentUserModel = cachedParent;
        } else {
          // Fetch and cache remotely if not present locally
          final fetchedParent = await _userRepo.fetchParentAndCache(user.uid);
          if (fetchedParent != null) currentUserModel = fetchedParent;
        }

        // Clear local child session when a parent signed-in is detected
        await _childBox.clear();
      } catch (e, st) {
        debugPrint("Auth state sync failed: $e\n$st");
      }
    } else {
      // Firebase says no authenticated user
      firebaseUser = null;

      // Keep the offline child session intact if it exists.
      // Only clear Parent sessions — avoid wiping a child session that may be offline
      if (currentUserModel is ParentUser) {
        currentUserModel = null;
      }
      // If currentUserModel is ChildUser, keep it (offline child stays signed-in)
    }

    // Only notify if the model actually changed (to avoid excessive rebuilds)
    if (previousUserModel != currentUserModel ||
        previousUserModel is! ParentUser) {
      notifyListeners();
    }
  }

  // ---------------- RESTORE SESSION ----------------
  Future<void> restoreSession() async {
    isLoading = true;
    notifyListeners();

    try {
      // 1️⃣ Load offline cache first
      final cachedChild = _childBox.values.isNotEmpty
          ? _childBox.values.first
          : null;
      final cachedParent = _parentBox.values.isNotEmpty
          ? _parentBox.values.first
          : null;

      if (cachedChild != null) {
        currentUserModel = cachedChild;
        firebaseUser = null;
      } else if (cachedParent != null) {
        currentUserModel = cachedParent;
        firebaseUser = null;
      } else {
        currentUserModel = null;
        firebaseUser = null;
      }

      notifyListeners();

      // 2️⃣ Async Firebase session validation (parent only)
      final fbUser = _auth.currentUser;
      if (fbUser != null) {
        var parent = _userRepo.getCachedParent(fbUser.uid);
        parent ??= await _userRepo.fetchParentAndCache(fbUser.uid);

        if (parent != null) {
          currentUserModel = parent;
          await _parentBox.put(parent.uid, parent);
          await _childBox.clear(); // clear old child cache
        }

        firebaseUser = fbUser;
        notifyListeners();
      }
    } catch (e, st) {
      debugPrint("Restore session failed: $e\n$st");
    } finally {
      isLoading = false;
      notifyListeners();
    }
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
    if (currentUserModel == null || currentUserModel is! ParentUser) {
      return null;
    }

    final parent = currentUserModel as ParentUser;
    final code = _auth.generateChildAccessCode();

    final child = ChildUser(
      cid: DateTime.now().millisecondsSinceEpoch.toString(),
      parentUid: parent.uid,
      name: name,
      streak: 0,
      firstVisitUnlocked: false,
      xp: 0,
      level: 1,
      currentWorld: 1,
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
    currentUserModel = child;
    await _userRepo.cacheChild(child);
    await _childBox.put(child.cid, child);
    firebaseUser = null;
    notifyListeners();
    }

  Future<void> signOut() async {
    try {
      // 1️⃣ Prevent race conditions by cancelling the listener first
      await _authStateSub?.cancel();
      _authStateSub = null;

      // 2️⃣ Sign out from Firebase and Google
      await _auth.signOut();

      // 3️⃣ Clear cached user data after auth sign-out
      await _userRepo.clearAllCachedData();
      await _parentBox.clear();
      await _childBox.clear();

      // 4️⃣ Reset provider state
      firebaseUser = null;
      currentUserModel = null;

      notifyListeners();

      // 5️⃣ Reattach authState listener
      _authStateSub = _auth.authStateChanges.listen(_onAuthStateChanged);

      debugPrint("✅ Sign-out completed successfully.");
    } catch (e, st) {
      debugPrint("⚠️ Error during sign-out: $e\n$st");
      rethrow;
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

  @override
  void dispose() {
    _authStateSub?.cancel();
    super.dispose();
  }
}
