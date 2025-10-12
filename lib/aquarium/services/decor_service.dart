import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:hive_flutter/hive_flutter.dart';
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

  Future<void> updatePlacedDecors(
  String parentId,
  String childId,
  List<PlacedDecor> placedDecors,
) async {
  final box = await Hive.openBox<PlacedDecor>('placedDecors_$childId');

  // update local hive
  await box.clear();
  await box.addAll(placedDecors);

  // sync firestore
  final firestore = FirebaseFirestore.instance;
  final decorMaps = placedDecors.map((d) => d.toMap()).toList();

  await firestore
      .collection('users')
      .doc(parentId)
      .collection('children')
      .doc(childId)
      .collection('aquarium')
      .doc('placedDecors')
      .set({'items': decorMaps});
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
