import 'package:hive/hive.dart';
import '../models/ownedFish_model.dart';
import '../services/fish_service.dart';
import '/data/models/child_model.dart';

class FishRepository {
  final FishService _service = FishService();
  final Box<ChildUser> _childBox = Hive.box<ChildUser>('childBox');

  Future<List<OwnedFish>> getOwnedFishes(String parentUid, String childId) async {
    final child = _childBox.get(childId);
    if (child == null) return [];

    // Hive local storage
    List<OwnedFish> hiveFishes =
        child.ownedFish.map((e) => OwnedFish.fromMap(e)).toList();

    // Fetch from Firestore
    final firestoreFishes = await _service.fetchOwnedFishes(parentUid, childId);
    if (firestoreFishes.isNotEmpty) {
      hiveFishes = firestoreFishes;
      child.ownedFish = hiveFishes.map((f) => f.toMap()).toList();
      await _childBox.put(childId, child);
    }

    return hiveFishes;
  }

  Future<void> addOwnedFish(String parentUid, String childId, OwnedFish fish) async {
    final child = _childBox.get(childId);
    if (child == null) return;

    child.ownedFish.add(fish.toMap());
    await _childBox.put(childId, child);
    await _service.syncOwnedFishes(
        parentUid, childId, child.ownedFish.map((e) => OwnedFish.fromMap(e)).toList());
  }

  Future<void> updateOwnedFish(String parentUid, String childId, OwnedFish fish) async {
    final child = _childBox.get(childId);
    if (child == null) return;

    final idx = child.ownedFish.indexWhere((f) => f['fishId'] == fish.fishId);;
    if (idx != -1) {
      child.ownedFish[idx] = fish.toMap();
    } else {
      child.ownedFish.add(fish.toMap());
    }

    await _childBox.put(childId, child);

    await _service.syncOwnedFishes(
        parentUid, childId, child.ownedFish.map((e) => OwnedFish.fromMap(e)).toList());
  }

  Future<void> storeFish(String parentUid, String childId, String fishId) async {
    final child = _childBox.get(childId);
    if (child == null) return;

    final idx = child.ownedFish.indexWhere((f) => f['fishId'] == fishId);;
    if (idx != -1) {
      final fish = OwnedFish.fromMap(child.ownedFish[idx]);
      final updated = fish.copyWith(isActive: false);
      child.ownedFish[idx] = updated.toMap();
      await _childBox.put(childId, child);

      await _service.syncOwnedFishes(
          parentUid, childId, child.ownedFish.map((f) => OwnedFish.fromMap(f)).toList());
    }
  }

  Future<void> sellFish(String parentUid, String childId, String fishId, int price) async {
    final child = _childBox.get(childId);
    if (child == null) return;

    child.ownedFish.removeWhere((f) => f['fishId'] == fishId);;
    await _childBox.put(childId, child);

    await _service.syncOwnedFishes(
        parentUid, childId, child.ownedFish.map((f) => OwnedFish.fromMap(f)).toList());

    // Refund balance
    await _updateBalance(parentUid, child, child.balance + price);
  }

  Future<void> _updateBalance(String parentUid, ChildUser child, int newBalance) async {
    final updatedChild = child.copyWith(balance: newBalance);
    await _childBox.put(child.cid, updatedChild);
    await _service.updateBalance(parentUid, child.cid, newBalance);
  }

  Future<void> refundBalance(
      String parentUid, String childId, int amount) async {
    final child = _childBox.get(childId);
    if (child == null) return;
    await _updateBalance(parentUid, child, child.balance + amount);
  }

  Future<void> deductBalance(
      String parentUid, String childId, int amount) async {
    final child = _childBox.get(childId);
    if (child == null) return;
    await _updateBalance(parentUid, child, child.balance - amount);
  }

  Future<int> fetchBalance(String parentUid, String childId) async {
    final child = _childBox.get(childId);
    if (child == null) return 0;
    return child.balance;
  }
}
