import 'dart:async';
import 'dart:convert';
import 'package:brightbuds_new/data/providers/task_provider.dart';
import 'package:brightbuds_new/data/models/therapist_model.dart';
import 'package:brightbuds_new/data/services/firestore_service.dart';
import 'package:brightbuds_new/main.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '/data/models/parent_model.dart';
import '/data/models/child_model.dart';
import '/data/services/auth_service.dart';
import '/data/repositories/user_repository.dart';

class AuthProvider extends ChangeNotifier {
  final AuthService _auth = AuthService();
  final UserRepository _userRepo = UserRepository();
  final FirestoreService _firestore = FirestoreService();

  dynamic currentUserModel; // ParentUser, ChildUser, or TherapistUser
  User? firebaseUser;

  Box<ParentUser>? _parentBox;
  Box<ChildUser>? _childBox;
  Box<TherapistUser>? _therapistBox;
  bool isLoading = true;
  bool _isInitialized = false;
  bool _isDisposed = false;
  bool _isSigningOut = false;

  StreamSubscription<User?>? _authStateSub;
  StreamSubscription<String>? _fcmTokenRefreshSub;

  // Track active async operations
  final Set<String> _activeOperations = {};

  AuthProvider() {
    _init();
  }

  Future<void> _init() async {
    if (_isInitialized) return;

    debugPrint('=== AuthProvider Initializing ===');

    try {
      // 1️⃣ Ensure Hive boxes are open
      await _ensureBoxesOpen();

      // 2️⃣ Attach auth state listener
      _authStateSub = _auth.authStateChanges.listen(_onAuthStateChanged);

      // 3️⃣ Load initial state from cache
      await _loadInitialState();

      // 4️⃣ Setup FCM
      await _setupFcm();

      _isInitialized = true;
      debugPrint('✅ AuthProvider initialized successfully');
    } catch (e, st) {
      debugPrint('❌ AuthProvider initialization failed: $e\n$st');
      _safeSetLoading(false);
    }
  }

  Future<void> _ensureBoxesOpen() async {
    final operationId = 'ensureBoxesOpen';
    _trackOperation(operationId);

    try {
      if (!Hive.isBoxOpen('parentBox')) {
        _parentBox = await Hive.openBox<ParentUser>('parentBox');
      } else {
        _parentBox = Hive.box<ParentUser>('parentBox');
      }

      if (!Hive.isBoxOpen('childBox')) {
        _childBox = await Hive.openBox<ChildUser>('childBox');
      } else {
        _childBox = Hive.box<ChildUser>('childBox');
      }

      if (!Hive.isBoxOpen('therapistBox')) {
        _therapistBox = await Hive.openBox<TherapistUser>('therapistBox');
      } else {
        _therapistBox = Hive.box<TherapistUser>('therapistBox');
      }

      debugPrint('✅ Hive boxes opened successfully');
    } catch (e) {
      debugPrint('❌ Error opening Hive boxes: $e');
      rethrow;
    } finally {
      _untrackOperation(operationId);
    }
  }

