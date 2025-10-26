import 'dart:collection';
import 'package:flutter/foundation.dart';
import 'package:brightbuds_new/data/providers/auth_provider.dart';
import '../models/placedDecor_model.dart';
import '../models/decor_definition.dart';
import '../repositories/decor_repository.dart';
import '/data/models/child_model.dart';
import '../catalogs/decor_catalog.dart';
import 'package:brightbuds_new/utils/network_helper.dart';

/// Pending action types for offline queue
enum _PendingActionType { addOrUpdate, remove, balance }

class _PendingAction {
  final _PendingActionType type;
  final PlacedDecor? decor; // present for addOrUpdate
  final String? id; // id for remove or addOrUpdate
  _PendingAction.addOrUpdate(this.decor)
    : type = _PendingActionType.addOrUpdate,
      id = decor?.id;
  _PendingAction.remove(this.id)
    : type = _PendingActionType.remove,
      decor = null;
  _PendingAction.balance()
    : type = _PendingActionType.balance,
      decor = null,
      id = null;
}

class DecorProvider extends ChangeNotifier {
  final DecorRepository _repo = DecorRepository();
  final AuthProvider authProvider;

  late ChildUser currentChild;

  List<PlacedDecor> placedDecors = [];
  List<PlacedDecor> _editingBuffer = [];
  bool isInEditMode = false;
  String? movingDecorId;

  final List<_PendingAction> _pendingActions = [];
  bool _disposed = false; // ✅ track dispose

