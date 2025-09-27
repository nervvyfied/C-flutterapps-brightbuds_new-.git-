import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/placedDecor_model.dart';

class DecorService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // ---------- Sync placed decors ----------
  Future<void> syncPlacedDecors(
      String parentUid, String childId, List<PlacedDecor> decors) async {
    final docRef = _db
        .collection("users")
        .doc(parentUid)
        .collection("children")
        .doc(childId)
        .collection("aquarium")
        .doc("decor");

    await docRef.set({
      "placedDecors": decors.map((d) => d.toMap()).toList(),
    }, SetOptions(merge: true));
  }

  // ---------- Fetch placed decors ----------
  Future<List<PlacedDecor>> fetchPlacedDecors(
      String parentUid, String childId) async {
    final docRef = _db
        .collection("users")
        .doc(parentUid)
        .collection("children")
        .doc(childId)
        .collection("aquarium")
        .doc("decor");

    final snapshot = await docRef.get();
    if (!snapshot.exists || snapshot.data() == null) return [];

    final data = snapshot.data()!;
    if (!data.containsKey("placedDecors")) return [];

    return (data["placedDecors"] as List)
        .map((map) => PlacedDecor.fromMap(Map<String, dynamic>.from(map)))
        .toList();
  }

  // ---------- Fetch & update balance ----------
  Future<int> fetchBalance(String parentUid, String childId) async {
    final childRef = _db
        .collection("users")
        .doc(parentUid)
        .collection("children")
        .doc(childId);

    final snapshot = await childRef.get();
    if (!snapshot.exists) return 0;
    return snapshot.data()?["balance"] ?? 0;
  }

  Future<void> updateBalance(
      String parentUid, String childId, int balance) async {
    final childRef = _db
        .collection("users")
        .doc(parentUid)
        .collection("children")
        .doc(childId);

    await childRef.update({"balance": balance});
  }
}
