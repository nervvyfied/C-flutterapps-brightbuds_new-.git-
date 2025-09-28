import 'dart:collection';
import 'package:flutter/foundation.dart';
import 'package:brightbuds_new/providers/auth_provider.dart';
import '../models/placedDecor_model.dart';
import '../models/decor_definition.dart';
import '../repositories/decor_repository.dart';
import '/data/models/child_model.dart';
import '../catalogs/decor_catalog.dart';

class DecorProvider extends ChangeNotifier {
  final DecorRepository _repo = DecorRepository();
  final AuthProvider authProvider;

  late ChildUser currentChild;

  List<PlacedDecor> placedDecors = [];
  List<PlacedDecor> _editingBuffer = [];
  bool isInEditMode = false;
  String? movingDecorId;

  bool isDecorSelected(String decorId) {
  if (!isInEditMode) return false;
  return _editingBuffer.any((d) => d.id == decorId && d.isSelected);
}


  DecorProvider({required this.authProvider}) {
    if (authProvider.currentUserModel is ChildUser) {
      currentChild = authProvider.currentUserModel;
      _init();
    }
  }

  Future<void> _init() async {
    placedDecors = await _repo.getPlacedDecors(currentChild.parentUid, currentChild.cid);
    notifyListeners();
  }

  List<PlacedDecor> get inventory =>
      placedDecors.where((d) => !d.isPlaced).toList();

  UnmodifiableListView<PlacedDecor> get editingDecors =>
      UnmodifiableListView(_editingBuffer);

  void _updateLocalBalance(int newBalance) {
    currentChild = currentChild.copyWith(balance: newBalance);
    notifyListeners();
  }

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

    await _repo.addPlacedDecor(currentChild.parentUid, currentChild.cid, newDecor);
    await _repo.deductBalance(currentChild.parentUid, currentChild.cid, decor.price);
    _updateLocalBalance(currentChild.balance - decor.price);

    placedDecors.add(newDecor);
    notifyListeners();
    return true;
  }

  /// Place an inventory item and immediately enter edit mode so user can move it.
  Future<void> placeFromInventory(String decorId, double x, double y) async {
    final decor = placedDecors.firstWhere((d) => d.decorId == decorId && !d.isPlaced,
        orElse: () => throw Exception('Decor not found in inventory'));
    decor.x = x;
    decor.y = y;
    decor.isPlaced = true;

    await _repo.updatePlacedDecor(currentChild.parentUid, currentChild.cid, decor);

    final idx = placedDecors.indexWhere((d) => d.id == decor.id);
    if (idx != -1) placedDecors[idx] = decor;

    // Enter edit mode and focus the new placed item so the user can move it immediately
    enterEditMode(focusDecorId: decor.id);

    notifyListeners();
  }

  // ---------- Edit Mode ----------
  /// Creates a deep copy buffer. If `focusDecorId` provided we'll set that item selected
  /// and make it the initial movingDecorId so UI shows controls.
  void enterEditMode({String? focusDecorId}) {
    _editingBuffer =
        placedDecors.map((d) => PlacedDecor.fromMap(d.toMap())).toList();
    isInEditMode = true;

    // Clear all selections first
    for (var d in _editingBuffer) d.isSelected = false;

    if (focusDecorId != null) {
      final idx = _editingBuffer.indexWhere((d) => d.id == focusDecorId);
      if (idx != -1) _editingBuffer[idx].isSelected = true;
    }

    movingDecorId = null; // only start moving when Move button is clicked
    notifyListeners();
  }

  void cancelEditMode() {
    _editingBuffer = [];
    isInEditMode = false;
    movingDecorId = null;
    notifyListeners();
  }

  /// Store a decor back to inventory (isPlaced = false)
