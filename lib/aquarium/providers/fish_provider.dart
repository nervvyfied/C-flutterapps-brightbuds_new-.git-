import 'dart:collection';
import 'package:brightbuds_new/notifications/fcm_service.dart';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/fish_definition.dart';
import '../models/ownedFish_model.dart';
import '../repositories/fish_repository.dart';
import '../catalogs/fish_catalog.dart';
import '/data/models/child_model.dart';
import '../../data/providers/auth_provider.dart';

class FishProvider extends ChangeNotifier {
  final AuthProvider authProvider;
  final FishRepository _repo = FishRepository();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  late ChildUser currentChild;
  late Box<ChildUser> _childBox;

  List<OwnedFish> ownedFishes = [];
  List<OwnedFish> _editingBuffer = [];
  bool isInEditMode = false;
  String? movingFishId;

  Function(int newBalance)? onBalanceChanged;

  FishProvider({required this.authProvider}) {
    _childBox = Hive.box<ChildUser>('childBox');

    if (authProvider.currentUserModel is ChildUser) {
      currentChild = authProvider.currentUserModel;

      // Restore local session first
      _restoreFromHive();

      // Then try fetching remote (optional)
      _init();

      // Hive listener: update balance only
      _childBox.watch(key: currentChild.cid).listen((event) {
        final updatedChild = _childBox.get(currentChild.cid);
        if (updatedChild != null &&
            updatedChild.balance != currentChild.balance) {
          currentChild = currentChild.copyWith(balance: updatedChild.balance);
          notifyListeners();
          if (kDebugMode) {
            print("🔄 Hive sync: balance updated to ${currentChild.balance}");
          }
        }
      });
    }
  }

  // ---------- Restore from Hive ----------
  void _restoreFromHive() {
    final child = _childBox.get(currentChild.cid);
    if (child != null) {
      // Restore balance
      currentChild = currentChild.copyWith(balance: child.balance);

      // Restore owned fishes
      ownedFishes = child.ownedFish
          .map((map) => OwnedFish.fromMap(Map<String, dynamic>.from(map)))
          .toList();

      if (kDebugMode) {
        print("📦 Restored ${ownedFishes.length} fishes from Hive for ${currentChild.cid}");
      }
      notifyListeners();
    }
  }

  // ---------- Initialization (remote sync) ----------
  Future<void> _init() async {
    try {
      final remoteFishes =
          await _repo.getOwnedFishes(currentChild.parentUid, currentChild.cid);

      // Merge remote with local (avoid duplicates)
      final localIds = ownedFishes.map((f) => f.id).toSet();
      for (var fish in remoteFishes) {
        if (!localIds.contains(fish.id)) {
          ownedFishes.add(fish);
        }
      }

      notifyListeners();
    } catch (_) {
      // Fail silently, rely on local
    }
  }

  Future<void> setChild(ChildUser child) async {
    currentChild = child;
    ownedFishes.clear();
    _editingBuffer.clear();
    isInEditMode = false;
    movingFishId = null;

    _restoreFromHive();
    await _init();
  }

  // ---------- Balance ----------
  void _updateLocalBalance(int newBalance) {
    if (currentChild.balance == newBalance) return;

    currentChild = currentChild.copyWith(balance: newBalance);

    final child = _childBox.get(currentChild.cid);
    if (child != null) {
      final updatedChild = child.copyWith(balance: newBalance);
      _childBox.put(currentChild.cid, updatedChild);
    }

    notifyListeners();
    onBalanceChanged?.call(newBalance);

    // Try remote sync silently
    try {
      _repo.updateBalance(currentChild.parentUid, currentChild.cid, newBalance);
    } catch (_) {}
  }

  Future<int> fetchBalance() async {
    try {
      return await _repo.fetchBalance(currentChild.parentUid, currentChild.cid);
    } catch (_) {
      return currentChild.balance;
    }
  }

  // ---------- Inventory ----------
  UnmodifiableListView<OwnedFish> get inventory =>
      UnmodifiableListView(ownedFishes.where((f) => !f.isActive));