  Future<void> _loadInitialState() async {
    final operationId = 'loadInitialState';
    _trackOperation(operationId);

    _safeSetLoading(true);

    try {
      // 1️⃣ Load cached users with proper type hierarchy: Therapist > Parent > Child
      final cachedTherapist = _therapistBox?.values.isNotEmpty == true
          ? _therapistBox!.values.first
          : null;
      final cachedParent = _parentBox?.values.isNotEmpty == true
          ? _parentBox!.values.first
          : null;
      final cachedChild = _childBox?.values.isNotEmpty == true
          ? _childBox!.values.first
          : null;

      if (cachedTherapist != null) {
        currentUserModel = cachedTherapist;
        firebaseUser = null;
        debugPrint(
          '👨‍⚕️ Loaded therapist from cache: ${cachedTherapist.name}',
        );
        _safeNotifyListeners();
      } else if (cachedParent != null) {
        currentUserModel = cachedParent;
        firebaseUser = null;
        debugPrint('👤 Loaded parent from cache: ${cachedParent.name}');
        _safeNotifyListeners();
      } else if (cachedChild != null) {
        currentUserModel = cachedChild;
        firebaseUser = null;
        debugPrint('📱 Loaded child from cache: ${cachedChild.name}');
        _safeNotifyListeners();
      }

      // 2️⃣ Check Firebase auth state (async, won't block UI)
      final fbUser = _auth.currentUser;
      if (fbUser != null) {
        debugPrint('🔥 Firebase user found: ${fbUser.uid}');

        WidgetsBinding.instance.addPostFrameCallback((_) async {
          try {
            // Fetch Therapist first
            final therapist = await _userRepo.fetchTherapistAndCache(
              fbUser.uid,
            );
            if (therapist != null) {
              currentUserModel = therapist;
              firebaseUser = fbUser;
              // Clear other boxes to prevent conflicts
              await _clearAllCacheExcept('therapist', therapist.uid);
              debugPrint('✅ Restored therapist session: ${therapist.name}');
              _safeNotifyListeners();
              await _safeSaveFcmToken();
              return;
            }

            // Then Parent
            final parent = await _userRepo.fetchParentAndCache(fbUser.uid);
            if (parent != null) {
              currentUserModel = parent;
              firebaseUser = fbUser;
              // Clear other boxes to prevent conflicts
              await _clearAllCacheExcept('parent', parent.uid);
              debugPrint('✅ Restored parent session: ${parent.name}');
              _safeNotifyListeners();
              await _safeSaveFcmToken();
              return;
            }

            // No user found
            debugPrint('⚠️ No user found in Firestore for UID: ${fbUser.uid}');
            currentUserModel = null;
            await _auth.signOut();
          } catch (e) {
            debugPrint('⚠️ Background session restore failed: $e');
          } finally {
            _safeSetLoading(false);
          }
        });
      } else {
        _safeSetLoading(false);
      }
    } catch (e, st) {
      debugPrint("❌ Error loading initial state: $e\n$st");
      currentUserModel = null;
      firebaseUser = null;
      _safeSetLoading(false);
      _safeNotifyListeners();
    } finally {
      _untrackOperation(operationId);
    }
  }

  // Helper method to clear all cache except the current user
  Future<void> _clearAllCacheExcept(String type, String uid) async {
    try {
      switch (type) {
        case 'therapist':
          // Keep only this therapist, clear everything else
          final therapist = _therapistBox?.get(uid);
          await _therapistBox?.clear();
          if (therapist != null) {
            await _therapistBox?.put(uid, therapist);
          }
          await _parentBox?.clear();
          await _childBox?.clear();
          break;
        case 'parent':
          // Keep only this parent, clear everything else
          final parent = _parentBox?.get(uid);
          await _parentBox?.clear();
          if (parent != null) {
            await _parentBox?.put(uid, parent);
          }
          await _therapistBox?.clear();
          await _childBox?.clear();
          break;
        case 'child':
          // Keep only this child, clear everything else
          final child = _childBox?.get(uid);
          await _childBox?.clear();
          if (child != null) {
            await _childBox?.put(uid, child);
          }
          await _therapistBox?.clear();
          await _parentBox?.clear();
          break;
      }
    } catch (e) {
      debugPrint('⚠️ Error clearing cache: $e');
    }
  }

  Future<void> _onAuthStateChanged(User? user) async {
    if (_isDisposed || _isSigningOut) return;
    final operationId = 'authStateChanged';
    _trackOperation(operationId);

    try {
      debugPrint('=== Auth State Changed ===');
      debugPrint('Previous firebaseUser: ${firebaseUser?.uid}');
      debugPrint('New firebaseUser: ${user?.uid}');
      debugPrint('Current user model type: ${currentUserModel?.runtimeType}');

      // If same user, skip
      if (user?.uid == firebaseUser?.uid && currentUserModel != null) {
        debugPrint('⚠️ Same user, skipping update');
        return;
      }

      // Clear sensitive data
      firebaseUser = user;
      currentUserModel = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _syncTaskProvider(navigatorKey.currentContext!);
      });

