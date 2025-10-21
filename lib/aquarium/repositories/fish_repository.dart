import 'package:hive/hive.dart';
import '../models/ownedFish_model.dart';
import '../services/fish_service.dart';
import '/data/models/child_model.dart';

class FishRepository {
  final FishService _service = FishService();
  late Box<ChildUser> _childBox;

  FishRepository() {
    _initBox();
  }

  Future<void> _initBox() async {
    _childBox = await Hive.openBox<ChildUser>('childBox');
  }

  Future<List<OwnedFish>> getOwnedFishes(String parentUid, String childId) async {
    final child = _childBox.get(childId);
    if (child == null) return [];

    List<OwnedFish> localFishes = child.ownedFish.map((e) => OwnedFish.fromMap(e)).toList();

    try {
      final remoteFishes = await _service.fetchOwnedFishes(parentUid, childId);

      final mergedMap = {for (var f in localFishes) f.id: f};
      for (var f in remoteFishes) {
        mergedMap[f.id] = f; // overwrite with remote
      }

      final mergedList = mergedMap.values.toList();
      child.ownedFish = mergedList.map((f) => f.toMap()).toList();
      await _childBox.put(childId, child);

      return mergedList;
    } catch (_) {
      return localFishes;
    }
  }

  Future<void> addOwnedFish(String parentUid, String childId, OwnedFish fish) async {
    final child = _childBox.get(childId);
    if (child == null) return;

    if (!child.ownedFish.any((f) => f['id'] == fish.id)) {
      child.ownedFish.add(fish.toMap());
      await _childBox.put(childId, child);
    }

    try {
      await _service.syncOwnedFishes(
        parentUid,
        childId,
        child.ownedFish.map((e) => OwnedFish.fromMap(e)).toList(),
      );
    } catch (_) {}
  }

  Future<void> updateOwnedFish(String parentUid, String childId, OwnedFish fish) async {
    final child = _childBox.get(childId);
    if (child == null) return;

    final idx = child.ownedFish.indexWhere((f) => f['id'] == fish.id);
    if (idx != -1) {
      child.ownedFish[idx] = fish.toMap();
    } else {
      child.ownedFish.add(fish.toMap());
    }

    await _childBox.put(childId, child);

    try {
      await _service.syncOwnedFishes(
        parentUid,
        childId,
        child.ownedFish.map((e) => OwnedFish.fromMap(e)).toList(),
      );
    } catch (_) {}
  }

  Future<void> removeOwnedFish(String parentUid, String childId, String fishId) async {
    final child = _childBox.get(childId);
    if (child == null) return;

    child.ownedFish.removeWhere((f) => f['id'] == fishId);
    await _childBox.put(childId, child);

    try {
      await _service.syncOwnedFishes(
        parentUid,
        childId,
        child.ownedFish.map((f) => OwnedFish.fromMap(f)).toList(),
      );
    } catch (_) {}
  }

  Future<void> storeFish(String parentUid, String childId, String fishId) async {
    final child = _childBox.get(childId);
    if (child == null) return;

    final idx = child.ownedFish.indexWhere((f) => f['fishId'] == fishId);
    if (idx == -1) return;

    final fish = OwnedFish.fromMap(child.ownedFish[idx]);
    child.ownedFish[idx] = fish.copyWith(isActive: false).toMap();
    await _childBox.put(childId, child);

    try {
      await _service.syncOwnedFishes(
        parentUid,
        childId,
        child.ownedFish.map((f) => OwnedFish.fromMap(f)).toList(),
      );
    } catch (_) {}
  }

  /// Public balance updates for provider
  Future<void> updateBalance(String parentUid, String childId, int newBalance) async {
    final child = _childBox.get(childId);
    if (child == null) return;
    if (child.balance == newBalance) return;

    final updatedChild = child.copyWith(balance: newBalance);
    await _childBox.put(childId, updatedChild);

    try {
      await _service.updateBalance(parentUid, childId, newBalance);
    } catch (_) {}
  }

  Future<void> refundBalance(String parentUid, String childId, int amount) async {
    final child = _childBox.get(childId);
    if (child == null) return;
    await updateBalance(parentUid, childId, child.balance + amount);
  }

  Future<void> deductBalance(String parentUid, String childId, int amount) async {
    final child = _childBox.get(childId);
    if (child == null) return;
    await updateBalance(parentUid, childId, child.balance - amount);
  }

  Future<int> fetchBalance(String parentUid, String childId) async {
    final child = _childBox.get(childId);
    if (child == null) return 0;
    return child.balance;
  }
}
