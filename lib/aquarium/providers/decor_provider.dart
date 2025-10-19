import 'dart:collection';
import 'package:flutter/foundation.dart';
import 'package:brightbuds_new/data/providers/auth_provider.dart';
import '../models/placedDecor_model.dart';
import '../models/decor_definition.dart';
import '../repositories/decor_repository.dart';
import '/data/models/child_model.dart';
import '../catalogs/decor_catalog.dart';
import 'package:brightbuds_new/utils/network_helper.dart';

class DecorProvider extends ChangeNotifier {
  final DecorRepository _repo = DecorRepository();
  final AuthProvider authProvider;

  late ChildUser currentChild;

  List<PlacedDecor> placedDecors = [];
  List<PlacedDecor> _editingBuffer = [];
  bool isInEditMode = false;
  String? movingDecorId;

  /// Queue for pending offline changes
  final Set<String> _pendingPushIds = {};

  DecorProvider({required this.authProvider}) {
    if (authProvider.currentUserModel is ChildUser) {
      currentChild = authProvider.currentUserModel as ChildUser;
      loadOfflineFirst();
    }
  }

  // ---------- GETTERS ----------
  UnmodifiableListView<PlacedDecor> get editingDecors =>
      UnmodifiableListView(_editingBuffer);

  List<PlacedDecor> get inventory =>
      placedDecors.where((d) => !d.isPlaced).toList();

  bool isDecorSelected(String decorId) =>
      isInEditMode &&
      _editingBuffer.any((d) => d.id == decorId && d.isSelected);

  DecorDefinition getDecorDefinition(String decorId) =>
      DecorCatalog.all.firstWhere((d) => d.id == decorId);

  bool isAlreadyPlaced(String decorId) =>
      placedDecors.any((d) => d.decorId == decorId && d.isPlaced);

  bool isOwnedButNotPlaced(String decorId) =>
      placedDecors.any((d) => d.decorId == decorId && !d.isPlaced);

  // ---------- PURCHASE (offline-first) ----------
  Future<bool> purchaseDecor(DecorDefinition decor) async {
  // Prevent duplicate purchase
  if (isAlreadyPlaced(decor.id) || isOwnedButNotPlaced(decor.id)) return false;
  if (currentChild.balance < decor.price) return false;

  // 1️⃣ Update local balance immediately (optimistic)
  currentChild = currentChild.copyWith(balance: currentChild.balance - decor.price);

  // 2️⃣ Add decor locally
  final newDecor = PlacedDecor(
    id: DateTime.now().millisecondsSinceEpoch.toString(),
    decorId: decor.id,
    x: 100,
    y: 100,
    isPlaced: false,
  );
  placedDecors.add(newDecor);
  if (isInEditMode) _editingBuffer.add(PlacedDecor.fromMap(newDecor.toMap()));

  // 3️⃣ Queue pending changes
  _pendingPushIds.add(newDecor.id);
  _pendingPushIds.add('_balance'); // special ID to track balance change
  notifyListeners();

  // 4️⃣ Attempt to sync
  try {
    await _repo.addPlacedDecor(currentChild.parentUid, currentChild.cid, newDecor);
    await _maybePersistBalance();
    _pendingPushIds.remove(newDecor.id);
    _pendingPushIds.remove('_balance');
    if (await NetworkHelper.isOnline()) await pushPendingChanges();
  } catch (e) {
    debugPrint('⚠️ purchaseDecor offline, will sync later: $e');
  }

  return true;
}

  // ---------- SET CHILD ----------
  Future<void> setChild(ChildUser child) async {
    currentChild = child;
    placedDecors.clear();
    _editingBuffer.clear();
    _pendingPushIds.clear();
    isInEditMode = false;
    movingDecorId = null;
    notifyListeners();

    await loadOfflineFirst();
  }

  // ---------- LOAD OFFLINE-FIRST ----------
  Future<void> loadOfflineFirst() async {
    try {
      final local =
          await _repo.getPlacedDecors(currentChild.parentUid, currentChild.cid);
      placedDecors = List.from(local);
      _editingBuffer =
          placedDecors.map((d) => PlacedDecor.fromMap(d.toMap())).toList();
      notifyListeners();
    } catch (e) {
      debugPrint('DecorProvider: Failed to load local placed decors: $e');
      placedDecors = [];
      _editingBuffer = [];
      notifyListeners();
    }

    if (await NetworkHelper.isOnline()) {
      await _mergeRemote();
    }
  }

