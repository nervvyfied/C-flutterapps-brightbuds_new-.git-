import 'dart:math';
import 'package:brightbuds_new/data/models/therapist_model.dart';
import 'package:brightbuds_new/data/repositories/user_repository.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '/data/services/firestore_service.dart';
import '/data/models/parent_model.dart';
import '/data/models/child_model.dart';
import 'package:google_sign_in/google_sign_in.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirestoreService _firestore = FirestoreService();
  final UserRepository _userRepo = UserRepository();

  User? get currentUser => _auth.currentUser;
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  // ---------------- PARENT ----------------
  Future<ParentUser?> signUpParent(
    String name,
    String email,
    String password,
  ) async {
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

  // ---------------- PARENT GOOGLE LOGIN ----------------
  Future<ParentUser?> signInParentWithGoogle() async {
    try {
      final GoogleSignIn googleSignIn = GoogleSignIn();
      final GoogleSignInAccount? googleUser = await googleSignIn.signIn();

      if (googleUser == null) return null; // User canceled login

      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;

      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      final userCredential = await _auth.signInWithCredential(credential);
      final user = userCredential.user;
      if (user == null) throw Exception("No Firebase user found");

      // Check if parent already exists in Firestore
      ParentUser? parent = await _firestore.getParent(user.uid);

      if (parent == null) {
        // If not, create a new ParentUser
        parent = ParentUser(
          uid: user.uid,
          name: user.displayName ?? '',
          email: user.email ?? '',
          accessCode: "",
          createdAt: DateTime.now(),
        );

        await _firestore.createParent(parent);
      }

      // Cache the user
      await _userRepo.cacheParent(parent);

      return parent;
    } catch (e) {
      throw Exception("Google sign-in failed: $e");
    }
  }

  // ---------------- THERAPIST ----------------
  Future<TherapistUser?> signUpTherapist(
    String name,
    String email,
    String password,
  ) async {
    if (name.isEmpty || email.isEmpty || password.isEmpty) {
      throw Exception("Name, email, and password cannot be empty");
    }

    final credential = await _auth.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );

    final therapist = TherapistUser(
      uid: credential.user!.uid,
      name: name,
      email: email,
      childrenAccessCodes: {},
      createdAt: DateTime.now(), // added createdAt
      isVerified: false,
    );

    await _firestore.createTherapist(therapist);
    return therapist;
  }

  Future<TherapistUser?> loginTherapist(String email, String password) async {
    try {
      // Use FirebaseAuth directly
      final credential = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      // Fetch therapist from Firestore
      final therapist = await _firestore.getTherapist(credential.user!.uid);
      if (therapist == null) {
        // UID exists in Auth but not in Firestore
        await _auth.signOut();
        throw Exception("UID exists in Auth but not in Firestore");
      }

      return therapist;
    } catch (e) {
      debugPrint('❌ Therapist login failed: $e');
      rethrow;
    }
  }

  Future<TherapistUser?> signInTherapistWithGoogle() async {
    try {
      final GoogleSignIn googleSignIn = GoogleSignIn();
      final GoogleSignInAccount? googleUser = await googleSignIn.signIn();

      if (googleUser == null) return null; // User canceled login

      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;

      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      final userCredential = await _auth.signInWithCredential(credential);
      final user = userCredential.user;
      if (user == null) throw Exception("No Firebase user found");

      // Check if therapist already exists in Firestore
      TherapistUser? therapist = await _firestore.getTherapist(user.uid);

      if (therapist == null) {
        // If not, create a new TherapistUser
        therapist = TherapistUser(
          uid: user.uid,
          name: user.displayName ?? '',
          email: user.email ?? '',
          createdAt: DateTime.now(),
          isVerified: false,
        );

        await _firestore.createTherapist(therapist);
      }

      // Cache the user
      await _userRepo.cacheTherapist(therapist);

      return therapist; // ← FIXED: Return the therapist object!
    } catch (e) {
      throw Exception("Google sign-in failed: $e");
    }
  }

  // ---------------- CHILD ----------------
  /// Generates a **unique access code** for a new child
  String generateChildAccessCode({int length = 6}) {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final rand = Random();
    return List.generate(
      length,
      (_) => chars[rand.nextInt(chars.length)],
    ).join();
  }

  Future<ChildUser> childLogin(String accessCode) async {
    final normalizedCode = accessCode.trim().toUpperCase();

    final result = await _firestore.getParentByAccessCodeWithChild(
      normalizedCode,
    );
    if (result == null) throw Exception("Invalid access code");

    final parent = result['parent'] as ParentUser;
    final child = result['child'] as ChildUser?;
    if (child == null) throw Exception("Child not found");

    final updatedChild = ChildUser(
      cid: child.cid,
      parentUid: parent.uid,
      name: child.name,
      balance: child.balance,
      streak: child.streak,
      therapistUid: child.therapistUid,
    );

    await _userRepo.cacheParent(parent);
    await _userRepo.cacheChild(updatedChild);

    return updatedChild;
  }

  // ---------------- SIGN OUT ----------------
  Future<void> signOut() async {
    // 1️⃣ Safely sign out of Firebase and Google
    final googleSignIn = GoogleSignIn();
    final isGoogleUser = await googleSignIn.isSignedIn();

    if (isGoogleUser) {
      await googleSignIn.signOut(); // only signOut(), no need for disconnect()
    }

    await _auth.signOut(); // Firebase sign-out

    // 2️⃣ Clear cached Hive data *after* sign-out
    await _userRepo.clearAllCachedData();

    // 3️⃣ Optional: small delay to ensure async clears complete
    await Future.delayed(const Duration(milliseconds: 300));
  }
}
