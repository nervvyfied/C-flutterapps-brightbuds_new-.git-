import 'dart:collection';
import 'package:flutter/foundation.dart';
import 'package:brightbuds_new/data/providers/auth_provider.dart';
import '../models/placedDecor_model.dart';
import '../models/decor_definition.dart';
import '../repositories/decor_repository.dart';
import '/data/models/child_model.dart';
import '../catalogs/decor_catalog.dart';
import 'package:brightbuds_new/utils/network_helper.dart';

/// Offline-first DecorProvider
///
/// Handles decor placement, offline caching, and online sync with Firestore.
class DecorProvider extends ChangeNotifier {
  final DecorRepository _repo = DecorRepository();
  final AuthProvider authProvider;

  late ChildUser currentChild;

  /// Canonical list of placed decors (merged local + remote)
  List<PlacedDecor> placedDecors = [];

  /// Local edit buffer for placement screen
  List<PlacedDecor> _editingBuffer = [];

  bool isInEditMode = false;
  String? movingDecorId;

  /// Queue of pending local changes (by decor ID)
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

Future<bool> purchaseDecor(DecorDefinition decor) async {
  if (isAlreadyPlaced(decor.id)) return false;
  if (currentChild.balance < decor.price) return false;

  final newDecor = PlacedDecor(
    id: DateTime.now().millisecondsSinceEpoch.toString(),
    decorId: decor.id,
    x: 100,
    y: 100,
    isPlaced: false,
  );

  // Deduct balance
  currentChild = currentChild.copyWith(
    balance: currentChild.balance - decor.price,
  );

  // Add to placedDecors
  placedDecors.add(newDecor);
  notifyListeners();

  // Save to repo
  await _repo.addPlacedDecor(
    currentChild.parentUid,
    currentChild.cid,
    newDecor,
  );

  return true; // ✅ Return success
}

  // ---------- OFFLINE-FIRST LOAD ----------

  Future<void> loadOfflineFirst() async {
    try {
      // Load cached local decors
      final local = await _repo.getPlacedDecors(
        currentChild.parentUid,
        currentChild.cid,
      );
      placedDecors = List.from(local);
      notifyListeners();
    } catch (e) {
      debugPrint('DecorProvider: Failed to load local placed decors: $e');
      placedDecors = [];
      notifyListeners();
    }

    // Merge remote when online
    if (await NetworkHelper.isOnline()) {
      await _mergeRemote();
    } else {
      debugPrint('DecorProvider: offline — showing cached decors.');
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

      // Save merged local copy
      await _repo.updatePlacedDecors(
        currentChild.parentUid,
        currentChild.cid,
        placedDecors,
      );

      // Push queued changes
      if (_pendingPushIds.isNotEmpty) {
        await pushPendingChanges();
      }

      notifyListeners();
      debugPrint(
        'DecorProvider: merged remote placed decors (${remote.length}) into local cache.',
      );
    } catch (e) {
      debugPrint('DecorProvider: failed merging remote decors: $e');
    }
  }

  // ---------- EDIT MODE ----------

  enterEditMode({String? focusDecorId}) {
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

  // ---------- PLACEMENT / POSITION ----------

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

    notifyListeners();

    if (persist && mainIdx != -1) {
      final decor = placedDecors[mainIdx];
      await _repo.updatePlacedDecor(
        currentChild.parentUid,
        currentChild.cid,
        decor,
      );
      _pendingPushIds.add(decor.id);

      if (await NetworkHelper.isOnline()) {
        await pushPendingChanges();
      }
    }
  }

  Future<void> placeFromInventory(String decorId, double x, double y) async {
    final newDecor = PlacedDecor(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      decorId: decorId,
      x: x,
      y: y,
      isPlaced: true,
    );

    placedDecors.add(newDecor);
    notifyListeners();

    await _repo.addPlacedDecor(
      currentChild.parentUid,
      currentChild.cid,
      newDecor,
    );
    _pendingPushIds.add(newDecor.id);

    if (await NetworkHelper.isOnline()) {
      await pushPendingChanges();
    }

    enterEditMode(focusDecorId: newDecor.id);
  }

  // ---------- STORE / SELL / REMOVE ----------

