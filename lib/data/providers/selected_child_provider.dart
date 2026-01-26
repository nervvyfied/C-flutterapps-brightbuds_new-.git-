import 'package:flutter/foundation.dart';

class SelectedChildProvider with ChangeNotifier {
  Map<String, dynamic>? _selectedChild;

  Map<String, dynamic>? get selectedChild => _selectedChild;

  void setSelectedChild(Map<String, dynamic>? child) {
    debugPrint(
      "👶 Setting selected child: ${child?['name']} (${child?['cid']})",
    );

    // Validate the child data
    if (child != null) {
      final childId = child['cid']?.toString();
      if (childId == null || childId.isEmpty) {
        debugPrint("⚠️ Invalid child ID in setSelectedChild");
        _selectedChild = null;
      } else {
        _selectedChild = child;
      }
    } else {
      _selectedChild = null;
    }

    notifyListeners();
  }

  void clearSelectedChild() {
    _selectedChild = null;
    notifyListeners();
  }

  /// Update specific fields of the selected child
  void updateSelectedChild(Map<String, dynamic> updatedFields) {
    if (_selectedChild == null) {
      debugPrint('⚠️ updateSelectedChild called but no child selected');
      return;
    }
  }
}