  UnmodifiableListView<OwnedFish> get activeFishes =>
      UnmodifiableListView(ownedFishes.where((f) => f.isActive));

  bool isOwned(String fishId) => ownedFishes.any((f) => f.fishId == fishId);

  bool canPurchase(FishDefinition fish) =>
      fish.type == FishType.purchasable &&
      currentChild.balance >= fish.price;

  FishDefinition getFishDefinition(String fishId) =>
      FishCatalog.byId(fishId);

  // ---------- Purchase ----------
  Future<bool> purchaseFish(FishDefinition fish) async {
    if (!canPurchase(fish)) return false;
    if (ownedFishes.where((f) => f.fishId == fish.id).length >= 15) return false;

    final newFish = OwnedFish(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      fishId: fish.id,
      isActive: false,
      isNeglected: false,
      isPurchased: true,
      isUnlocked: fish.type != FishType.unlockable,
    );

    final newBalance = currentChild.balance - fish.price;

    _updateLocalBalance(newBalance);

    ownedFishes.add(newFish);

    // Persist to Hive
    final child = _childBox.get(currentChild.cid);
    if (child != null) {
      child.ownedFish.add(newFish.toMap());
      await _childBox.put(currentChild.cid, child);
    }

    notifyListeners();

    // Remote sync
    try {
      await _repo.addOwnedFish(currentChild.parentUid, currentChild.cid, newFish);
    } catch (_) {}

    if (kDebugMode) {
      print("🟢 Purchased fish ${fish.name} (offline-ready, balance $newBalance)");
    }

    return true;
  }

  // ---------- Activate / Store ----------
  Future<void> activateFish(String fishId) async =>
      _updateFishState(fishId, isActive: true);

  Future<void> storeFish(String fishId) async =>
      _updateFishState(fishId, isActive: false);

  Future<void> _updateFishState(String fishId, {required bool isActive}) async {
    final idx = ownedFishes.indexWhere((f) => f.fishId == fishId);
    if (idx == -1) return;

    ownedFishes[idx] = ownedFishes[idx].copyWith(isActive: isActive);

    final child = _childBox.get(currentChild.cid);
    if (child != null) {
      final updatedFishes = ownedFishes.map((f) => f.toMap()).toList();
      final updatedChild = child.copyWith(ownedFish: updatedFishes);
      await _childBox.put(currentChild.cid, updatedChild);
    }

    notifyListeners();

    try {
      await _repo.updateOwnedFish(currentChild.parentUid, currentChild.cid, ownedFishes[idx]);
    } catch (_) {}

    if (kDebugMode) print("🟢 Fish ${fishId} state updated: isActive=$isActive (offline-ready)");
  }

  // ---------- Sell ----------
  Future<void> sellFish(String fishId) async {
    final idx = ownedFishes.indexWhere((f) => f.fishId == fishId);
    if (idx == -1) return;

    final fishDef = FishCatalog.byId(fishId);
    final price = fishDef.type == FishType.purchasable ? fishDef.price : 0;

    final soldFish = ownedFishes.removeAt(idx);

    if (price > 0) _updateLocalBalance(currentChild.balance + price);

    final child = _childBox.get(currentChild.cid);
    if (child != null) {
      child.ownedFish.removeWhere((f) => f['id'] == soldFish.id);
      await _childBox.put(currentChild.cid, child);
    }

    try {
      await _repo.removeOwnedFish(currentChild.parentUid, currentChild.cid, soldFish.id);
    } catch (_) {}

    notifyListeners();

    if (kDebugMode) {
      print("🟢 Sold fish ${soldFish.fishId} for $price tokens. New balance: ${currentChild.balance}");
    }
  }

  // ---------- Unlock ----------
  Future<void> unlockFish(String fishId) async {
    if (ownedFishes.any((f) => f.id == fishId)) return;

    final newFish = OwnedFish(id: fishId, fishId: fishId, isUnlocked: true, isActive: false);
    ownedFishes.add(newFish);

    final child = _childBox.get(currentChild.cid);
    if (child != null) {
      child.ownedFish.add(newFish.toMap());
      await _childBox.put(currentChild.cid, child);
    }

    try {
      await _repo.updateOwnedFish(currentChild.parentUid, currentChild.cid, newFish);
    } catch (_) {}

    notifyListeners();
  }

