import 'package:flutter/foundation.dart';
import '../models/assigned_cbt_model.dart';
import '../repositories/cbt_repository.dart';

class CBTProvider with ChangeNotifier {
  final CBTRepository _repository = CBTRepository();
  List<AssignedCBT> _assigned = [];

  List<AssignedCBT> get assigned => _assigned;

  /// Loads CBTs for a specific child (syncs Firestore → Hive → state)
  Future<void> loadCBT(String parentId, String childId) async {
    await _repository.syncFromFirestore(parentId, childId);
    _assigned = _repository.getLocalCBTs(childId);
    notifyListeners();
  }

  /// Marks a CBT exercise as completed for a child
  Future<void> markAsCompleted(String parentId, String childId, String cbtId) async {
    await _repository.updateCompletion(parentId, childId, cbtId);
    await loadCBT(parentId, childId); // Refresh list after update
  }

  /// Assigns a new CBT to a child (parent side)
  Future<void> assignCBT(String parentId, AssignedCBT cbt) async {
    await _repository.addAssignedCBT(parentId, cbt);
    _assigned.add(cbt);
    notifyListeners();
  }

  /// Returns a specific CBT by ID (for details page)
  AssignedCBT? getCBTById(String id) {
    try {
      return _assigned.firstWhere((cbt) => cbt.id == id);
    } catch (_) {
      return null;
    }
  }

  /// Clears cache when user logs out or switches child
  void clear() {
    _assigned = [];
    notifyListeners();
  }
}
