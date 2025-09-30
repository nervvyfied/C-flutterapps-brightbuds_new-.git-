import 'dart:collection';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../models/fish_definition.dart';
import '../models/ownedFish_model.dart';
import '../repositories/fish_repository.dart';
import '../catalogs/fish_catalog.dart';
import '/data/models/child_model.dart';
import '/providers/auth_provider.dart';

class FishProvider extends ChangeNotifier {
  final AuthProvider authProvider;
  final FishRepository _repo = FishRepository();

  late ChildUser currentChild;

  final FirebaseFirestore firestore = FirebaseFirestore.instance;

  List<OwnedFish> ownedFishes = [];
  List<OwnedFish> _editingBuffer = [];
  bool isInEditMode = false;
  String? movingFishId;

  FishProvider({required this.authProvider}) {
    if (authProvider.currentUserModel is ChildUser) {
      currentChild = authProvider.currentUserModel;
      _init();
    }
  }

  Future<void> _init() async {
    ownedFishes = await _repo.getOwnedFishes(currentChild.parentUid, currentChild.cid);
    notifyListeners();
  }

  bool isUnlocked(String fishId) {
  return ownedFishes.any((f) => f.fishId == fishId);
}


void selectFish(String fishId) {
  if (!isInEditMode) return;

  // Find the fish by definition ID
  final idx = _editingBuffer.indexWhere((f) => f.fishId == fishId);
  if (idx == -1) return;

  // Deselect all first
  for (var f in _editingBuffer) {
    f.isSelected = false;
  }

  // Toggle selection
  _editingBuffer[idx].isSelected = !_editingBuffer[idx].isSelected;

  notifyListeners();
}

/// Check selection state
bool isFishSelected(String fishId) {
  if (!isInEditMode) return false;
  return _editingBuffer.any((f) => f.fishId == fishId && f.isSelected);
}

  // ---------- Balance ----------
  void _updateLocalBalance(int newBalance) {
    currentChild = currentChild.copyWith(balance: newBalance);
    notifyListeners();
  }

  Future<int> fetchBalance() async {
    return _repo.fetchBalance(currentChild.parentUid, currentChild.cid);
  }

  // ---------- Inventory ----------
  UnmodifiableListView<OwnedFish> get inventory =>
      UnmodifiableListView(ownedFishes.where((f) => !f.isActive));

  UnmodifiableListView<OwnedFish> get activeFishes =>
      UnmodifiableListView(ownedFishes.where((f) => f.isActive));

  bool isOwned(String fishId) =>
      ownedFishes.any((f) => f.fishId == fishId);

  bool canPurchase(FishDefinition fish) {
    if (fish.type != FishType.purchasable) return false;
    if (currentChild.balance < fish.price) return false;
    return true;
  }

  // ---------- Purchase ----------
  Future<bool> purchaseFish(FishDefinition fish) async {
    if (!canPurchase(fish)) return false;
    final count = ownedFishes.where((f) => f.fishId == fish.id).length;
    if (count >= 15) return false;

    final newFish = OwnedFish(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      fishId: fish.id,
      isActive: false,
      isNeglected: false,
      isPurchased: true,
      isUnlocked: fish.type == FishType.unlockable ? false : true,
    );

    await _repo.addOwnedFish(currentChild.parentUid, currentChild.cid, newFish);
    ownedFishes.add(newFish);

    await _repo.deductBalance(currentChild.parentUid, currentChild.cid, fish.price);
    _updateLocalBalance(currentChild.balance - fish.price);

    await _refreshBalance();

    notifyListeners();
    if (kDebugMode) print("🟢 Purchased fish ${fish.name}");
    return true;
  }

  // ---------- Edit Mode ----------
  UnmodifiableListView<OwnedFish> get editingFishes =>
      UnmodifiableListView(_editingBuffer);

  void enterEditMode({String? focusFishId}) {
    _editingBuffer = ownedFishes.map((f) => OwnedFish.fromMap(f.toMap())).toList();
    isInEditMode = true;

    // Deselect all first
    for (var f in _editingBuffer) f.isSelected = false;

    if (focusFishId != null) {
      final idx = _editingBuffer.indexWhere((f) => f.id == focusFishId);
      if (idx != -1) _editingBuffer[idx].isSelected = true;
    }

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

    await _repo.updateOwnedFish(currentChild.parentUid, currentChild.cid, _editingBuffer as OwnedFish);

    ownedFishes
      ..clear()
      ..addAll(_editingBuffer);

    _editingBuffer.clear();
    movingFishId = null;
    isInEditMode = false;

    notifyListeners();
    if (kDebugMode) print("✅ Edit mode saved. ${ownedFishes.length} fishes synced.");
  }

