import 'package:flutter/foundation.dart';

class SelectedChildProvider extends ChangeNotifier {
  Map<String, dynamic>? _selectedChild;

  Map<String, dynamic>? get selectedChild => _selectedChild;

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

  /// Returns true if a child is selected.
  bool get hasSelectedChild => _selectedChild != null;
}
