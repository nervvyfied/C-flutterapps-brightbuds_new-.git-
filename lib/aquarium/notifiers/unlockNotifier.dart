import 'package:flutter/material.dart';
import '../models/fish_definition.dart';

class UnlockNotifier extends ChangeNotifier {
  FishDefinition? _justUnlocked;

  FishDefinition? get justUnlocked => _justUnlocked;

  void setUnlocked(FishDefinition fish) {
    _justUnlocked = fish;
    notifyListeners();
  }

  void clear() {
    _justUnlocked = null;
    notifyListeners();
  }
}
