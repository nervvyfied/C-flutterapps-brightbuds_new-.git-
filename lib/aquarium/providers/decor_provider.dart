import 'dart:collection';
import 'package:flutter/foundation.dart';
import 'package:brightbuds_new/providers/auth_provider.dart';
import 'package:hive_flutter/hive_flutter.dart';
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

  Future<void> placeFromInventory(String decorId, double x, double y) async {
    final decor = placedDecors.firstWhere((d) => d.decorId == decorId && !d.isPlaced);
    decor.x = x;
    decor.y = y;
    decor.isPlaced = true;
    await _repo.updatePlacedDecor(currentChild.parentUid, currentChild.cid, decor);

    final idx = placedDecors.indexWhere((d) => d.id == decor.id);
    if (idx != -1) placedDecors[idx] = decor;
    notifyListeners();
  }
  

  // ---------- Edit Mode ----------
  void enterEditMode({String? focusDecorId}) {
    _editingBuffer = placedDecors.map((d) => PlacedDecor.fromMap(d.toMap())).toList();
    isInEditMode = true;
    movingDecorId = focusDecorId;
    notifyListeners();
  }

  void cancelEditMode() {
    _editingBuffer = [];
    isInEditMode = false;
    movingDecorId = null;
    notifyListeners();
  }

  Future<void> saveEditMode() async {
    for (var edited in _editingBuffer) {
      final exists = placedDecors.any((p) => p.id == edited.id);
      if (exists) {
        await _repo.updatePlacedDecor(currentChild.parentUid, currentChild.cid, edited);
      } else {
        await _repo.addPlacedDecor(currentChild.parentUid, currentChild.cid, edited);
      }
    }
    await _init();
    _editingBuffer = [];
    isInEditMode = false;
    movingDecorId = null;
  }

  void toggleDecorSelection(String decorId) {
  // Try to find the decor in the editing buffer
  PlacedDecor? decor;
  try {
    decor = editingDecors.firstWhere((d) => d.id == decorId);
  } catch (e) {
    decor = null;
  }

  // If found, toggle its selection
  if (decor != null) {
    decor.isSelected = !decor.isSelected;
    notifyListeners();
  }
}

void updateDecorPositionInBuffer(String decorId, double newX, double newY) {
    final decorIndex = editingDecors.indexWhere((d) => d.id == decorId);
    if (decorIndex == -1) return;

    final decor = editingDecors[decorIndex];
    editingDecors[decorIndex] = decor.copyWith(x: newX, y: newY);
    notifyListeners();
  }

void startMovingDecor(String decorId) {
  movingDecorId = decorId;
  notifyListeners(); // very important
}

void stopMovingDecor() {
  movingDecorId = null;
  notifyListeners();
}

  Future<void> deleteDecorInBuffer(String decorId, {bool refund = true}) async {
    if (!isInEditMode) return;
    final index = _editingBuffer.indexWhere((d) => d.id == decorId);
    if (index == -1) return;

    final toDelete = _editingBuffer.removeAt(index);
    await _repo.removePlacedDecor(currentChild.parentUid, currentChild.cid, decorId);

    if (refund) {
      final def = getDecorDefinition(toDelete.decorId);
      await _repo.refundBalance(currentChild.parentUid, currentChild.cid, def.price);
      _updateLocalBalance(currentChild.balance + def.price);
    }
    notifyListeners();
  }

  DecorDefinition getDecorDefinition(String decorId) {
    return DecorCatalog.all.firstWhere((d) => d.id == decorId);
  }

  Future<void> openEditModeForPlacement(String decorId) async {
    await _init();
    final decor = placedDecors.firstWhere((d) => d.decorId == decorId);
    enterEditMode(focusDecorId: decor.id);
  }

  
}