      // Clear all caches when auth state changes (new user or logout)
      await _clearAllCaches();

      _safeNotifyListeners();

      // If signed in, fetch the new user's data
      if (user != null) {
        debugPrint('🔥 User signed in: ${user.uid}');

        // Fetch Therapist first
        final therapist = await _userRepo.fetchTherapistAndCache(user.uid);
        if (therapist != null) {
          currentUserModel = therapist;
          await _clearAllCacheExcept('therapist', therapist.uid);
          _safeNotifyListeners();
          await _safeSaveFcmToken();
          return;
        }

        // Then Parent
        final parent = await _userRepo.fetchParentAndCache(user.uid);
        if (parent != null) {
          currentUserModel = parent;
          await _clearAllCacheExcept('parent', parent.uid);
          _safeNotifyListeners();
          await _safeSaveFcmToken();
          return;
        }

        // No user found in Firestore
        debugPrint('⚠️ No user found in Firestore for UID: ${user.uid}');
        currentUserModel = null;
        _safeNotifyListeners();
      } else {
        debugPrint('👋 User signed out');
      }
    } catch (e, st) {
      debugPrint("❌ Auth state handling failed: $e\n$st");
      currentUserModel = null;
      _safeNotifyListeners();
    } finally {
      _untrackOperation(operationId);
    }
  }

  // Clear all caches (used during logout and auth state changes)
  Future<void> _clearAllCaches() async {
    try {
      await _parentBox?.clear();
      await _childBox?.clear();
      await _therapistBox?.clear();
      debugPrint('✅ All caches cleared');
    } catch (e) {
      debugPrint('⚠️ Error clearing caches: $e');
    }
  }

  // ---------------- SAFE STATE MANAGEMENT ----------------
  void _trackOperation(String operationId) {
    if (_isDisposed) return;
    _activeOperations.add(operationId);
    debugPrint(
      '▶️ Started operation: $operationId (Active: ${_activeOperations.length})',
    );
  }

  void _untrackOperation(String operationId) {
    if (_isDisposed) return;
    _activeOperations.remove(operationId);
    debugPrint(
      '⏹️ Finished operation: $operationId (Active: ${_activeOperations.length})',
    );
  }

  void _safeSetLoading(bool value) {
    if (_isDisposed) return;
    isLoading = value;
    _safeNotifyListeners();
  }

  void _safeNotifyListeners() {
    if (_isDisposed || !hasListeners) return;

    try {
      notifyListeners();
    } catch (e) {
      // Ignore errors when notifying disposed listeners
      debugPrint('⚠️ Failed to notify listeners (may be disposed): $e');
    }
  }

  // ---------------- PARENT METHODS ----------------
  Future<void> signUpParent(String name, String email, String password) async {
    final operationId = 'signUpParent';
    _trackOperation(operationId);

    debugPrint('=== Signing up parent: $email ===');
    try {
      final parent = await _auth.signUpParent(name, email, password);
      if (parent != null) {
        firebaseUser = _auth.currentUser;

        if (firebaseUser != null && !firebaseUser!.emailVerified) {
          await firebaseUser!.sendEmailVerification();
          currentUserModel = parent;
          await _clearAllCacheExcept('parent', parent.uid);
          _safeNotifyListeners();
          debugPrint('✅ Parent signed up, verification email sent');
          return;
        }

        await _saveParentSession(parent);
      }
    } catch (e) {
      debugPrint('❌ Parent signup failed: $e');
      rethrow;
    } finally {
      _untrackOperation(operationId);
    }
  }

  Future<void> loginParent(String email, String password) async {
    final operationId = 'loginParent';
    _trackOperation(operationId);

    try {
      debugPrint('=== Logging in parent: $email ===');

      final parent = await _auth.loginParent(email, password);
      firebaseUser = _auth.currentUser;

      await firebaseUser?.reload();
      firebaseUser = _auth.currentUser;

      if (firebaseUser != null && !firebaseUser!.emailVerified) {
        await _auth.signOut();
        throw Exception("Please verify your email before logging in.");
      }

      if (parent != null) {
        // ✅ Role check
        final isActuallyParent = await _userRepo.isParent(firebaseUser!.uid);
        if (!isActuallyParent) {
          await _auth.signOut();
          throw Exception("This account is not a parent account.");
        }

        await _saveParentSession(parent);
        debugPrint('✅ Parent logged in: ${parent.name}');
      }
    } catch (e) {
      debugPrint('❌ Parent login failed: $e');
      rethrow;
    } finally {
      _untrackOperation(operationId);
    }
  }

  Future<void> signInParentWithGoogle() async {
    final operationId = 'signInParentWithGoogle';
    _trackOperation(operationId);

    try {
      debugPrint('=== Parent Google sign-in ===');

      final parent = await _auth.signInParentWithGoogle();
      firebaseUser = _auth.currentUser;

      if (parent != null) {
        final isActuallyParent = await _userRepo.isParent(firebaseUser!.uid);
        if (!isActuallyParent) {
          await _auth.signOut();
          throw Exception("This Google account is not a parent account.");
        }

        await _saveParentSession(parent);
        debugPrint('✅ Parent Google sign-in successful: ${parent.name}');
      }
    } catch (e) {
      debugPrint('❌ Parent Google sign-in failed: $e');
      rethrow;
    } finally {
      _untrackOperation(operationId);
    }
  }

  Future<void> _saveParentSession(ParentUser parent) async {
    final operationId = 'saveParentSession';
    _trackOperation(operationId);

    debugPrint('=== Saving parent session ===');
    currentUserModel = parent;
    firebaseUser = _auth.currentUser;
    await _clearAllCacheExcept('parent', parent.uid);

    // Save FCM token
    await _safeSaveFcmToken();

    _safeNotifyListeners();
    debugPrint('✅ Parent session saved: ${parent.name}');

    _untrackOperation(operationId);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncTaskProvider(navigatorKey.currentContext!);
    });
  }

  // ---------------- THERAPIST METHODS ----------------
  Future<void> signUpTherapist(
    String name,
    String email,
    String password,
  ) async {
    final operationId = 'signUpTherapist';
    _trackOperation(operationId);

    debugPrint('=== Signing up therapist: $email ===');
    try {
      final therapist = await _auth.signUpTherapist(name, email, password);
      if (therapist != null) {
        firebaseUser = _auth.currentUser;

        if (firebaseUser != null && !firebaseUser!.emailVerified) {
          await firebaseUser!.sendEmailVerification();
          currentUserModel = therapist;
          await _clearAllCacheExcept('therapist', therapist.uid);
          _safeNotifyListeners();
          debugPrint('✅ Therapist signed up, verification email sent');
          return;
        }

        await _saveTherapistSession(therapist);
      }
    } catch (e) {
      debugPrint('❌ Therapist signup failed: $e');
      rethrow;
    } finally {
      _untrackOperation(operationId);
    }
  }

  Future<void> loginTherapist(String email, String password) async {
    final operationId = 'loginTherapist';
    _trackOperation(operationId);

    try {
      debugPrint('=== Logging in therapist: $email ===');

      // Login via AuthService
      final therapist = await _auth.loginTherapist(email, password);
      firebaseUser = _auth.currentUser;

      // 🔒 Only allow login if therapist.isVerified is true
      if (therapist != null && therapist.isVerified != true) {
        await _auth.signOut();
        throw Exception(
          "Your therapist account is pending verification. Please wait for approval.",
        );
      }

      if (therapist != null) {
        // Role check
        final isActuallyTherapist = await _userRepo.isTherapist(
          firebaseUser!.uid,
        );
        if (!isActuallyTherapist) {
          await _auth.signOut();
          throw Exception("This account is not a therapist account.");
        }

        await _saveTherapistSession(therapist);
        debugPrint('✅ Therapist logged in: ${therapist.name}');
      }
    } catch (e) {
      debugPrint('❌ Therapist login failed: $e');
      rethrow;
    } finally {
      _untrackOperation(operationId);
    }
  }

  Future<void> signInTherapistWithGoogle() async {
    final operationId = 'signInTherapistWithGoogle';
    _trackOperation(operationId);

    try {
      debugPrint('=== Therapist Google sign-in ===');

      final therapist = await _auth.signInTherapistWithGoogle();
      firebaseUser = _auth.currentUser;

      if (therapist != null) {
        final isActuallyTherapist = await _userRepo.isTherapist(
          firebaseUser!.uid,
        );
        if (!isActuallyTherapist) {
          await _auth.signOut();
          throw Exception("This Google account is not a therapist account.");
        }

        await _saveTherapistSession(therapist);
        debugPrint('✅ Therapist Google sign-in successful: ${therapist.name}');
      }
    } catch (e) {
      debugPrint('❌ Therapist Google sign-in failed: $e');
      rethrow;
    } finally {
      _untrackOperation(operationId);
    }
  }

  Future<void> linkChildByAccessCode({
    required String code,
    required String therapistUid,
  }) async {
    try {
      await _firestore.linkChildByAccessCode(
        accessCode: code,
        therapistUid: therapistUid,
      );
      // Refresh therapist data
      final therapist = await _userRepo.fetchTherapistAndCache(therapistUid);
      if (therapist != null) {
        await updateCurrentUserModel(therapist);
      }
    } catch (e) {
      debugPrint('Link failed: $e');
      rethrow;
    }
  }

  Future<void> _saveTherapistSession(TherapistUser therapist) async {
    final operationId = 'saveTherapistSession';
    _trackOperation(operationId);

    try {
      currentUserModel = therapist;
      firebaseUser = _auth.currentUser;

      await _clearAllCacheExcept('therapist', therapist.uid);

      await _safeSaveFcmToken();
      _safeNotifyListeners();

      debugPrint('✅ Therapist session saved: ${therapist.name}');
    } finally {
      _untrackOperation(operationId);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _syncTaskProvider(navigatorKey.currentContext!);
      });
    }
  }

  // ---------------- CHILD METHODS ----------------
  Future<ChildUser?> addChild(String name) async {
    final operationId = 'addChild';
    _trackOperation(operationId);

    debugPrint('=== Adding child: $name ===');
    try {
      if (currentUserModel == null || currentUserModel is! ParentUser) {
        debugPrint('❌ Cannot add child: Not logged in as parent');
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
        therapistUid: null,
        xp: 0,
        level: 1,
        currentWorld: 1,
      );

      final createdChild = await _userRepo.createChild(parent.uid, child, code);
      if (createdChild != null) {
        await _childBox?.put(createdChild.cid, createdChild);

        // Refresh parent cache
        final updatedParent = await _userRepo.fetchParentAndCache(parent.uid);
        if (updatedParent != null) {
          currentUserModel = updatedParent;
          await _clearAllCacheExcept('parent', updatedParent.uid);
        }

        debugPrint('✅ Child added: ${createdChild.name}, Code: $code');
      }

      return createdChild;
    } finally {
      _untrackOperation(operationId);
    }
  }

  Future<void> loginChild(String accessCode) async {
    final operationId = 'loginChild';
    _trackOperation(operationId);

    debugPrint('=== Logging in child with code: $accessCode ===');
    try {
      final child = await _auth.childLogin(accessCode);
      currentUserModel = child;
      firebaseUser = null;

      // Clear all other caches first
      await _clearAllCaches();
      // Then save child
      await _childBox?.put(child.cid, child);

      // Save FCM token for child
      await _safeSaveFcmToken();

      _safeNotifyListeners();
      debugPrint('✅ Child logged in: ${child.name}');
    } catch (e) {
      debugPrint('❌ Child login failed: $e');
      rethrow;
    } finally {
      _untrackOperation(operationId);
    }
  }

  // ---------------- SIGN OUT ----------------
  Future<void> signOut() async {
    if (_isSigningOut) return;

    _isSigningOut = true;

    try {
      debugPrint('=== Signing out user ===');

      // Save reference to current user for FCM removal
      final userToSignOut = currentUserModel;

      // 1. Remove FCM token BEFORE clearing local state
      try {
        if (userToSignOut != null) {
          await _safeRemoveFcmToken(userToSignOut);
          debugPrint('✅ FCM token removed');
        }
      } catch (e) {
        debugPrint('⚠️ Failed to remove FCM token: $e');
      }

      // 2. Clear ALL local caches before Firebase operations
      await _clearAllCaches();
      debugPrint('✅ Local caches cleared');
      try {
        final context = navigatorKey.currentContext;
        if (context != null) {
          Provider.of<TaskProvider>(context, listen: false).clearCurrentUser();
        }
      } catch (_) {}

      // 3. Clear SharedPreferences
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.clear();
        debugPrint('✅ SharedPreferences cleared');
      } catch (e) {
        debugPrint('⚠️ Failed to clear SharedPreferences: $e');
      }

      // 4. Sign out Google if needed
      try {
        final googleSignIn = GoogleSignIn();
        if (await googleSignIn.isSignedIn()) {
          await googleSignIn.signOut();
          debugPrint('✅ Signed out from Google');
        }
      } catch (e) {
        debugPrint('⚠️ Google sign-out failed: $e');
      }

      // 5. Sign out Firebase - DO NOT clear persistence, just sign out
      try {
        await _auth.signOut();
        debugPrint('✅ Signed out from Firebase Auth');
      } catch (e) {
        debugPrint('⚠️ Firebase sign-out failed: $e');
      }

      // 6. Reset all state variables
      currentUserModel = null;
      firebaseUser = null;

      _safeNotifyListeners();
      debugPrint('✅ Sign-out completed fully');
    } finally {
      _isSigningOut = false;
    }
  }

  void _syncTaskProvider(BuildContext context) {
    if (_isDisposed) return;

    final taskProvider = Provider.of<TaskProvider>(context, listen: false);

    if (currentUserModel is ParentUser) {
      final parent = currentUserModel as ParentUser;
      taskProvider.setCurrentUser(parent.uid, UserType.parent);
    } else if (currentUserModel is TherapistUser) {
      final therapist = currentUserModel as TherapistUser;
      taskProvider.setCurrentUser(therapist.uid, UserType.therapist);
    } else {}
  }

  Future<void> _safeRemoveFcmToken([dynamic user]) async {
    final currentUser = user ?? currentUserModel;
    if (_isDisposed || currentUser == null) return;

    final operationId = 'removeFcmToken';
    _trackOperation(operationId);

    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token == null) return;

      debugPrint(
        '🗑️ Removing FCM token: $token for ${currentUser.runtimeType}',
      );

      if (currentUser is ParentUser) {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(currentUser.uid)
            .update({
              'fcmTokens': FieldValue.arrayRemove([token]),
            });
      } else if (currentUser is ChildUser) {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(currentUser.parentUid)
            .collection('children')
            .doc(currentUser.cid)
            .update({
              'fcmTokens': FieldValue.arrayRemove([token]),
            });
      } else if (currentUser is TherapistUser) {
        await FirebaseFirestore.instance
            .collection('therapists')
            .doc(currentUser.uid)
            .update({
              'fcmTokens': FieldValue.arrayRemove([token]),
            });
      }

      debugPrint('✅ FCM token removed successfully');
    } catch (e, stack) {
      debugPrint('⚠️ Failed to remove FCM token: $e\n$stack');
    } finally {
      _untrackOperation(operationId);
    }
  }

  // ---------------- UPDATE USER ----------------
  Future<void> updateCurrentUserModel(dynamic updatedUser) async {
    final operationId = 'updateCurrentUserModel';
    _trackOperation(operationId);

    debugPrint('=== Updating user model ===');

    try {
      if (updatedUser is ParentUser) {
        currentUserModel = updatedUser;
        await _clearAllCacheExcept('parent', updatedUser.uid);
        debugPrint('✅ Updated parent: ${updatedUser.name}');
      } else if (updatedUser is ChildUser) {
        currentUserModel = updatedUser;
        await _clearAllCacheExcept('child', updatedUser.cid);
        debugPrint('✅ Updated child: ${updatedUser.name}');
      } else if (updatedUser is TherapistUser) {
        currentUserModel = updatedUser;
        await _clearAllCacheExcept('therapist', updatedUser.uid);
        debugPrint('✅ Updated therapist: ${updatedUser.name}');
      } else {
        debugPrint('⚠️ Unknown user type for update');
        return;
      }

      _safeNotifyListeners();
    } finally {
      _untrackOperation(operationId);
    }
  }

  // ---------------- FCM TOKEN HANDLING ----------------
  Future<void> _setupFcm() async {
    final operationId = 'setupFcm';
    _trackOperation(operationId);

    try {
      // Request permissions
      await FirebaseMessaging.instance.requestPermission();

      // Setup token refresh listener
      _fcmTokenRefreshSub = FirebaseMessaging.instance.onTokenRefresh.listen((
        newToken,
      ) async {
        debugPrint('🔄 FCM token refreshed: $newToken');
        if (isLoggedIn && !_isDisposed) {
          await _safeSaveFcmToken();
        }
      });

      // Save token if user is logged in
      if (isLoggedIn) {
        await _safeSaveFcmToken();
      }

      debugPrint('✅ FCM setup completed');
    } catch (e, stack) {
      debugPrint('❌ FCM setup failed: $e\n$stack');
    } finally {
      _untrackOperation(operationId);
    }
  }

  Future<void> _safeSaveFcmToken() async {
    if (_isDisposed) return;

    final operationId = 'saveFcmToken';
    _trackOperation(operationId);

    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token == null) {
        debugPrint('⚠️ No FCM token available');
        return;
      }

      debugPrint(
        '📱 Saving FCM token: $token for ${currentUserModel?.runtimeType}',
      );

      final timestamp = FieldValue.serverTimestamp();

      if (currentUserModel is ParentUser) {
        final parent = currentUserModel as ParentUser;
        await FirebaseFirestore.instance
            .collection('users')
            .doc(parent.uid)
            .update({
              'fcmToken': token,
              'fcmTokens': FieldValue.arrayUnion([token]),
              'fcmTokenUpdatedAt': timestamp,
              'lastSeen': timestamp,
            });
        debugPrint('✅ Parent FCM token saved: $token');
      } else if (currentUserModel is ChildUser) {
        final child = currentUserModel as ChildUser;
        await FirebaseFirestore.instance
            .collection('users')
            .doc(child.parentUid)
            .collection('children')
            .doc(child.cid)
            .set({
              'fcmToken': token,
              'fcmTokens': FieldValue.arrayUnion([token]),
              'fcmTokenUpdatedAt': timestamp,
              'lastSeen': timestamp,
            }, SetOptions(merge: true));
        debugPrint('✅ Child FCM token saved: $token');
      } else if (currentUserModel is TherapistUser) {
        final therapist = currentUserModel as TherapistUser;
        await FirebaseFirestore.instance
            .collection('therapists')
            .doc(therapist.uid)
            .update({
              'fcmToken': token,
              'fcmTokens': FieldValue.arrayUnion([token]),
              'fcmTokenUpdatedAt': timestamp,
              'lastSeen': timestamp,
            });
        debugPrint('✅ Therapist FCM token saved: $token');
      } else {
        debugPrint('⚠️ Unknown user type, cannot save FCM token');
      }
    } catch (e, stack) {
      debugPrint('❌ Failed to save FCM token: $e\n$stack');
    } finally {
      _untrackOperation(operationId);
    }
  }

  // ---------------- PASSWORD & VERIFICATION METHODS ----------------
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

  Future<void> setPasswordForTherapistUser(String password) async {
    if (firebaseUser == null) throw Exception("No logged-in user");
    await firebaseUser!.updatePassword(password);
  }

  Future<void> setPasswordForTherapistGoogleUser(String password) async {
    if (firebaseUser == null) throw Exception("No logged-in user");

    try {
      await firebaseUser!.updatePassword(password);
      await firebaseUser!.reload();
      var therapist = await _userRepo.fetchTherapistAndCache(firebaseUser!.uid);
      if (therapist != null) await _saveTherapistSession(therapist);
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

  Future<void> checkTherapistEmailVerifiedStatus() async {
    await firebaseUser?.reload();
    if (firebaseUser != null && firebaseUser!.emailVerified) {
      final therapist = await _userRepo.fetchTherapistAndCache(
        firebaseUser!.uid,
      );
      if (therapist != null) await _saveTherapistSession(therapist);
    }
  }

  Future<void> resendVerificationEmailTherapist() async {
    final user = _auth.currentUser;
    if (user != null && !user.emailVerified) {
      await user.sendEmailVerification();
    } else {
      throw Exception("Email is already verified or no user found.");
    }
  }

  Future<void> refreshTherapistData() async {
    if (!isTherapist || currentUserModel == null) return;

    try {
      final therapist = currentUserModel as TherapistUser;
      final refreshedTherapist = await _userRepo.fetchTherapistAndCache(
        therapist.uid,
      );

      if (refreshedTherapist != null) {
        await updateCurrentUserModel(refreshedTherapist);
      }
    } catch (e) {
      debugPrint('Error refreshing therapist data: $e');
    }
  }

  Future<void> saveParentAfterVerification(ParentUser parent) async {
    currentUserModel = parent;
    await _clearAllCacheExcept('parent', parent.uid);
    _safeNotifyListeners();
  }

  Future<void> saveTherapistAfterVerification(TherapistUser therapist) async {
    currentUserModel = therapist;
    await _clearAllCacheExcept('therapist', therapist.uid);
    _safeNotifyListeners();
  }

  // ---------------- HELPERS ----------------
  bool get isLoggedIn => currentUserModel != null;
  bool get isParent => currentUserModel is ParentUser;
  bool get isChild => currentUserModel is ChildUser;
  bool get isTherapist => currentUserModel is TherapistUser;

  ParentUser? get parent => isParent ? currentUserModel as ParentUser : null;
  ChildUser? get child => isChild ? currentUserModel as ChildUser : null;
  TherapistUser? get therapist =>
      isTherapist ? currentUserModel as TherapistUser : null;

  @override
  void dispose() {
    debugPrint('=== Disposing AuthProvider ===');
    debugPrint('Active operations on dispose: ${_activeOperations.length}');

    _isDisposed = true;

    // Cancel all listeners
    _authStateSub?.cancel();
    _fcmTokenRefreshSub?.cancel();

    // Don't close Hive boxes as they might be used elsewhere
    // Just clear references
    _parentBox = null;
    _childBox = null;
    _therapistBox = null;

    super.dispose();
  }
}