  // ---------- Neglected ----------
  Future<void> setNeglected(String fishId, bool neglected) async {
  final idx = ownedFishes.indexWhere((f) => f.fishId == fishId);
  if (idx == -1) return;

  // Update local fish state
  ownedFishes[idx] = ownedFishes[idx].copyWith(isNeglected: neglected);

  final child = _childBox.get(currentChild.cid);
  if (child != null) {
    final updatedFishes = ownedFishes.map((f) => f.toMap()).toList();
    final updatedChild = child.copyWith(ownedFish: updatedFishes);
    await _childBox.put(currentChild.cid, updatedChild);
  }

  // Update Firestore
  try {
    await _repo.updateOwnedFish(currentChild.parentUid, currentChild.cid, ownedFishes[idx]);
  } catch (_) {}

  // ✅ Fetch child token and send notification
  final childSnapshot = await FirebaseFirestore.instance
      .collection('users')
      .doc(currentChild.parentUid)
      .collection('children')
      .doc(currentChild.cid)
      .get();

  final childToken = childSnapshot.data()?['fcmToken'];
  if (childToken != null && neglected) { // Only notify if fish is neglected
    await FCMService.sendNotification(
      title: '🐟 Your Fish Needs Attention!',
      body: 'You haven’t checked your aquarium lately!',
      token: childToken,
      data: {'type': 'fish_neglected'},
    );
  }

  notifyListeners();
}


  // ---------- Edit Mode ----------
  UnmodifiableListView<OwnedFish> get editingFishes =>
      UnmodifiableListView(_editingBuffer);

  void enterEditMode({String? focusFishId}) {
    _editingBuffer = ownedFishes.map((f) => f.copyWith()).toList();
    for (var f in _editingBuffer) f.isSelected = false;

    if (focusFishId != null) {
      final idx = _editingBuffer.indexWhere((f) => f.id == focusFishId);
      if (idx != -1) _editingBuffer[idx].isSelected = true;
    }

    isInEditMode = true;
    movingFishId = null;
    notifyListeners();
  }

  void cancelEditMode() {
    _editingBuffer.clear();
    isInEditMode = false;
    movingFishId = null;
    notifyListeners();
  }

  Future<void> saveEditMode() async {
    if (!isInEditMode) return;

    for (var fish in _editingBuffer) {
      try {
        await _repo.updateOwnedFish(currentChild.parentUid, currentChild.cid, fish);
      } catch (_) {}
    }

    ownedFishes = List.from(_editingBuffer);
    _editingBuffer.clear();
    isInEditMode = false;
    movingFishId = null;
    notifyListeners();

    if (kDebugMode) print("✅ Edit mode saved. ${ownedFishes.length} fishes synced.");
  }

  void toggleFishSelection(String fishId) {
    if (!isInEditMode) enterEditMode(focusFishId: fishId);

    for (var f in _editingBuffer) f.isSelected = false;
    final idx = _editingBuffer.indexWhere((f) => f.id == fishId);
    if (idx != -1) _editingBuffer[idx].isSelected = true;
    notifyListeners();
  }

  void deselectFish(String fishId) {
    final idx = _editingBuffer.indexWhere((f) => f.id == fishId);
    if (idx != -1) {
      _editingBuffer[idx].isSelected = false;
      notifyListeners();
    }
  }

  void startMovingFish(String fishId) {
    if (!isInEditMode) return;
    movingFishId = fishId;
    final idx = _editingBuffer.indexWhere((f) => f.id == fishId);
    if (idx != -1) _editingBuffer[idx].isSelected = true;
    notifyListeners();
  }

  void stopMovingFish() {
    movingFishId = null;
    notifyListeners();
  }

  // ---------- Clear ----------
  void clearData() {
    ownedFishes.clear();
    _editingBuffer.clear();
    isInEditMode = false;
    movingFishId = null;
    notifyListeners();
  }
}