  Future<void> _mergeRemote() async {
    try {
      final remote =
          await _repo.getPlacedDecors(currentChild.parentUid, currentChild.cid);

      final Map<String, PlacedDecor> merged = {
        for (var d in placedDecors) d.id: PlacedDecor.fromMap(d.toMap()),
      };

      for (var r in remote) {
        merged[r.id] = PlacedDecor.fromMap(r.toMap());
      }

      placedDecors = merged.values.toList();
      _editingBuffer =
          placedDecors.map((d) => PlacedDecor.fromMap(d.toMap())).toList();
      notifyListeners();

      await _repo.updatePlacedDecors(
          currentChild.parentUid, currentChild.cid, placedDecors);
      if (_pendingPushIds.isNotEmpty) await pushPendingChanges();
    } catch (e) {
      debugPrint('DecorProvider: failed merging remote decors: $e');
    }
  }

  // ---------- EDIT MODE ----------
  void enterEditMode({String? focusDecorId}) {
    _editingBuffer =
        placedDecors.map((d) => PlacedDecor.fromMap(d.toMap())).toList();
    isInEditMode = true;
    for (var d in _editingBuffer) d.isSelected = false;

    if (focusDecorId != null) {
      final idx = _editingBuffer.indexWhere((d) => d.id == focusDecorId);
      if (idx != -1) _editingBuffer[idx].isSelected = true;
    }

    movingDecorId = null;
    notifyListeners();
  }

  void cancelEditMode() {
    _editingBuffer.clear();
    isInEditMode = false;
    movingDecorId = null;
    notifyListeners();
  }

  void toggleDecorSelection(String decorId) {
    if (!isInEditMode) enterEditMode(focusDecorId: decorId);
    for (var d in _editingBuffer) d.isSelected = false;

    final idx = _editingBuffer.indexWhere((d) => d.id == decorId);
    if (idx != -1) _editingBuffer[idx].isSelected = true;

    notifyListeners();
  }

  void startMovingDecor(String decorId) {
    if (!isInEditMode) return;
    movingDecorId = decorId;

    final idx = _editingBuffer.indexWhere((d) => d.id == decorId);
    if (idx != -1) _editingBuffer[idx].isSelected = true;

    notifyListeners();
  }

  void stopMovingDecor() {
    movingDecorId = null;
    notifyListeners();
  }

  // ---------- PLACEMENT ----------
  Future<void> updateDecorPosition(String decorId, double x, double y,
      {bool persist = false}) async {
    final idx = _editingBuffer.indexWhere((d) => d.id == decorId);
    if (idx != -1) {
      _editingBuffer[idx].x = x;
      _editingBuffer[idx].y = y;
    }

    final mainIdx = placedDecors.indexWhere((d) => d.id == decorId);
    if (mainIdx != -1) {
      placedDecors[mainIdx].x = x;
      placedDecors[mainIdx].y = y;
    }

    notifyListeners();

    if (persist && mainIdx != -1) {
      final decor = placedDecors[mainIdx];
      _pendingPushIds.add(decor.id);
      try {
        await _repo.updatePlacedDecor(
            currentChild.parentUid, currentChild.cid, decor);
        _pendingPushIds.remove(decor.id);
        if (await NetworkHelper.isOnline()) await pushPendingChanges();
      } catch (e) {
        debugPrint('⚠️ updateDecorPosition offline, will sync later: $e');
      }
    }
  }

  /// ✅ FIXED: Properly place a decor and remove it from inventory immediately
  Future<void> placeDecor(String decorId) async {
    final idx = placedDecors.indexWhere(
        (d) => d.decorId == decorId && d.isPlaced == false);
    if (idx == -1) return;

    placedDecors[idx] = placedDecors[idx].copyWith(isPlaced: true);
    _pendingPushIds.add(placedDecors[idx].id);
    notifyListeners();

    try {
      await _repo.updatePlacedDecor(
          currentChild.parentUid, currentChild.cid, placedDecors[idx]);
      _pendingPushIds.remove(placedDecors[idx].id);
      if (await NetworkHelper.isOnline()) await pushPendingChanges();
    } catch (e) {
      debugPrint('⚠️ placeDecor offline, will sync later: $e');
    }
  }

  Future<void> placeFromInventory(String decorId, double x, double y) async {
    // Update the existing decor instead of creating a new one
    final idx = placedDecors.indexWhere(
        (d) => d.decorId == decorId && d.isPlaced == false);
    if (idx != -1) {
      placedDecors[idx].isPlaced = true;
      placedDecors[idx].x = x;
      placedDecors[idx].y = y;
      _pendingPushIds.add(placedDecors[idx].id);
    } else {
      // fallback for missing decor entry
      final newDecor = PlacedDecor(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        decorId: decorId,
        x: x,
        y: y,
        isPlaced: true,
      );
      placedDecors.add(newDecor);
      _pendingPushIds.add(newDecor.id);
    }

    _editingBuffer =
        placedDecors.map((d) => PlacedDecor.fromMap(d.toMap())).toList();
    notifyListeners();

    try {
      await _repo.updatePlacedDecors(
          currentChild.parentUid, currentChild.cid, placedDecors);
      if (await NetworkHelper.isOnline()) await pushPendingChanges();
    } catch (e) {
      debugPrint('⚠️ placeFromInventory offline, will sync later: $e');
    }
  }

