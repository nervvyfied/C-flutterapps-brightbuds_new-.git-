import 'package:flutter/material.dart';
import '../models/fish_definition.dart';
import '../models/decor_definition.dart';
import '../models/achievement_definition.dart';

/// Holds the latest unlocked item (Fish, Decor, or Achievement) for dialogs
class UnlockNotifier extends ChangeNotifier {
  final List<dynamic> _queue = []; // queue of unlocks
  bool _isShowing = false;
  dynamic _lastUnlocked; // FishDefinition, DecorDefinition, or AchievementDefinition

  //dynamic get lastUnlocked => _lastUnlocked;
  dynamic get current => _queue.isNotEmpty ? _queue.first : null;

  void setUnlocked(dynamic item) {
    _queue.add(item);
    if (!_isShowing) {
      _showNext();
    }
  }

  /// Called after a dialog is closed
  void clearCurrent() {
    if (_queue.isNotEmpty) {
      _queue.removeAt(0);
    }
    _isShowing = false;
    _showNext();
  }

  /// Internal: show next unlock if queue is not empty
  void _showNext() {
    if (_queue.isNotEmpty) {
      _isShowing = true;
      notifyListeners(); // triggers UnlockListener
    }
  }
}