  void toggleFishSelection(String fishId) {
    if (!isInEditMode) enterEditMode(focusFishId: fishId);

    // Deselect all first
    for (var f in _editingBuffer) f.isSelected = false;

    // Select this fish
    final idx = _editingBuffer.indexWhere((f) => f.id == fishId);
    if (idx != -1) _editingBuffer[idx].isSelected = true;

    notifyListeners();
  }

  void deselectFish(String fishId) {
    final idx = _editingBuffer.indexWhere((f) => f.id == fishId);
    if (idx == -1) return;

    _editingBuffer[idx].isSelected = false;
    notifyListeners();
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

  // ---------- Store ----------
  Future<void> storeFish(String fishId) async {
  OwnedFish? fish;

  if (isInEditMode) {
    final idx = _editingBuffer.indexWhere((f) => f.fishId == fishId && f.isActive);
    if (idx == -1) return;

    _editingBuffer[idx] = _editingBuffer[idx].copyWith(isActive: false);
    fish = _editingBuffer[idx];
    final mainIdx = ownedFishes.indexWhere((f) => f.id == fish!.id);
    if (mainIdx != -1) ownedFishes[mainIdx] = fish;
  } else {
    final idx = ownedFishes.indexWhere((f) => f.fishId == fishId && f.isActive);
    if (idx == -1) return;

    ownedFishes[idx] = ownedFishes[idx].copyWith(isActive: false);
    fish = ownedFishes[idx];
  }

  await _repo.updateOwnedFish(currentChild.parentUid, currentChild.cid, fish);

  notifyListeners();
}



  // ---------- Activate ----------
  Future<void> activateFish(String fishId) async {
  OwnedFish? fish;

  if (isInEditMode) {
    final idx = _editingBuffer.indexWhere((f) => f.fishId == fishId && !f.isActive);
    if (idx == -1) return;

    _editingBuffer[idx] = _editingBuffer[idx].copyWith(isActive: true);
    fish = _editingBuffer[idx];
    final mainIdx = ownedFishes.indexWhere((f) => f.id == fish!.id);
    if (mainIdx != -1) ownedFishes[mainIdx] = fish;
  } else {
    final idx = ownedFishes.indexWhere((f) => f.fishId == fishId && !f.isActive);
    if (idx == -1) return;

    ownedFishes[idx] = ownedFishes[idx].copyWith(isActive: true);
    fish = ownedFishes[idx];
  }

  await _repo.updateOwnedFish(currentChild.parentUid, currentChild.cid, fish);

  notifyListeners();
  if (kDebugMode) print("🟢 Activated fish $fishId in aquarium");
}


  // ---------- Sell ----------
  Future<void> sellFish(String fishId) async {
  // Find the fish in the main ownedFishes list
  final idx = ownedFishes.indexWhere((f) => f.fishId == fishId);
  if (idx == -1) return; // nothing to sell

  final fishDef = FishCatalog.byId(fishId);
  final price = fishDef.type == FishType.purchasable ? fishDef.price : 0;

  // Remove from Hive & Firestore
  await _repo.sellFish(currentChild.parentUid, currentChild.cid, fishId, price);

  // Remove locally
  ownedFishes.removeAt(idx);

  // Refresh balance locally
  await _refreshBalance();

  notifyListeners();
  if (kDebugMode) print("🟢 Sold fish $fishId for $price tokens");
}




  // ---------- Unlock ----------
  Future<void> unlockFish(String fishId) async {
  final child = currentChild;

  await firestore
      .collection('users')
      .doc(child.parentUid)
      .collection('children')
      .doc(child.cid)
      .collection('fishes')
      .doc(fishId)
      .set({
        'fishId': fishId,
        'isUnlocked': true,
        'isActive': false,
      }, SetOptions(merge: true));

      ownedFishes.add(
      OwnedFish(
        id: fishId, // 👈 can use same as fishId if you don’t have a unique doc ID
        fishId: fishId,
        isUnlocked: true,
      ),
    );

  notifyListeners();
}


  // ---------- Neglected State ----------
  Future<void> setNeglected(String fishId, bool neglected) async {
    final idx = ownedFishes.indexWhere((f) => f.fishId == fishId);
    if (idx == -1) return;

    ownedFishes[idx] = ownedFishes[idx].copyWith(isNeglected: neglected);
    await _repo.updateOwnedFish(currentChild.parentUid, currentChild.cid, ownedFishes[idx]);

    notifyListeners();
    if (kDebugMode) print("⚠️ Fish $fishId neglected state: $neglected");
  }

  // ---------- Helpers ----------
  FishDefinition getFishDefinition(String fishId) {
    return FishCatalog.byId(fishId);
  }

  Future<void> _refreshBalance() async {
  final newBalance = await fetchBalance();
  currentChild = currentChild.copyWith(balance: newBalance);
  notifyListeners();
}


  
}