/*Future<void> storeDecorBackToInventory(String decorId) async {
  final index = _editingBuffer.indexWhere((d) => d.id == decorId);
  if (index == -1) return;

  _editingBuffer[index].isPlaced = false;
  _editingBuffer[index].isSelected = false; // deselect it

  // Also update main list
  final mainIdx = placedDecors.indexWhere((d) => d.id == decorId);
  if (mainIdx != -1) placedDecors[mainIdx].isPlaced = false;

  if (kDebugMode) print("🟡 Decor $decorId stored back to inventory");

  // Remove from edit buffer so UI doesn’t render it
  _editingBuffer.removeAt(index);

  // If nothing left selected, exit edit mode
  if (_editingBuffer.isEmpty) cancelEditMode();

  notifyListeners();
}*/


/// Sell a decor (remove permanently and refund tokens)
/*Future<void> sellDecor(String decorId) async {
  final index = _editingBuffer.indexWhere((d) => d.id == decorId);
  if (index == -1) return;

  final toDelete = _editingBuffer.removeAt(index); // remove first
  await _repo.removePlacedDecor(currentChild.parentUid, currentChild.cid, decorId);

  final def = getDecorDefinition(toDelete.decorId);
  await _repo.refundBalance(currentChild.parentUid, currentChild.cid, def.price);
  _updateLocalBalance(currentChild.balance + def.price);

  // Remove from main placedDecors too
  placedDecors.removeWhere((d) => d.id == decorId);

  if (kDebugMode) print("🟢 Decor $decorId sold for ${def.price} tokens");

  if (_editingBuffer.isEmpty) cancelEditMode();
  notifyListeners();
}*/

  void toggleDecorSelection(String decorId) {
  if (!isInEditMode) enterEditMode(focusDecorId: decorId);

  // Deselect all first
  for (var decor in _editingBuffer) {
    decor.isSelected = false;
  }

  // Select this decor
  final idx = _editingBuffer.indexWhere((d) => d.id == decorId);
  if (idx != -1) _editingBuffer[idx].isSelected = true;

  notifyListeners();

  if (kDebugMode) {
    print("Decor $decorId selected.");
  }
}


void startMovingDecor(String decorId) {
    if (!isInEditMode) return;

    movingDecorId = decorId;

    // Ensure decor is selected
    final idx = _editingBuffer.indexWhere((d) => d.id == decorId);
    if (idx != -1) _editingBuffer[idx].isSelected = true;

    notifyListeners();
  }

  void stopMovingDecor() {
    movingDecorId = null;
    notifyListeners();
  }

  Future<void> updateDecorPosition(String decorId, double x, double y, {bool persist = false}) async {
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

  // Persist immediately
  if (persist && mainIdx != -1) {
    final decor = placedDecors[mainIdx];
    await _repo.updatePlacedDecor(currentChild.parentUid, currentChild.cid, decor);
  }
}


  /// Delete or move decor in buffer.
/// - storeBack = true → return to inventory (isPlaced = false)
/// - sell = true → remove permanently and refund
/*Future<void> deleteDecorInBuffer(String decorId, {bool storeBack = false, bool sell = false}) async {
  if (!isInEditMode) return;

  final index = _editingBuffer.indexWhere((d) => d.id == decorId);
  if (index == -1) return;

  final toDelete = _editingBuffer[index];

  if (storeBack) {
    // Mark as unplaced (inventory)
    _editingBuffer[index].isPlaced = false;

    // Also update main placedDecors
    final mainIdx = placedDecors.indexWhere((d) => d.id == decorId);
    if (mainIdx != -1) {
      placedDecors[mainIdx].isPlaced = false;
    }

    if (kDebugMode) print("🟡 Decor $decorId stored back to inventory");
  } else if (sell) {
    // Remove permanently
    _editingBuffer.removeAt(index);
    await _repo.removePlacedDecor(currentChild.parentUid, currentChild.cid, decorId);

    // Refund child tokens
    final def = getDecorDefinition(toDelete.decorId);
    await _repo.refundBalance(currentChild.parentUid, currentChild.cid, def.price);
    _updateLocalBalance(currentChild.balance + def.price);

    // Remove from main placedDecors as well
    final mainIdx = placedDecors.indexWhere((d) => d.id == decorId);
    if (mainIdx != -1) placedDecors.removeAt(mainIdx);

    if (kDebugMode) print("🟢 Decor $decorId sold for ${def.price} tokens");
  }

  // Exit edit mode if nothing selected
  final anySelected = _editingBuffer.any((d) => d.isSelected);
  if (!anySelected) {
    cancelEditMode();
  }

  notifyListeners();
}*/

  /// Handles storing back to inventory or selling a decor
