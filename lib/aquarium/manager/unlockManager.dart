import 'package:brightbuds_new/aquarium/notifiers/unlockNotifier.dart';
import 'package:brightbuds_new/aquarium/progression/achievement_resolver.dart';
import 'package:brightbuds_new/aquarium/progression/world_progression.dart';
import 'package:brightbuds_new/data/models/child_model.dart';
import 'package:brightbuds_new/data/models/task_model.dart';
import 'package:brightbuds_new/data/repositories/user_repository.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:brightbuds_new/data/providers/selected_child_provider.dart';
import '../progression/unlock_resolver.dart';
import '../models/fish_definition.dart';
import '../models/decor_definition.dart';

class UnlockManager extends ChangeNotifier {
  final UserRepository _userRepo = UserRepository();
  final SelectedChildProvider childProvider;
  final UnlockNotifier unlockNotifier;

  UnlockManager({required this.childProvider, required this.unlockNotifier});

  /// Tracks the most recently unlocked fish or decor
  FishDefinition? _lastFishUnlocked;
  DecorDefinition? _lastDecorUnlocked;

  FishDefinition? get lastFishUnlocked => _lastFishUnlocked;
  DecorDefinition? get lastDecorUnlocked => _lastDecorUnlocked;

  /// Call this after the child completes a level
  void checkLevelUnlocks(int currentLevel) {
    final selectedChild = childProvider.selectedChild;
    if (selectedChild == null) return;

    final world = Worlds.getWorldForLevel(currentLevel);

    // Use Sets for uniqueness
    final unlockedFishSet = Set<String>.from(selectedChild['unlockedFish'] ?? []);
    final unlockedDecorSet = Set<String>.from(selectedChild['unlockedDecor'] ?? []);

    final resolver = UnlockResolver(
      currentLevel: currentLevel,
      currentWorld: world.worldId,
    );

    FishDefinition? fishToUnlock;
    DecorDefinition? decorToUnlock;

    // Find the first new fish
    for (var fish in resolver.unlockedFish) {
      if (!unlockedFishSet.contains(fish.id)) {
        fishToUnlock = fish;
        break;
      }
    }

    // If no fish, find the first new decor
    if (fishToUnlock == null) {
      for (var decor in resolver.unlockedDecor) {
        if (!unlockedDecorSet.contains(decor.id)) {
          decorToUnlock = decor;
          break;
        }
      }
    }

    // Only trigger unlock if it's genuinely new
    if (fishToUnlock != null && _lastFishUnlocked?.id != fishToUnlock.id) {
      _lastFishUnlocked = fishToUnlock;
      unlockedFishSet.add(fishToUnlock.id);
      unlockNotifier.setUnlocked(fishToUnlock);
    } else if (decorToUnlock != null && _lastDecorUnlocked?.id != decorToUnlock.id) {
      _lastDecorUnlocked = decorToUnlock;
      unlockedDecorSet.add(decorToUnlock.id);
      unlockNotifier.setUnlocked(decorToUnlock);
    }

    // Persist changes if any unlock happened
    if (_lastFishUnlocked != null || _lastDecorUnlocked != null) {
      childProvider.updateSelectedChild({
        ...selectedChild,
        'unlockedFish': unlockedFishSet.toList(),
        'unlockedDecor': unlockedDecorSet.toList(),
      });

      notifyListeners();
      debugPrint('✅ Unlock triggered: ${_lastFishUnlocked?.name ?? _lastDecorUnlocked?.name}');
    }
  }

  /// Clear last unlock after showing popup
  void clearLastUnlock() {
    _lastFishUnlocked = null;
    _lastDecorUnlocked = null;
    notifyListeners();
  }

  void checkAchievementUnlocks(List<TaskModel> tasks, ChildUser child) {
  final childUser = childProvider.selectedChildAsUser;
  if (childUser == null) return;

  final resolver = AchievementResolver(child: childUser, tasks: tasks);
  final newAchievements = resolver.unlockedAchievements;

  if (newAchievements.isNotEmpty) {
    // Deduplicate
    final updatedAchievements = {
      ...childUser.unlockedAchievements,
      ...newAchievements.map((a) => a.id),
    }.toList();

    childProvider.updateSelectedChild({'unlockedAchievements': updatedAchievements});

    // Enqueue achievements for dialogs one by one
    for (var achievement in newAchievements) {
      unlockNotifier.setUnlocked(achievement);
      saveUnlockedAchievement(childUser, achievement.id);
    }
  }
}


Future<void> saveUnlockedAchievement(ChildUser child, String achievementId) async {
    if (!child.unlockedAchievements.contains(achievementId)) {
      child.unlockedAchievements.add(achievementId);

      // Update Hive cache
      await _userRepo.cacheChild(child);

      // Update Firestore
      await _userRepo.updateChildAchievements(child.parentUid, child.cid, child.unlockedAchievements);
    }
  }
  /// Returns the current last unlock (fish or decor)
  dynamic get lastUnlock => _lastFishUnlocked ?? _lastDecorUnlocked;

  Future<void> setFishNeglected(String fishId, bool value) async {
    final child = childProvider.selectedChild;
    if (child == null) return;

    // 1️⃣ Update in-memory state
    if (child['fishes'] != null) {
      final fish = child['fishes']
          .firstWhere((f) => f['id'] == fishId, orElse: () => null);
      if (fish != null) fish['neglected'] = value;
    }

    // 2️⃣ Persist to Firestore
    final parentUid = child['parentUid'];
    final cid = child['cid'];

    if (parentUid != null && cid != null) {
      final docRef = FirebaseFirestore.instance
          .collection('users')
          .doc(parentUid)
          .collection('children')
          .doc(cid);

      await docRef.update({
        'fishes.$fishId.neglected': value,
      });
    }
  }
}