  Future<void> storeDecor(String decorId) async {
    final mainIdx = placedDecors.indexWhere((d) => d.id == decorId);
    if (mainIdx == -1) return;

    placedDecors[mainIdx].isPlaced = false;
    await _repo.updatePlacedDecor(
      currentChild.parentUid,
      currentChild.cid,
      placedDecors[mainIdx],
    );
    _pendingPushIds.add(decorId);

    notifyListeners();

    if (await NetworkHelper.isOnline()) {
      await pushPendingChanges();
    }
  }

  Future<void> sellDecor(String decorId) async {
    final mainIdx = placedDecors.indexWhere((d) => d.id == decorId);
    if (mainIdx == -1) return;

    final decor = placedDecors.removeAt(mainIdx);
    final def = getDecorDefinition(decor.decorId);

    await _repo.removePlacedDecor(
      currentChild.parentUid,
      currentChild.cid,
      decorId,
    );

    currentChild = currentChild.copyWith(
      balance: currentChild.balance + def.price,
    );
    _pendingPushIds.add(decorId);

    notifyListeners();

    if (await NetworkHelper.isOnline()) {
      await pushPendingChanges();
    }
  }

  Future<void> removeDecorPermanently(
    String decorId, {
    bool refund = true,
  }) async {
    final mainIdx = placedDecors.indexWhere((d) => d.id == decorId);
    if (mainIdx == -1) return;

    final decor = placedDecors.removeAt(mainIdx);
    final def = getDecorDefinition(decor.decorId);

    await _repo.removePlacedDecor(
      currentChild.parentUid,
      currentChild.cid,
      decorId,
    );

    if (refund) {
      currentChild = currentChild.copyWith(
        balance: currentChild.balance + def.price,
      );
      await _repo.updateBalance(
        currentChild.parentUid,
        currentChild.cid,
        currentChild.balance,
      );
    }

    _pendingPushIds.add(decorId);
    notifyListeners();

    if (await NetworkHelper.isOnline()) {
      await pushPendingChanges();
    }

    await _initFromRepo();
  }

  // ---------- SAVE / CANCEL EDIT ----------

  Future<void> saveEditMode() async {
    if (!isInEditMode) return;

    final Map<String, PlacedDecor> bufMap = {
      for (var d in _editingBuffer) d.id: PlacedDecor.fromMap(d.toMap()),
    };

    final Map<String, PlacedDecor> canon = {
      for (var d in placedDecors) d.id: PlacedDecor.fromMap(d.toMap()),
    };

    for (var entry in bufMap.entries) {
      canon[entry.key] = entry.value;
      _pendingPushIds.add(entry.key);
    }

    placedDecors = canon.values.toList();

    await _repo.updatePlacedDecors(
      currentChild.parentUid,
      currentChild.cid,
      placedDecors,
    );

    _editingBuffer.clear();
    isInEditMode = false;
    movingDecorId = null;

    notifyListeners();

    if (await NetworkHelper.isOnline()) {
      await pushPendingChanges();
      await _mergeRemote();
    }
  }

  // ---------- SYNC / PUSH ----------

  Future<void> pushPendingChanges() async {
    if (_pendingPushIds.isEmpty) return;

    final online = await NetworkHelper.isOnline();
    if (!online) {
      debugPrint('DecorProvider: offline — skipping pushPendingChanges.');
      return;
    }

    try {
      final toPush = placedDecors
          .where((d) => _pendingPushIds.contains(d.id))
          .map((d) => PlacedDecor.fromMap(d.toMap()))
          .toList();

      if (toPush.isEmpty) {
        _pendingPushIds.clear();
        return;
      }

      await _repo.pushPlacedDecorChanges(
        currentChild.parentUid,
        currentChild.cid,
        toPush,
      );

      for (var d in toPush) {
        _pendingPushIds.remove(d.id);
      }

      await _mergeRemote();

      debugPrint(
        'DecorProvider: pushed ${toPush.length} pending decor changes.',
      );
    } catch (e) {
      debugPrint('DecorProvider: pushPendingChanges failed: $e');
    }
  }

  // ---------- INTERNAL ----------

  Future<void> _initFromRepo() async {
    try {
      placedDecors = await _repo.getPlacedDecors(
        currentChild.parentUid,
        currentChild.cid,
      );
      notifyListeners();
    } catch (e) {
      debugPrint('DecorProvider: _initFromRepo failed: $e');
    }
  }
}