Future<void> handleDecorAction(
  String decorId, {
  bool storeBack = false,
  bool sell = false,
}) async {
  final idx = _editingBuffer.indexWhere((d) => d.id == decorId);
  if (idx == -1) return;

  final decor = _editingBuffer[idx];

  if (storeBack) {
    // Mark as inventory
    decor.isPlaced = false;
    decor.isSelected = false;

    // Update repo (Hive + Firestore)
    await _repo.storeDecor(currentChild.parentUid, currentChild.cid, decorId);

    // Update main placedDecors
    final mainIdx = placedDecors.indexWhere((d) => d.id == decorId);
    if (mainIdx != -1) placedDecors[mainIdx].isPlaced = false;

    // Remove from edit buffer so it disappears from aquarium view
    _editingBuffer.removeAt(idx);

    if (kDebugMode) print("🟡 Stored $decorId back to inventory");
  } else if (sell) {
    final def = getDecorDefinition(decor.decorId);

    // Call repo sell → removes decor + refunds balance
    await _repo.sellDecor(currentChild.parentUid, currentChild.cid, decorId, def.price);

    // Update local balance copy
    _updateLocalBalance(currentChild.balance + def.price);

    // Remove from local lists
    _editingBuffer.removeAt(idx);
    placedDecors.removeWhere((d) => d.id == decorId);

    if (kDebugMode) print("🟢 Sold $decorId for ${def.price} tokens");
  }

  // Exit edit mode if nothing selected
  if (!_editingBuffer.any((d) => d.isSelected)) {
    cancelEditMode();
  }

  notifyListeners();
}

void deselectDecor(String decorId) {
  final idx = _editingBuffer.indexWhere((d) => d.id == decorId);
  if (idx == -1) return;

  _editingBuffer[idx].isSelected = false;
  notifyListeners();
}


Future<void> saveEditMode() async {
  if (!isInEditMode) return;

  // Sync the current buffer to repository (Hive + Firestore)
  await _repo.updatePlacedDecors(
    currentChild.parentUid,
    currentChild.cid,
    _editingBuffer,
  );

  // Update main list to match buffer (only keep placed decors)
  placedDecors
    ..clear()
    ..addAll(_editingBuffer.where((d) => d.isPlaced));

  // Clear buffer and exit edit mode
  _editingBuffer.clear();
  movingDecorId = null;
  isInEditMode = false;

  notifyListeners();

  if (kDebugMode) {
    print("✅ Edit mode saved. ${placedDecors.length} decors now placed.");
  }
}




  Future<void> openEditModeForPlacement(String decorId) async {
    await _init();
    final decor = placedDecors.firstWhere((d) => d.decorId == decorId, orElse: () => throw Exception('not found'));
    enterEditMode(focusDecorId: decor.id);
  }

  Future<void> removeDecorPermanently(String decorId, {bool refund = true}) async {
    final decor = placedDecors.firstWhere((d) => d.id == decorId);
    await _repo.removePlacedDecor(currentChild.parentUid, currentChild.cid, decorId);

    if (refund) {
      final def = getDecorDefinition(decor.decorId);
      await _repo.refundBalance(currentChild.parentUid, currentChild.cid, def.price);
      _updateLocalBalance(currentChild.balance + def.price);
    }

    await _init();
  }

  DecorDefinition getDecorDefinition(String decorId) {
    return DecorCatalog.all.firstWhere((d) => d.id == decorId);
  }
}
