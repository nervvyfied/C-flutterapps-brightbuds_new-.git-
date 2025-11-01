// ignore_for_file: avoid_types_as_parameter_names, unused_element

import 'dart:collection';
import 'package:cloud_firestore/cloud_firestore.dart';
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
  final int? delta; // ✅ for balance changes

  _PendingAction.addOrUpdate(this.decor)
    : type = _PendingActionType.addOrUpdate,
      id = decor?.id,
      delta = null;

  _PendingAction.remove(this.id)
    : type = _PendingActionType.remove,
      decor = null,
      delta = null;

  _PendingAction.balance(this.delta)
    : type = _PendingActionType.balance,
      decor = null,
      id = null;
}

class DecorProvider extends ChangeNotifier {
  int _balance = 0;

  int get balance => _balance;

  void updateBalance(int newBalance) {
    _balance = newBalance;
    notifyListeners();
  }

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
    // Prevent buying if already owned
    if (isAlreadyPlaced(decor.id) || isOwnedButNotPlaced(decor.id)) {
      return false;
    }

    // Check if balance is enough
    if (currentChild.balance < decor.price) return false;

    // 1️⃣ Deduct local balance safely
    _updateLocalBalance(-decor.price);

    // 2️⃣ Create new placed decor
    final newDecor = PlacedDecor(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      decorId: decor.id,
      x: 100,
      y: 100,
      isPlaced: false,
    );

    // 3️⃣ Update local lists
    placedDecors.add(newDecor);
    if (isInEditMode) _editingBuffer.add(PlacedDecor.fromMap(newDecor.toMap()));

    // 4️⃣ Queue pending action for offline sync
    _pendingActions.add(_PendingAction.addOrUpdate(newDecor));

    _safeNotify();

    // 5️⃣ Fire off async Firestore/Hive sync
    _syncDecorToFirestore(newDecor);
    _syncBalanceToFirestore(); // ensure balance is synced

