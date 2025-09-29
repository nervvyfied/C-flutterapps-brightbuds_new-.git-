import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/ownedFish_model.dart';

class FishService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  Future<void> syncOwnedFishes(String parentUid, String childId, List<OwnedFish> fishes) async {
    final docRef = _db
        .collection("users")
        .doc(parentUid)
        .collection("children")
        .doc(childId)
        .collection("aquarium")
        .doc("fishes");

    await docRef.set({
      "ownedFishes": fishes.map((f) => f.toMap()).toList(),
    }, SetOptions(merge: true));
  }

  Future<List<OwnedFish>> fetchOwnedFishes(String parentUid, String childId) async {
    final docRef = _db
        .collection("users")
        .doc(parentUid)
        .collection("children")
        .doc(childId)
        .collection("aquarium")
        .doc("fishes");

    final snapshot = await docRef.get();
    if (!snapshot.exists || snapshot.data() == null) return [];

    final data = snapshot.data()!;
    if (!data.containsKey("ownedFishes")) return [];

    return (data["ownedFishes"] as List)
        .map((map) => OwnedFish.fromMap(Map<String, dynamic>.from(map)))
        .toList();
  }

  Future<int> fetchBalance(String parentUid, String childId) async {
    final childRef = _db.collection("users").doc(parentUid).collection("children").doc(childId);
    final snapshot = await childRef.get();
    if (!snapshot.exists) return 0;
    return snapshot.data()?["balance"] ?? 0;
  }

  Future<void> updateBalance(String parentUid, String childId, int balance) async {
    final childRef = _db.collection("users").doc(parentUid).collection("children").doc(childId);
    await childRef.update({"balance": balance});
  }
}
