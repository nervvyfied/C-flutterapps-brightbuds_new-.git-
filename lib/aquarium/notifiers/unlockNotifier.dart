import 'package:flutter/material.dart';
import '../models/fish_definition.dart';

class UnlockNotifier extends ChangeNotifier {
  FishDefinition? _lastUnlocked;

  FishDefinition? get lastUnlocked => _lastUnlocked;

  void notifyUnlock(FishDefinition fish) {
    _lastUnlocked = fish;
    notifyListeners();
  }

  void clear() {
    _lastUnlocked = null;
    notifyListeners();
  }
}
