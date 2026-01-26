import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/achievement_definition.dart';
import '../notifiers/achievement_notifier.dart';
import '/data/models/child_model.dart';
import '/data/models/task_model.dart';

class AchievementManager {
  final AchievementNotifier achievementNotifier;
  final ChildUser currentChild;
  final FirebaseFirestore firestore = FirebaseFirestore.instance;

  AchievementManager({
    required this.achievementNotifier,
    required this.currentChild,
  });

  /// Call this whenever relevant data changes (XP, level, journal, tasks)
  Future<void> checkAchievements() async {
    final achievements = AchievementsCatalog.all; // your static badges

    // Fetch dynamic data needed for achievements
    final xp = await fetchCurrentXP();
    final level = await fetchCurrentLevel();
    final happyEntries = await fetchHappyJournalEntries();
    final hardTasksDone = await fetchHardTasksDone();

    for (var achievement in achievements) {
      if (achievementUnlocked(achievement)) continue;

      bool shouldUnlock = false;

      switch (achievement.id) {
        case 'xp_100':
          shouldUnlock = xp >= 100;
          break;
        case 'level_5':
          shouldUnlock = level >= 5;
          break;
        case 'happy_10':
          shouldUnlock = happyEntries >= 10;
          break;
        case 'complete_10_hard':
          shouldUnlock = hardTasksDone >= 10;
          break;
      }

      if (shouldUnlock) {
        await saveAchievementForChild(currentChild, achievement.id);
        achievementNotifier.setUnlocked(achievement);
      }
    }
  }

  bool achievementUnlocked(AchievementDefinition achievement) {
    return currentChild.unlockedAchievements.contains(achievement.id);
  }

  Future<void> saveAchievementForChild(ChildUser child, String achievementId) async {
    if (!child.unlockedAchievements.contains(achievementId)) {
      child.unlockedAchievements.add(achievementId);
      await firestore
          .collection('users')
          .doc(child.parentUid)
          .collection('children')
          .doc(child.cid)
          .update({'achievements': child.unlockedAchievements});
    }
  }

  // ------------------- Dynamic fetch functions -------------------

  Future<int> fetchCurrentXP() async {
    return currentChild.xp;
  }

  Future<int> fetchCurrentLevel() async {
    return currentChild.level;
  }

  Future<int> fetchHappyJournalEntries() async {
    final snap = await firestore
        .collection('users')
        .doc(currentChild.parentUid)
        .collection('children')
        .doc(currentChild.cid)
        .collection('journals')
        .where('mood', isEqualTo: 'happy')
        .get();
    return snap.docs.length;
  }

  Future<int> fetchHardTasksDone() async {
    final snap = await firestore
        .collection('users')
        .doc(currentChild.parentUid)
        .collection('children')
        .doc(currentChild.cid)
        .collection('tasks')
        .get();

    return snap.docs
        .map((d) => TaskModel.fromFirestore(d.data(), d.id))
        .where((t) => t.difficulty.toLowerCase() == 'hard' && t.isDone)
        .length;
  }
}