    return true;
  }

  // Helper to sync a placed decor without blocking UI
  Future<void> _syncDecorToFirestore(PlacedDecor decor) async {
    try {
      if (await NetworkHelper.isOnline()) {
        await _repo.addPlacedDecor(
          currentChild.parentUid,
          currentChild.cid,
          decor,
        );
        _removeFirstPendingOfTypeForId(
          _PendingActionType.addOrUpdate,
          decor.id,
        );

        // Try to push all other pending actions as well
        if (_pendingActions.isNotEmpty) await pushPendingChanges();
      }
    } catch (e) {
      debugPrint('⚠️ addPlacedDecor offline, will sync later: $e');
    }
  }

  // ---------- SELL ----------
  Future<void> sellDecor(String placedDecorId) async {
    final idx = placedDecors.indexWhere((d) => d.id == placedDecorId);
    if (idx == -1) return;

    final soldDecor = placedDecors.removeAt(idx);
    _editingBuffer.removeWhere((d) => d.id == soldDecor.id);

    // Get decor price
    final decorDef = DecorCatalog.byId(soldDecor.decorId);
    final price = decorDef.price;

    // 1️⃣ Increase balance locally
    _updateLocalBalance(price);

    // 2️⃣ Queue pending remove action
    _pendingActions.add(_PendingAction.remove(soldDecor.id));

    _safeNotify();

    // 3️⃣ Fire off async Firestore/Hive sync
    try {
      await _repo.removePlacedDecor(
        currentChild.parentUid,
        currentChild.cid,
        soldDecor.id,
      );
      _removeFirstPendingOfTypeForId(_PendingActionType.remove, soldDecor.id);

      // Sync all other pending actions including balance
      if (await NetworkHelper.isOnline()) await pushPendingChanges();
      _syncBalanceToFirestore();
    } catch (e) {
      debugPrint("⚠️ sellDecor offline, will sync later: $e");
    }

    if (kDebugMode) {
      debugPrint(
        "🟢 Sold decor ${soldDecor.decorId} for $price tokens. Balance: ${currentChild.balance}",
      );
    }
  }

  void _updateLocalBalance(int delta, {bool notify = true}) {
    if (delta == 0) return;

    // Update in-memory balance immediately
    currentChild = currentChild.copyWith(balance: currentChild.balance + delta);

    // Add pending action for Firestore sync
    _pendingActions.add(_PendingAction.balance(delta));

    if (notify) _safeNotify();

    // Fire off async Firestore merge (safely sums all pending deltas)
    _syncBalanceToFirestore();
  }

  Future<void> _syncBalanceToFirestore() async {
    if (!await NetworkHelper.isOnline()) return;

    final pendingDeltas = _pendingActions
        .where((a) => a.type == _PendingActionType.balance)
        .toList();
    if (pendingDeltas.isEmpty) return;

    try {
      final childRef = FirebaseFirestore.instance
          .collection('users')
          .doc(currentChild.parentUid)
          .collection('children')
          .doc(currentChild.cid);

      await FirebaseFirestore.instance.runTransaction((transaction) async {
        final snapshot = await transaction.get(childRef);
        if (!snapshot.exists) throw Exception("Child not found");

        int firestoreBalance = snapshot.data()?['balance'] ?? 0;

        // Sum all pending deltas
        final totalDelta = pendingDeltas.fold(
          0,
          (sum, a) => sum + (a.delta ?? 0),
        );

        final newBalance = firestoreBalance + totalDelta;

        // Update Firestore
        transaction.update(childRef, {'balance': newBalance});

        // Update local memory & Hive/local storage
        currentChild = currentChild.copyWith(balance: newBalance);
        await _repo.updateBalance(
          currentChild.parentUid,
          currentChild.cid,
          newBalance,
        );

        // Remove applied pending balance actions
        _pendingActions.removeWhere(
          (a) => a.type == _PendingActionType.balance,
        );

        if (kDebugMode) print("✅ Synced balance: $newBalance");
      });
    } catch (e) {
      debugPrint("⚠️ Failed to sync balance: $e");
    }
  }

  Future<void> loadBalance() async {
    try {
      // 1️⃣ Load local cached balance first
      final cachedBalance = await _repo.fetchBalance(
        currentChild.parentUid,
        currentChild.cid,
      );

      currentChild = currentChild.copyWith(balance: cachedBalance);
      _safeNotify();

      if (kDebugMode) print("💰 Loaded local balance: $cachedBalance");

      // 2️⃣ Merge with Firestore balance asynchronously
      await _syncBalanceFromFirestore();
    } catch (e) {
      debugPrint("⚠️ loadBalance failed: $e");
    }
  }

  Future<void> _syncBalanceFromFirestore() async {
    try {
      if (!await NetworkHelper.isOnline()) return;

      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(currentChild.parentUid)
          .collection('children')
          .doc(currentChild.cid)
          .get();

      if (!doc.exists) return;

      // Firestore balance
      final remote = doc.data()?['balance'] ?? 0;
      int remoteBalance;
      if (remote is int) {
        remoteBalance = remote;
      } else if (remote is double) {
        remoteBalance = remote.toInt();
      } else {
        remoteBalance = int.tryParse('$remote') ?? 0;
      }

      // Sum all pending balance deltas locally
      final pendingDelta = _pendingActions
          .where((a) => a.type == _PendingActionType.balance)
          .fold(0, (sum, a) => sum + (a.delta ?? 0));

      // Merge Firestore + pending
      final mergedBalance = remoteBalance + pendingDelta;

      // Update local memory & Hive only if changed
      if (currentChild.balance != mergedBalance) {
        currentChild = currentChild.copyWith(balance: mergedBalance);
        _safeNotify();

        if (kDebugMode) {
          print("💰 Merged balance from Firestore + pending: $mergedBalance");
        }

        await _repo.updateBalance(
          currentChild.parentUid,
          currentChild.cid,
          mergedBalance,
        );
      }

      // Now push all pending balance deltas to Firestore safely
      if (pendingDelta != 0) {
        await _syncBalanceToFirestore();
      }
    } catch (e) {
      debugPrint("⚠️ _syncBalanceFromFirestore failed: $e");
    }
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

    await loadOfflineFirst(); // loads decors
    await loadBalance(); // loads balance
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
      await _syncBalanceToFirestore();
      await pushPendingChanges(); // push other decor changes
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
    for (var d in _editingBuffer) {
      d.isSelected = false;
    }

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
    for (var d in _editingBuffer) {
      d.isSelected = false;
    }

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
      // 1️⃣ Handle add/update decors
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

      // 2️⃣ Handle removes
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

      // ✅ No balance handling here—it's done via _syncBalanceToFirestore

      // 3️⃣ Merge remote decors
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
