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

      print("✅ Firestore: ownedFishes successfully synced (${fishes.length})");
    } catch (e) {
      print("❌ Firestore syncOwnedFishes failed: $e");
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
        print("ℹ️ Firestore: no fishes found remotely");
        return [];
      }

      final data = snapshot.data()!;
      if (!data.containsKey("ownedFishes")) return [];

      return (data["ownedFishes"] as List)
          .map((map) => OwnedFish.fromMap(Map<String, dynamic>.from(map)))
          .toList();
    } catch (e) {
      print("❌ Firestore fetchOwnedFishes failed: $e");
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
        print("⚠️ Firestore: child doc missing for balance fetch");
        return 0;
      }
      final data = snapshot.data();
      return data?["balance"] ?? 0;
    } catch (e) {
      print("❌ Firestore fetchBalance failed: $e");
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
      print("✅ Firestore: balance updated to $balance");
    } catch (e) {
      print("❌ Firestore updateBalance failed: $e");
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
      print("✅ Firestore: fish $fishId removed");
    } catch (e) {
      print("❌ Firestore removeOwnedFish failed: $e");
      rethrow;
    }
  }
}
