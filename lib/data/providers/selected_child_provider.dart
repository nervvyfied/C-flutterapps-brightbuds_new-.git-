import 'package:brightbuds_new/data/models/child_model.dart';
import 'package:brightbuds_new/data/repositories/user_repository.dart';
import 'package:flutter/foundation.dart';

class SelectedChildProvider extends ChangeNotifier {
  final UserRepository _userRepo = UserRepository();
  Map<String, dynamic>? _selectedChild;

  Map<String, dynamic>? get selectedChild => _selectedChild;

  ChildUser? get selectedChildAsUser {
    if (_selectedChild == null) return null;

    return ChildUser(
      cid: _selectedChild!['id'] ?? '',
      parentUid: _selectedChild!['parentUid'] ?? '',
      name: _selectedChild!['name'] ?? '',
      xp: _selectedChild!['xp'] ?? 0,
      level: _selectedChild!['level'] ?? 1,
      streak: _selectedChild!['streak'] ?? 0,
      unlockedAchievements: List<String>.from(
          _selectedChild!['unlockedAchievements'] ?? []),
    );
  }

  /// Sets the selected child and notifies listeners.
  void setSelectedChild(Map<String, dynamic>? child) {
    _selectedChild = child;
    if (child != null || _selectedChild == null) {
      notifyListeners();
    }
  }

  /// Updates specific fields of the selected child safely.
  void updateSelectedChild(Map<String, dynamic> updatedFields) {
    if (_selectedChild != null) {
      _selectedChild = {..._selectedChild!, ...updatedFields}; // safer merge
      notifyListeners();
    }
  }

  /// Clears the selected child.
  void clearSelectedChild() {
    _selectedChild = null;
    notifyListeners();
  }

  Future<void> fetchChildAndSet(String parentUid, String childId) async {
  final child = await _userRepo.fetchChildAndCache(parentUid, childId);
  if (child != null) {
    setSelectedChild({
      'id': child.cid,
      'parentUid': child.parentUid,
      'name': child.name,
      'xp': child.xp,
      'level': child.level,
      'streak': child.streak,
      'unlockedAchievements': child.unlockedAchievements,
    });
  }
}

  /// Returns true if a child is selected.
  bool get hasSelectedChild => _selectedChild != null;

  Future loadEntries() async {}
}