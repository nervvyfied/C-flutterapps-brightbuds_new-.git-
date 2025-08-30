import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '/data/services/auth_service.dart';
import '/data/repositories/user_repository.dart';
import '/data/models/user_model.dart';
import '/data/services/sync_service.dart';

class AuthProvider extends ChangeNotifier {
  final AuthService _auth = AuthService();
  final UserRepository _userRepo = UserRepository();
  final SyncService _sync = SyncService();

  UserModel? currentUserModel;
  User? firebaseUser;

  late final Box<UserModel> _userBox;

  AuthProvider() {
    _userBox = Hive.box<UserModel>('usersBox'); // already opened in main.dart
    _auth.authStateChanges.listen(_onAuthStateChanged);
  }

  bool get isHiveReady => _userBox.isOpen;

  Future<void> _onAuthStateChanged(User? user) async {
    firebaseUser = user;

    if (user == null) {
      currentUserModel = null;
      notifyListeners();
      return;
    }

    // Try loading from Hive first
    currentUserModel = _userBox.get(user.uid);

    if (currentUserModel == null) {
      // Fetch from Firestore if not cached
      currentUserModel = await _userRepo.fetchUserAndCache(user.uid);
      if (currentUserModel != null) {
        await _userBox.put(user.uid, currentUserModel!);
      }
    }

    // Kick off sync service
    final isParent = currentUserModel?.role == 'parent';
    await _sync.syncOnLogin(user.uid, isParent: isParent);

    notifyListeners();
  }

  // ---------------- PARENT ----------------
  Future<void> signUpParent(String displayName, String email, String password) async {
    final userModel = await _auth.signUpParent(displayName, email, password);
    if (userModel != null) {
      currentUserModel = userModel;
      firebaseUser = _auth.currentUser;
      await _userBox.put(userModel.uid, userModel);
      notifyListeners();
    }
  }

  Future<void> loginParent(String email, String password) async {
    final userModel = await _auth.loginParent(email, password);
    if (userModel != null) {
      currentUserModel = userModel;
      firebaseUser = _auth.currentUser;
      await _userBox.put(userModel.uid, userModel);
      notifyListeners();
    }
  }

  // ---------------- CHILD ----------------
  Future<String> generateChildCode() async {
    final parentUid = firebaseUser!.uid;
    return await _auth.generateChildAccessCode(parentUid);
  }

  Future<void> childJoin(String accessCode, String childName) async {
    final userModel = await _auth.joinChildWithCode(accessCode, childName);
    if (userModel != null) {
      currentUserModel = userModel;
      firebaseUser = _auth.currentUser;
      await _userBox.put(userModel.uid, userModel);
      notifyListeners();
    }
  }

  // ---------------- SIGN OUT ----------------
  Future<void> signOut() async {
    await _auth.signOut();
    currentUserModel = null;
    firebaseUser = null;
    notifyListeners();
  }
}
