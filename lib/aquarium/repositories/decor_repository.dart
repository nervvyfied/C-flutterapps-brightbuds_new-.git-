import 'package:brightbuds_new/aquarium/services/decor_service.dart';
import '/data/models/child_model.dart';
import '../models/placedDecor_model.dart';
import 'package:hive/hive.dart';

class DecorRepository {
  final DecorService _service = DecorService();
  final Box<ChildUser> _childBox = Hive.box<ChildUser>('childBox');

  // ---------- Get placed/stored decors ----------
  Future<void> syncPlacedDecors(
      String parentId,
      String childId,
      List<PlacedDecor> placedDecors,
    ) async {
      await _service.syncPlacedDecors(parentId, childId, placedDecors);
  }

  Future<void> updatePlacedDecors(
    String parentId,
    String childId,
    List<PlacedDecor> placedDecors,
  ) async {
    await _service.updatePlacedDecors(parentId, childId, placedDecors);
  }

  Future<List<PlacedDecor>> getPlacedDecors(
      String parentUid, String childId) async {
    final child = _childBox.get(childId);
    if (child == null) return [];

    // Load Hive first
    List<PlacedDecor> hiveDecors =
        child.placedDecors.map((e) => PlacedDecor.fromMap(e)).toList();

    // Merge with Firestore
    final firestoreDecors = await _service.fetchPlacedDecors(parentUid, childId);
    if (firestoreDecors.isNotEmpty) {
      hiveDecors = firestoreDecors;
      child.placedDecors = hiveDecors.map((d) => d.toMap()).toList();
      await _childBox.put(childId, child);
    }

    return hiveDecors;
  }

  // ---------- Add ----------
  Future<void> addPlacedDecor(
      String parentUid, String childId, PlacedDecor decor) async {
    final child = _childBox.get(childId);
    if (child == null) return;

    child.placedDecors.add(decor.toMap());
    await _childBox.put(childId, child);

    await _service.syncPlacedDecors(
      parentUid,
      childId,
      child.placedDecors.map((e) => PlacedDecor.fromMap(e)).toList(),
    );
  }

  // ---------- Update (works for both placed + stored) ----------
  Future<void> updatePlacedDecor(
      String parentUid, String childId, PlacedDecor decor) async {
    final child = _childBox.get(childId);
    if (child == null) return;

    final idx = child.placedDecors.indexWhere((d) => d['id'] == decor.id);
    if (idx != -1) {
      child.placedDecors[idx] = decor.toMap();
    } else {
      child.placedDecors.add(decor.toMap());
    }

    await _childBox.put(childId, child);

    await _service.syncPlacedDecors(
      parentUid,
      childId,
      child.placedDecors.map((e) => PlacedDecor.fromMap(e)).toList(),
    );
  }

  // ---------- Store (mark isPlaced = false but keep ownership) ----------
  Future<void> storeDecor(
      String parentUid, String childId, String decorId) async {
    final child = _childBox.get(childId);
    if (child == null) return;

    final idx = child.placedDecors.indexWhere((d) => d['id'] == decorId);
    if (idx != -1) {
      final decor = PlacedDecor.fromMap(child.placedDecors[idx]);
      final updated = decor.copyWith(isPlaced: false);
      child.placedDecors[idx] = updated.toMap();

      await _childBox.put(childId, child);
      await _service.syncPlacedDecors(
        parentUid,
        childId,
        child.placedDecors.map((e) => PlacedDecor.fromMap(e)).toList(),
      );
    }
  }

  // ---------- Sell (remove completely) ----------
  Future<void> sellDecor(
      String parentUid, String childId, String decorId, int price) async {
    final child = _childBox.get(childId);
    if (child == null) return;

    child.placedDecors.removeWhere((d) => d['id'] == decorId);
    await _childBox.put(childId, child);

    await _service.syncPlacedDecors(
      parentUid,
      childId,
      child.placedDecors.map((e) => PlacedDecor.fromMap(e)).toList(),
    );

    // Refund balance for selling
    await _updateBalance(parentUid, child, child.balance + price);
  }

  Future<void> removePlacedDecor(
      String parentUid, String childId, String decorId) async {
    final child = _childBox.get(childId);
    if (child == null) return;

    child.placedDecors.removeWhere((d) => d['id'] == decorId);
    await _childBox.put(childId, child);

    await _service.syncPlacedDecors(
        parentUid, childId, child.placedDecors.map((e) => PlacedDecor.fromMap(e)).toList());
  }

  // ---------- Balance ----------
  Future<void> deductBalance(
      String parentUid, String childId, int amount) async {
    final child = _childBox.get(childId);
    if (child == null) return;
    await _updateBalance(parentUid, child, child.balance - amount);
  }

  Future<void> refundBalance(
      String parentUid, String childId, int amount) async {
    final child = _childBox.get(childId);
    if (child == null) return;
    await _updateBalance(parentUid, child, child.balance + amount);
  }

  Future<void> _updateBalance(
      String parentUid, ChildUser child, int newBalance) async {
    final updatedChild = child.copyWith(balance: newBalance);
    await _childBox.put(child.cid, updatedChild);
    await _service.updateBalance(parentUid, child.cid, newBalance);
  }

  Future<int> fetchBalance(String parentUid, String childId) async {
    final child = _childBox.get(childId);
    if (child == null) return 0;
    return child.balance;
  }
}
