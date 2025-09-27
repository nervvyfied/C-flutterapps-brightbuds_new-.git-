import 'package:flutter/foundation.dart';

class SelectedChildProvider extends ChangeNotifier {
  Map<String, dynamic>? _selectedChild;

  Map<String, dynamic>? get selectedChild => _selectedChild;

  void setSelectedChild(Map<String, dynamic>? child) {
    _selectedChild = child;
    notifyListeners();
  }

  void updateSelectedChild(Map<String, dynamic> updatedFields) {
    if (_selectedChild != null) {
      _selectedChild!.addAll(updatedFields);
      notifyListeners();
    }
  }

  void clearSelectedChild() {
    _selectedChild = null;
    notifyListeners();
  }

  bool get hasSelectedChild => _selectedChild != null;
}
