import 'package:hive/hive.dart';
import '../models/ownedFish_model.dart';
import '../services/fish_service.dart';
import '/data/models/child_model.dart';

class FishRepository {
  final FishService _service = FishService();
  static Box<ChildUser>? _childBox;

  // 🧩 Safer one-time Hive initialization
  Future<void> _ensureBox() async {
    if (_childBox == null || !_childBox!.isOpen) {
      _childBox = await Hive.openBox<ChildUser>('childBox');
      print("📦 Hive childBox opened.");
    }
  }

  // 🐟 Get all fishes (merged local + remote)
  Future<List<OwnedFish>> getOwnedFishes(
    String parentUid,
    String childId,
  ) async {
    await _ensureBox();
    final child = _childBox!.get(childId);
    if (child == null) return [];

    final localFishes = child.ownedFish
        .map((e) => OwnedFish.fromMap(e))
        .toList();

    try {
      final remoteFishes = await _service.fetchOwnedFishes(parentUid, childId);

      // Merge without duplication
      final mergedMap = {for (var f in localFishes) f.id: f};
      for (var f in remoteFishes) {
        mergedMap[f.id] = f;
      }

      final mergedList = mergedMap.values.toList();
      child.ownedFish = mergedList.map((f) => f.toMap()).toList();
      await _childBox!.put(childId, child);

      return mergedList;
    } catch (e) {
      print("⚠️ Using local fishes (offline mode): $e");
      return localFishes;
    }
  }

  // 🐟 Add owned fish (now truly offline-first)
  Future<void> addOwnedFish(
    String parentUid,
    String childId,
    OwnedFish fish,
  ) async {
    await _ensureBox();
    final child = _childBox!.get(childId);
    if (child == null) return;

    // ✅ Always update local Hive first
    if (!child.ownedFish.any((f) => f['id'] == fish.id)) {
      child.ownedFish.add(fish.toMap());
      await _childBox!.put(childId, child);
      print("🐟 [Offline] Added ${fish.id} locally to Hive.");
    }

    // ☁️ Try syncing with Firestore
    try {
      await _service.syncOwnedFishes(
        parentUid,
        childId,
        child.ownedFish.map((e) => OwnedFish.fromMap(e)).toList(),
      );
      print("☁️ Synced owned fishes to Firestore.");
    } catch (e) {
      print(
        "⚠️ Offline - Firestore sync failed, keeping local copy. Error: $e",
      );
    }
  }

  // 🐟 Update owned fish (used when changing properties)
  Future<void> updateOwnedFish(
    String parentUid,
    String childId,
    OwnedFish fish,
  ) async {
    await _ensureBox();
    final child = _childBox!.get(childId);
    if (child == null) return;

    final idx = child.ownedFish.indexWhere((f) => f['id'] == fish.id);
    if (idx != -1) {
      child.ownedFish[idx] = fish.toMap();
    } else {
      child.ownedFish.add(fish.toMap());
    }

    await _childBox!.put(childId, child);
    print("🐠 Updated ${fish.id} locally.");

    try {
      await _service.syncOwnedFishes(
        parentUid,
        childId,
        child.ownedFish.map((e) => OwnedFish.fromMap(e)).toList(),
      );
      print("☁️ Synced updated fish to Firestore.");
    } catch (e) {
      print("⚠️ Offline - unable to sync fish update. Error: $e");
    }
  }

  // 🐟 Remove fish (for selling)
  Future<void> removeOwnedFish(
    String parentUid,
    String childId,
    String fishId,
  ) async {
    await _ensureBox();
    final child = _childBox!.get(childId);
    if (child == null) return;

    child.ownedFish.removeWhere((f) => f['id'] == fishId);
    await _childBox!.put(childId, child);
    print("🧹 Removed fish $fishId locally.");

    try {
      await _service.removeOwnedFish(parentUid, childId, fishId);
      print("☁️ Synced fish removal to Firestore.");
    } catch (e) {
      print("⚠️ Offline - unable to sync fish removal. Error: $e");
    }
  }

  // 🐟 Store fish (make inactive)
  Future<void> storeFish(
    String parentUid,
    String childId,
    String fishId,
  ) async {
    await _ensureBox();
    final child = _childBox!.get(childId);
    if (child == null) return;

    final idx = child.ownedFish.indexWhere((f) => f['fishId'] == fishId);
    if (idx == -1) return;

    final fish = OwnedFish.fromMap(child.ownedFish[idx]);
    child.ownedFish[idx] = fish.copyWith(isActive: false).toMap();
    await _childBox!.put(childId, child);
    print("🐡 Stored fish $fishId locally (inactive).");

    try {
      await _service.syncOwnedFishes(
        parentUid,
        childId,
        child.ownedFish.map((f) => OwnedFish.fromMap(f)).toList(),
      );
      print("☁️ Synced store action to Firestore.");
    } catch (e) {
      print("⚠️ Offline - failed to sync store action. Error: $e");
    }
  }

  // 💰 Balance update (used by purchase/sell)
  Future<void> updateBalance(
    String parentUid,
    String childId,
    int newBalance,
  ) async {
    await _ensureBox();
    final child = _childBox!.get(childId);
    if (child == null) return;
    if (child.balance == newBalance) return;

    final updatedChild = child.copyWith(balance: newBalance);
    await _childBox!.put(childId, updatedChild);
    print("💰 Updated balance locally: $newBalance");

    try {
      await _service.updateBalance(parentUid, childId, newBalance);
      print("☁️ Synced balance to Firestore.");
    } catch (e) {
      print("⚠️ Offline - balance sync deferred. Error: $e");
    }
  }

  Future<void> refundBalance(
    String parentUid,
    String childId,
    int amount,
  ) async {
    await _ensureBox();
    final child = _childBox!.get(childId);
    if (child == null) return;

    final newBalance = child.balance + amount;
    await updateBalance(parentUid, childId, newBalance);
  }

  Future<void> deductBalance(
    String parentUid,
    String childId,
    int amount,
  ) async {
    await _ensureBox();
    final child = _childBox!.get(childId);
    if (child == null) return;

    final newBalance = child.balance - amount;
    await updateBalance(parentUid, childId, newBalance);
  }

  Future<int> fetchBalance(String parentUid, String childId) async {
    await _ensureBox();
    final child = _childBox!.get(childId);
    if (child != null && child.balance > 0) return child.balance;

    final remoteBalance = await _service.fetchBalance(parentUid, childId);
    if (child != null) {
      final updated = child.copyWith(balance: remoteBalance);
      await _childBox!.put(childId, updated);
    }
    return remoteBalance;
  }
}
