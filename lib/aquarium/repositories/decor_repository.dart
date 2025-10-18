import 'package:brightbuds_new/aquarium/services/decor_service.dart';
import '/data/models/child_model.dart';
import '../models/placedDecor_model.dart';
import 'package:hive/hive.dart';

class DecorRepository {
  final DecorService _service = DecorService();
  final Box<ChildUser> _childBox = Hive.box<ChildUser>('childBox');

  // ---------- Sync / Push ----------
  Future<void> pushPlacedDecorChanges(
      String parentId, String childId, List<PlacedDecor> placedDecors) async {
    // Simply call syncPlacedDecors to Firestore
    await _service.syncPlacedDecors(parentId, childId, placedDecors);

    // Update local cache after syncing
    final child = _childBox.get(childId);
    if (child != null) {
      child.placedDecors = placedDecors.map((d) => d.toMap()).toList();
      await _childBox.put(childId, child);
    }
  }

  // ---------- Get Placed Decors ----------
  Future<List<PlacedDecor>> getPlacedDecors(
      String parentUid, String childId) async {
    final child = _childBox.get(childId);
    if (child == null) return [];

    // Load from local first
    List<PlacedDecor> hiveDecors =
        child.placedDecors.map((e) => PlacedDecor.fromMap(e)).toList();

    // Then merge with Firestore
    final firestoreDecors =
        await _service.fetchPlacedDecors(parentUid, childId);

    if (firestoreDecors.isNotEmpty) {
      hiveDecors = firestoreDecors;
      child.placedDecors = hiveDecors.map((d) => d.toMap()).toList();
      await _childBox.put(childId, child);
    }

    return hiveDecors;
  }

  // ---------- Update All ----------
  Future<void> updatePlacedDecors(
      String parentId, String childId, List<PlacedDecor> placedDecors) async {
    final child = _childBox.get(childId);
    if (child != null) {
      child.placedDecors = placedDecors.map((d) => d.toMap()).toList();
      await _childBox.put(childId, child);
    }

    await _service.syncPlacedDecors(parentId, childId, placedDecors);
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

  // ---------- Update One ----------
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

  // ---------- Store (mark as not placed) ----------
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

  // ---------- Sell (remove + refund) ----------
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

    await _updateBalance(parentUid, child, child.balance + price);
  }

  // ---------- Remove Permanently ----------
  Future<void> removePlacedDecor(
      String parentUid, String childId, String decorId) async {
    final child = _childBox.get(childId);
    if (child == null) return;

    child.placedDecors.removeWhere((d) => d['id'] == decorId);
    await _childBox.put(childId, child);

    await _service.syncPlacedDecors(
      parentUid,
      childId,
      child.placedDecors.map((e) => PlacedDecor.fromMap(e)).toList(),
    );
  }

  // ---------- Balance ----------
  Future<void> updateBalance(
      String parentUid, String childId, int newBalance) async {
    final child = _childBox.get(childId);
    if (child == null) return;
    final updatedChild = child.copyWith(balance: newBalance);
    await _childBox.put(childId, updatedChild);
    await _service.updateBalance(parentUid, childId, newBalance);
  }

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
