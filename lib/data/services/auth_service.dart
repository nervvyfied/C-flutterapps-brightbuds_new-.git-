import 'package:firebase_auth/firebase_auth.dart';
import '/data/models/user_model.dart';
import '/data/services/firestore_service.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirestoreService _firestoreService = FirestoreService();

  User? get currentUser => _auth.currentUser;

  // Stream for Auth state changes
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  // ---------------- PARENT ----------------
  Future<UserModel?> signUpParent(String displayName, String email, String password) async {
  if (displayName.isEmpty || email.isEmpty || password.isEmpty) {
    throw Exception("Name, email, and password cannot be empty");
  }

  final credential = await _auth.createUserWithEmailAndPassword(
    email: email,
    password: password,
  );

  final user = UserModel(
    uid: credential.user!.uid,
    role: "parent",
    name: displayName,
    email: email,
    accessCode: _generateAccessCode(),
    linkedParentId: null,
    createdAt: DateTime.now(),
  );

  await _firestoreService.createUser(user);
  return user;
}


  Future<UserModel?> loginParent(String email, String password) async {
    final credential = await _auth.signInWithEmailAndPassword(
      email: email,
      password: password,
    );

    return await _firestoreService.getUser(credential.user!.uid);
  }

  // ---------------- CHILD ----------------
  Future<String> generateChildAccessCode(String parentUid) async {
  // Fetch parent
  final parent = await _firestoreService.getUser(parentUid);
  if (parent == null) throw Exception("Parent not found");

  final code = _generateAccessCode();
  // Save access code for child linking
  parent.accessCode = code;
  await _firestoreService.updateUser(parent);
  return code;
}

  Future<UserModel?> joinChildWithCode(String accessCode, String childName) async {
  // Find parent with access code
  final parent = await _firestoreService.getParentByAccessCode(accessCode);
  if (parent == null) throw Exception("Invalid access code");

  // Sign in child anonymously in Firebase
  final credential = await _auth.signInAnonymously();

  // Create child user model
  final child = UserModel(
    uid: credential.user!.uid,
    role: "child",
    name: childName,
    email: null, // no email required
    linkedParentId: parent.uid,
    createdAt: DateTime.now(),
  );

  // Save child in Firestore
  await _firestoreService.createUser(child);

  return child;
}

  // ---------------- SIGN OUT ----------------
  Future<void> signOut() async {
    await _auth.signOut();
  }

  // ---------------- HELPERS ----------------
  String _generateAccessCode() {
    return DateTime.now().millisecondsSinceEpoch.toString().substring(7);
  }
}
