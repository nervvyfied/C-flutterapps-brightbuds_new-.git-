import 'package:brightbuds_new/aquarium/progression/achievement_resolver.dart';
import 'package:brightbuds_new/data/models/journal_model.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/achievement_definition.dart';
import '../notifiers/achievement_notifier.dart';
import '/data/models/child_model.dart';
import '/data/models/task_model.dart';

class AchievementManager {
  final AchievementNotifier achievementNotifier;
  final ChildUser child;
  final FirebaseFirestore firestore = FirebaseFirestore.instance;
  final Set<String> _alreadyUnlockedCache = {};

  AchievementManager({
    required this.achievementNotifier,
    required this.child,
  });

  Future<void> check({
  required List<TaskModel> tasks,
  required List<JournalEntry> journals,
}) async {
  final resolver = AchievementResolver(
    child: child,
    tasks: tasks,
    journals: journals,
  );

  final newAchievements = resolver.unlockedAchievements;

  if (newAchievements.isEmpty) return;

  for (final achievement in newAchievements) {
    if (!child.unlockedAchievements.contains(achievement.id)) {
      child.unlockedAchievements.add(achievement.id);

      // ✅ Update notifier immediately so UI unlocks instantly
      achievementNotifier.setUnlocked(achievement);

      // ✅ Persist to Firestore using correct field name
      await FirebaseFirestore.instance
          .collection('users')
          .doc(child.parentUid)
          .collection('children')
          .doc(child.cid)
          .update({'unlockedAchievements': child.unlockedAchievements});
    }
  }
}

  /// Call this whenever relevant data changes (XP, level, journal, tasks)
  Future<void> checkAchievements() async {
    // Fetch everything once
    final tasksSnap = await firestore
        .collection('users')
        .doc(child.parentUid)
        .collection('children')
        .doc(child.cid)
        .collection('tasks')
        .get();

    final tasks = tasksSnap.docs
        .map((d) => TaskModel.fromFirestore(d.data(), d.id))
        .toList();

    final journalsSnap = await firestore
        .collection('users')
        .doc(child.parentUid)
        .collection('children')
        .doc(child.cid)
        .collection('journals')
        .get();

    final journals = journalsSnap.docs
        .map((d) => JournalEntry.fromMap(d.data()))
        .toList();

    final resolver = AchievementResolver(
        child: child,
        tasks: tasks,
        journals: journals, // you might extend resolver to accept journals
    );

    final newAchievements = resolver.unlockedAchievements;

    for (var achievement in newAchievements) {
      await saveAchievementForChild(child, achievement.id);
      achievementNotifier.setUnlocked(achievement);
    }
  }

  bool achievementUnlocked(AchievementDefinition achievement) {
    return child.unlockedAchievements.contains(achievement.id);
  }

  Future<void> saveAchievementForChild(ChildUser child, String achievementId) async {
    if (!child.unlockedAchievements.contains(achievementId)) {
      child.unlockedAchievements.add(achievementId);
      await firestore
        .collection('users')
        .doc(child.parentUid)
        .collection('children')
        .doc(child.cid)
        .update({'unlockedAchievements': child.unlockedAchievements});
    }
  }

  // ------------------- Dynamic fetch functions -------------------

  Future<int> fetchCurrentXP() async {
    return child.xp;
  }

  Future<int> fetchCurrentLevel() async {
    return child.xp ~/ 100;
  }

  Future<int> fetchHappyJournalEntries() async {
    final snap = await firestore
        .collection('users')
        .doc(child.parentUid)
        .collection('children')
        .doc(child.cid)
        .collection('journals')
        .where('mood', isEqualTo: 'happy')
        .get();
    return snap.docs.length;
  }

  Future<int> fetchHardTasksDone() async {
    final snap = await firestore
        .collection('users')
        .doc(child.parentUid)
        .collection('children')
        .doc(child.cid)
        .collection('tasks')
        .get();

    return snap.docs
        .map((d) => TaskModel.fromFirestore(d.data(), d.id))
        .where((t) => t.difficulty.toLowerCase() == 'hard' && t.isDone)
        .length;
  }
}