  DecorProvider({required this.authProvider}) {
    if (authProvider.currentUserModel is ChildUser) {
      currentChild = authProvider.currentUserModel as ChildUser;
      loadOfflineFirst();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  void _safeNotify() {
    if (!_disposed) notifyListeners();
  }

  // ---------- GETTERS ----------
  UnmodifiableListView<PlacedDecor> get editingDecors =>
      UnmodifiableListView(_editingBuffer);

  List<PlacedDecor> get inventory =>
      placedDecors.where((d) => !d.isPlaced).toList();

  bool get hasPending => _pendingActions.isNotEmpty;

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
    if (isAlreadyPlaced(decor.id) || isOwnedButNotPlaced(decor.id))
      return false;
    if (currentChild.balance < decor.price) return false;

    _updateLocalBalance(currentChild.balance - decor.price);

    final newDecor = PlacedDecor(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      decorId: decor.id,
      x: 100,
      y: 100,
      isPlaced: false,
    );

    placedDecors.add(newDecor);
    if (isInEditMode) _editingBuffer.add(PlacedDecor.fromMap(newDecor.toMap()));

    _pendingActions.add(_PendingAction.addOrUpdate(newDecor));
    _pendingActions.add(_PendingAction.balance());
    _safeNotify();

    try {
      await _repo.addPlacedDecor(
        currentChild.parentUid,
        currentChild.cid,
        newDecor,
      );
      await _maybePersistBalance();
      _removeFirstPendingOfTypeForId(
        _PendingActionType.addOrUpdate,
        newDecor.id,
      );
      _removeFirstPendingOfType(_PendingActionType.balance);
      if (await NetworkHelper.isOnline()) await pushPendingChanges();
    } catch (e) {
      debugPrint('⚠️ purchaseDecor offline, will sync later: $e');
    }

    return true;
  }

  // ---------- SELL ----------
  Future<void> sellDecor(String placedDecorId) async {
    final idx = placedDecors.indexWhere((d) => d.id == placedDecorId);
    if (idx == -1) return;

    final soldDecor = placedDecors.removeAt(idx);
    _editingBuffer.removeWhere((d) => d.id == soldDecor.id);

    final decorDef = DecorCatalog.byId(soldDecor.decorId);
    final price = decorDef.price;

    _updateLocalBalance(currentChild.balance + price);
    _pendingActions.add(_PendingAction.remove(soldDecor.id));
    _safeNotify();

    debugPrint(
      "🟢 Sold decor ${soldDecor.decorId} for $price tokens. New balance: ${currentChild.balance}",
    );
  }

  void _updateLocalBalance(int newBalance) {
    if (currentChild.balance == newBalance) return;
    currentChild = currentChild.copyWith(balance: newBalance);
    _pendingActions.add(_PendingAction.balance());
    try {
      _repo.updateBalance(currentChild.parentUid, currentChild.cid, newBalance);
    } catch (e) {
      debugPrint('⚠️ _repo.updateBalance failed (will sync later): $e');
    }
    _safeNotify();
  }

  // ---------- SET CHILD ----------
  Future<void> setChild(ChildUser child) async {
    currentChild = child;
    placedDecors.clear();
    _editingBuffer.clear();
    _pendingActions.clear();
    isInEditMode = false;
    movingDecorId = null;
    _safeNotify();

    await loadOfflineFirst();
  }

  // ---------- LOAD OFFLINE-FIRST ----------
  Future<void> loadOfflineFirst() async {
    try {
      final local = await _repo.getPlacedDecors(
        currentChild.parentUid,
        currentChild.cid,
      );

      // ✅ Prevent duplicates by replacing placedDecors with unique IDs
      final Map<String, PlacedDecor> unique = {
        for (var d in local) d.id: PlacedDecor.fromMap(d.toMap()),
      };
      placedDecors = unique.values.toList();

      _editingBuffer = placedDecors
          .map((d) => PlacedDecor.fromMap(d.toMap()))
          .toList();
      _safeNotify();
    } catch (e) {
      debugPrint('DecorProvider: Failed to load local placed decors: $e');
      placedDecors = [];
      _editingBuffer = [];
      _safeNotify();
    }

    if (await NetworkHelper.isOnline()) {
      await _mergeRemote();
    }
  }

  Future<void> _mergeRemote() async {
    try {
      final remote = await _repo.getPlacedDecors(
        currentChild.parentUid,
        currentChild.cid,
      );

      final Map<String, PlacedDecor> merged = {
        for (var d in placedDecors) d.id: PlacedDecor.fromMap(d.toMap()),
      };
      for (var r in remote) {
        merged[r.id] = PlacedDecor.fromMap(r.toMap());
      }

      placedDecors = merged.values.toList();
      _editingBuffer = placedDecors
          .map((d) => PlacedDecor.fromMap(d.toMap()))
          .toList();
      _safeNotify();

      await _repo.updatePlacedDecors(
        currentChild.parentUid,
        currentChild.cid,
        placedDecors,
      );

      if (_pendingActions.isNotEmpty) await pushPendingChanges();
    } catch (e) {
      debugPrint('DecorProvider: failed merging remote decors: $e');
    }
  }

  // ---------- EDIT MODE ----------
  void enterEditMode({String? focusDecorId}) {
    _editingBuffer = placedDecors
        .map((d) => PlacedDecor.fromMap(d.toMap()))
        .toList();
    isInEditMode = true;
    for (var d in _editingBuffer) d.isSelected = false;

    if (focusDecorId != null) {
      final idx = _editingBuffer.indexWhere((d) => d.id == focusDecorId);
      if (idx != -1) _editingBuffer[idx].isSelected = true;
    }

    movingDecorId = null;
    _safeNotify();
  }

  void cancelEditMode() {
    _editingBuffer.clear();
    isInEditMode = false;
    movingDecorId = null;
    _safeNotify();
  }

  void toggleDecorSelection(String decorId) {
    if (!isInEditMode) enterEditMode(focusDecorId: decorId);
    for (var d in _editingBuffer) d.isSelected = false;

    final idx = _editingBuffer.indexWhere((d) => d.id == decorId);
    if (idx != -1) _editingBuffer[idx].isSelected = true;

    _safeNotify();
  }

  void startMovingDecor(String decorId) {
    if (!isInEditMode) return;
    movingDecorId = decorId;

    final idx = _editingBuffer.indexWhere((d) => d.id == decorId);
    if (idx != -1) _editingBuffer[idx].isSelected = true;

    _safeNotify();
  }

  void stopMovingDecor() {
    movingDecorId = null;
    _safeNotify();
  }

  // ---------- PLACEMENT ----------
  Future<void> updateDecorPosition(
    String decorId,
    double x,
    double y, {
    bool persist = false,
  }) async {
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

    _safeNotify();

    if (persist && mainIdx != -1) {
      final decor = placedDecors[mainIdx];
      _pendingActions.add(_PendingAction.addOrUpdate(decor));
      try {
        await _repo.updatePlacedDecor(
          currentChild.parentUid,
          currentChild.cid,
          decor,
        );
        _removeFirstPendingOfTypeForId(
          _PendingActionType.addOrUpdate,
          decor.id,
        );
        if (await NetworkHelper.isOnline()) await pushPendingChanges();
      } catch (e) {
        debugPrint('⚠️ updateDecorPosition offline, will sync later: $e');
      }
    }
  }

  Future<void> placeDecor(String decorId) async {
    final idx = placedDecors.indexWhere(
      (d) => d.decorId == decorId && d.isPlaced == false,
    );
    if (idx == -1) return;

    placedDecors[idx] = placedDecors[idx].copyWith(isPlaced: true);
    _pendingActions.add(_PendingAction.addOrUpdate(placedDecors[idx]));
    _safeNotify();

    try {
      await _repo.updatePlacedDecor(
        currentChild.parentUid,
        currentChild.cid,
        placedDecors[idx],
      );
      _removeFirstPendingOfTypeForId(
        _PendingActionType.addOrUpdate,
        placedDecors[idx].id,
      );
      if (await NetworkHelper.isOnline()) await pushPendingChanges();
    } catch (e) {
      debugPrint('⚠️ placeDecor offline, will sync later: $e');
    }
  }

  Future<bool> placeFromInventory(String decorId, double x, double y) async {
    try {
      final idx = placedDecors.indexWhere(
        (d) => d.decorId == decorId && d.isPlaced == false,
      );

      if (idx != -1) {
        placedDecors[idx] = placedDecors[idx].copyWith(
          isPlaced: true,
          x: x,
          y: y,
        );
        _pendingActions.add(_PendingAction.addOrUpdate(placedDecors[idx]));
      } else {
        final newDecor = PlacedDecor(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          decorId: decorId,
          x: x,
          y: y,
          isPlaced: true,
        );
        placedDecors.add(newDecor);
        _pendingActions.add(_PendingAction.addOrUpdate(newDecor));
      }

      _editingBuffer = placedDecors
          .map((d) => PlacedDecor.fromMap(d.toMap()))
          .toList();
      _safeNotify();

      try {
        await _repo.updatePlacedDecors(
          currentChild.parentUid,
          currentChild.cid,
          placedDecors,
        );
        if (await NetworkHelper.isOnline()) await pushPendingChanges();
      } catch (e) {
        debugPrint('⚠️ placeFromInventory offline, will sync later: $e');
      }

      return true;
    } catch (e) {
      debugPrint('⚠️ placeFromInventory failed: $e');
      return false;
    }
  }

  Future<void> storeDecor(String decorId) async {
    final mainIdx = placedDecors.indexWhere((d) => d.id == decorId);
    if (mainIdx == -1) return;

    // 1️⃣ Update local state immediately
    final updatedDecor = placedDecors[mainIdx].copyWith(isPlaced: false);
    placedDecors[mainIdx] = updatedDecor;

    // Remove from editing buffer only if it’s not placed
    _editingBuffer.removeWhere((d) => d.id == decorId);

    // 2️⃣ Notify UI immediately
    notifyListeners();

    // 3️⃣ Queue pending action for offline/remote sync
    _pendingActions.add(_PendingAction.addOrUpdate(updatedDecor));

    // 4️⃣ Fire off remote update asynchronously
    await (_storeDecorRemote(updatedDecor));
  }

  // Helper to do async Firestore/Hive update without blocking UI
  Future<void> _storeDecorRemote(PlacedDecor decor) async {
    try {
      await _repo.updatePlacedDecor(
        currentChild.parentUid,
        currentChild.cid,
        decor,
      );

      // Remove pending action once synced
      _removeFirstPendingOfTypeForId(_PendingActionType.addOrUpdate, decor.id);

      // Attempt to push other pending changes
      if (await NetworkHelper.isOnline()) await pushPendingChanges();
    } catch (e) {
      debugPrint('⚠️ storeDecor remote sync failed: $e');
    }
  }

  // ---------- SAVE EDIT ----------
  Future<void> saveEditMode() async {
    if (!isInEditMode) return;

    for (var d in _editingBuffer) {
      final idx = placedDecors.indexWhere((p) => p.id == d.id);
      if (idx != -1) placedDecors[idx] = d;
      _pendingActions.add(_PendingAction.addOrUpdate(d));
    }

    _editingBuffer.clear();
    isInEditMode = false;
    movingDecorId = null;
    _safeNotify();

    try {
      await _repo.updatePlacedDecors(
        currentChild.parentUid,
        currentChild.cid,
        placedDecors,
      );
      if (await NetworkHelper.isOnline()) await pushPendingChanges();
      await _mergeRemote();
    } catch (e) {
      debugPrint('⚠️ saveEditMode offline, will sync later: $e');
    }
  }

  // ---------- SYNC ----------
  Future<void> pushPendingChanges() async {
    if (_pendingActions.isEmpty || !await NetworkHelper.isOnline()) return;

    final actions = List<_PendingAction>.from(_pendingActions);

    try {
      final addUpdates = actions
          .where(
            (a) => a.type == _PendingActionType.addOrUpdate && a.decor != null,
          )
          .map((a) => a.decor!)
          .toList();
      if (addUpdates.isNotEmpty) {
        await _repo.pushPlacedDecorChanges(
          currentChild.parentUid,
          currentChild.cid,
          addUpdates,
        );
        for (var d in addUpdates) {
          _removeFirstPendingOfTypeForId(_PendingActionType.addOrUpdate, d.id);
        }
      }

      final removes = actions
          .where((a) => a.type == _PendingActionType.remove && a.id != null)
          .map((a) => a.id!)
          .toList();
      for (var id in removes) {
        await _repo.removePlacedDecor(
          currentChild.parentUid,
          currentChild.cid,
          id,
        );
        _removeFirstPendingOfTypeForId(_PendingActionType.remove, id);
      }

      final hasBalance = actions.any(
        (a) => a.type == _PendingActionType.balance,
      );
      if (hasBalance) {
        await _maybePersistBalance();
        _removeFirstPendingOfType(_PendingActionType.balance);
      }

      await _mergeRemote();
    } catch (e) {
      debugPrint('DecorProvider: pushPendingChanges failed: $e');
    }
  }

  void _removeFirstPendingOfType(_PendingActionType type) {
    final idx = _pendingActions.indexWhere((a) => a.type == type);
    if (idx != -1) _pendingActions.removeAt(idx);
  }

  void _removeFirstPendingOfTypeForId(_PendingActionType type, String? id) {
    if (id == null) return;
    final idx = _pendingActions.indexWhere((a) => a.type == type && a.id == id);
    if (idx != -1) _pendingActions.removeAt(idx);
  }

  Future<void> _maybePersistBalance() async {
    try {
      final storedBalance = await _repo.fetchBalance(
        currentChild.parentUid,
        currentChild.cid,
      );
      if (storedBalance != currentChild.balance) {
        await _repo.updateBalance(
          currentChild.parentUid,
          currentChild.cid,
          currentChild.balance,
        );
      }
    } catch (e) {
      debugPrint('⚠️ _maybePersistBalance failed: $e');
    }
  }

  void clearData() {
    placedDecors.clear();
    _editingBuffer.clear();
    isInEditMode = false;
    movingDecorId = null;
    _pendingActions.clear();
    _safeNotify();
    if (kDebugMode) print("🟢 DecorProvider data cleared for logout.");
  }
}
