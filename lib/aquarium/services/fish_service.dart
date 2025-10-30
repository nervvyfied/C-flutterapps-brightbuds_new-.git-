import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/ownedFish_model.dart';

class FishService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  Future<void> syncOwnedFishes(
    String parentUid,
    String childId,
    List<OwnedFish> fishes,
  ) async {
    final docRef = _db
        .collection("users")
        .doc(parentUid)
        .collection("children")
        .doc(childId)
        .collection("aquarium")
        .doc("fishes");

    try {
      await docRef.set({
        "ownedFishes": fishes.map((f) => f.toMap()).toList(),
      }, SetOptions(merge: true));

    } catch (e) {
      rethrow;
    }
  }

  Future<List<OwnedFish>> fetchOwnedFishes(
    String parentUid,
    String childId,
  ) async {
    final docRef = _db
        .collection("users")
        .doc(parentUid)
        .collection("children")
        .doc(childId)
        .collection("aquarium")
        .doc("fishes");

    try {
      final snapshot = await docRef.get();

      if (!snapshot.exists || snapshot.data() == null) {
        return [];
      }

      final data = snapshot.data()!;
      if (!data.containsKey("ownedFishes")) return [];

      return (data["ownedFishes"] as List)
          .map((map) => OwnedFish.fromMap(Map<String, dynamic>.from(map)))
          .toList();
    } catch (e) {
      return [];
    }
  }

  Future<int> fetchBalance(String parentUid, String childId) async {
    final childRef = _db
        .collection("users")
        .doc(parentUid)
        .collection("children")
        .doc(childId);
    try {
      final snapshot = await childRef.get();
      if (!snapshot.exists) {
        return 0;
      }
      final data = snapshot.data();
      return data?["balance"] ?? 0;
    } catch (e) {
      return 0;
    }
  }

  Future<void> updateBalance(
    String parentUid,
    String childId,
    int balance,
  ) async {
    final childRef = _db
        .collection("users")
        .doc(parentUid)
        .collection("children")
        .doc(childId);

    try {
      await childRef.set({"balance": balance}, SetOptions(merge: true));
    } catch (e) {
      rethrow;
    }
  }

  /// Optional: Remove owned fish (used in sell)
  Future<void> removeOwnedFish(
    String parentUid,
    String childId,
    String fishId,
  ) async {
    final docRef = _db
        .collection("users")
        .doc(parentUid)
        .collection("children")
        .doc(childId)
        .collection("aquarium")
        .doc("fishes");

    try {
      final snapshot = await docRef.get();
      if (!snapshot.exists) return;

      final data = snapshot.data()!;
      final fishes = (data["ownedFishes"] ?? []) as List;
      fishes.removeWhere((f) => f["id"] == fishId);

      await docRef.set({"ownedFishes": fishes}, SetOptions(merge: true));
    } catch (e) {
      rethrow;
    }
  }
}