  // ---------- STORE ----------
  Future<void> storeDecor(String decorId) async {
    final mainIdx = placedDecors.indexWhere((d) => d.id == decorId);
    if (mainIdx == -1) return;

    placedDecors[mainIdx].isPlaced = false;
    _editingBuffer.removeWhere((d) => d.id == decorId);
    _pendingPushIds.add(decorId);
    notifyListeners();

    try {
      await _repo.updatePlacedDecor(
          currentChild.parentUid, currentChild.cid, placedDecors[mainIdx]);
      _pendingPushIds.remove(decorId);
      if (await NetworkHelper.isOnline()) await pushPendingChanges();
    } catch (e) {
      debugPrint('⚠️ storeDecor offline, will sync later: $e');
    }
  }

  // ---------- SELL ----------
  Future<void> sellDecor(String decorId) async {
  final mainIdx = placedDecors.indexWhere((d) => d.id == decorId);
  if (mainIdx == -1) return;

  final decor = placedDecors.removeAt(mainIdx);
  _editingBuffer.removeWhere((d) => d.id == decorId);

  // 1️⃣ Update balance locally
  final def = getDecorDefinition(decor.decorId);
  currentChild = currentChild.copyWith(balance: currentChild.balance + def.price);

  // 2️⃣ Queue pending changes
  _pendingPushIds.add(decorId);
  _pendingPushIds.add('_balance');
  notifyListeners();

  // 3️⃣ Attempt remote sync
  try {
    await _repo.removePlacedDecor(currentChild.parentUid, currentChild.cid, decorId);
    await _maybePersistBalance();
    _pendingPushIds.remove(decorId);
    _pendingPushIds.remove('_balance');
    if (await NetworkHelper.isOnline()) {
      await pushPendingChanges();
      await _mergeRemote();
    }
  } catch (e) {
    debugPrint('⚠️ sellDecor offline, will sync later: $e');
  }
}

// ---------- Helper for offline-safe balance persist ----------
Future<void> _maybePersistBalance() async {
  try {
    final storedBalance = await _repo.fetchBalance(currentChild.parentUid, currentChild.cid);
    if (storedBalance != currentChild.balance) {
      await _repo.updateBalance(
          currentChild.parentUid, currentChild.cid, currentChild.balance);
    }
  } catch (e) {
    debugPrint('⚠️ _maybePersistBalance failed: $e');
  }
}
  // ---------- SAVE EDIT ----------
  Future<void> saveEditMode() async {
    if (!isInEditMode) return;

    for (var d in _editingBuffer) {
      final idx = placedDecors.indexWhere((p) => p.id == d.id);
      if (idx != -1) placedDecors[idx] = d;
      _pendingPushIds.add(d.id);
    }

    _editingBuffer.clear();
    isInEditMode = false;
    movingDecorId = null;
    notifyListeners();

    try {
      await _repo.updatePlacedDecors(
          currentChild.parentUid, currentChild.cid, placedDecors);
      if (await NetworkHelper.isOnline()) await pushPendingChanges();
      await _mergeRemote();
    } catch (e) {
      debugPrint('⚠️ saveEditMode offline, will sync later: $e');
    }
  }

  // ---------- SYNC ----------
  Future<void> pushPendingChanges() async {
    if (_pendingPushIds.isEmpty || !await NetworkHelper.isOnline()) return;

    try {
      final toPush =
          placedDecors.where((d) => _pendingPushIds.contains(d.id)).toList();
      if (toPush.isEmpty) {
        _pendingPushIds.clear();
        return;
      }

      await _repo.pushPlacedDecorChanges(
          currentChild.parentUid, currentChild.cid, toPush);
      for (var d in toPush) _pendingPushIds.remove(d.id);

      await _mergeRemote();
    } catch (e) {
      debugPrint('DecorProvider: pushPendingChanges failed: $e');
    }
  }

  // ---------- CLEAR DATA ----------
  void clearData() {
    placedDecors.clear();
    _editingBuffer.clear();
    isInEditMode = false;
    movingDecorId = null;
    _pendingPushIds.clear();
    notifyListeners();
    if (kDebugMode) print("🟢 DecorProvider data cleared for logout.");
  }
}
