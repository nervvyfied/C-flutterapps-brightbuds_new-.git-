import 'package:brightbuds_new/aquarium/models/achievement_definition.dart';
import 'package:brightbuds_new/data/models/child_model.dart';
import 'package:flutter/material.dart';

class AchievementNotifier extends ChangeNotifier {
  AchievementDefinition? _justUnlocked;
  final Set<String> _unlockedIds = {};

  AchievementDefinition? get justUnlocked => _justUnlocked;
  Set<String> get unlockedIds => _unlockedIds;

  void setUnlocked(AchievementDefinition achievement) {
    if (_unlockedIds.contains(achievement.id)) return;
    _unlockedIds.add(achievement.id);
    _justUnlocked = achievement;
    notifyListeners();
  }

  void loadFromChild(ChildUser child) {
    _unlockedIds
      ..clear()
      ..addAll(child.unlockedAchievements);
    WidgetsBinding.instance.addPostFrameCallback((_) => notifyListeners());
  }

  void markUnlocked(String achievementId) {
    if (_unlockedIds.add(achievementId)) {
      notifyListeners();
    }
  }

  void clear() {
    _justUnlocked = null;
    notifyListeners();
  }
}
