// ignore_for_file: deprecated_member_use
import 'dart:math';

import 'package:brightbuds_new/aquarium/manager/achievement_manager.dart';
import 'package:brightbuds_new/aquarium/notifiers/achievement_notifier.dart';
import 'package:brightbuds_new/aquarium/notifiers/unlockNotifier.dart';
import 'package:brightbuds_new/data/models/child_model.dart';
import 'package:brightbuds_new/data/models/journal_model.dart';
import 'package:brightbuds_new/data/models/task_model.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/achievement_definition.dart';

class AchievementPage extends StatefulWidget {
  final ChildUser child;
  final List<TaskModel> tasks;
  final List<JournalEntry> journals;

  const AchievementPage({
    super.key,
    required this.child,
    required this.tasks,
    required this.journals,
  });

  @override
  State<AchievementPage> createState() => _AchievementPageState();
}

class _AchievementPageState extends State<AchievementPage> {
  late final AchievementNotifier achievementNotifier;

  @override
  void initState() {
    super.initState();
    achievementNotifier = context.read<AchievementNotifier>();
  }

  Stream<ChildUser> childStream() => FirebaseFirestore.instance
      .collection('users')
      .doc(widget.child.parentUid)
      .collection('children')
      .doc(widget.child.cid)
      .snapshots()
      .map((snap) => ChildUser.fromMap(snap.data()!, snap.id));

  Stream<List<TaskModel>> tasksStream(String parentUid, String childId) =>
      FirebaseFirestore.instance
          .collection('users')
          .doc(parentUid)
          .collection('children')
          .doc(childId)
          .collection('tasks')
          .snapshots()
          .map((snap) =>
              snap.docs.map((d) => TaskModel.fromFirestore(d.data(), d.id)).toList());

  Stream<List<JournalEntry>> journalsStream(String parentUid, String childId) =>
      FirebaseFirestore.instance
          .collection('users')
          .doc(parentUid)
          .collection('children')
          .doc(childId)
          .collection('journals')
          .snapshots()
          .map((snap) => snap.docs.map((d) => JournalEntry.fromMap(d.data())).toList());

  void _runAchievementCheck(ChildUser child, List<TaskModel> tasks, List<JournalEntry> journals) {
    // Always run when streams update
    AchievementManager(
      achievementNotifier: achievementNotifier,
      child: child,
    ).check(tasks: tasks, journals: journals);
  }

  @override
  Widget build(BuildContext context) {
    final allAchievements = AchievementsCatalog.all;
    final unlockNotifier = context.watch<UnlockNotifier>();

    return Scaffold(
      appBar: AppBar(title: const Text('Milestones & Achievements')),
      body: StreamBuilder<ChildUser>(
        stream: childStream(),
        builder: (context, childSnap) {
          if (!childSnap.hasData) return const Center(child: CircularProgressIndicator());
          final child = childSnap.data!;

          return StreamBuilder<List<TaskModel>>(
            stream: tasksStream(child.parentUid, child.cid),
            builder: (context, taskSnap) {
              if (!taskSnap.hasData) return const Center(child: CircularProgressIndicator());
              final tasks = taskSnap.data!;

              WidgetsBinding.instance.addPostFrameCallback((_) {
                achievementNotifier.loadFromChild(child);
              });

              return StreamBuilder<List<JournalEntry>>(
                stream: journalsStream(child.parentUid, child.cid),
                builder: (context, journalSnap) {
                  if (!journalSnap.hasData) return const Center(child: CircularProgressIndicator());
                  final journals = journalSnap.data!;

                  // ✅ Run achievements check on every stream update
                  _runAchievementCheck(child, tasks, journals);

                  final unlockedIds = context.watch<AchievementNotifier>().unlockedIds;

                   return ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: allAchievements.length,
              itemBuilder: (context, index) {
                final achievement = allAchievements[index];

                final isJustUnlocked = unlockNotifier.current?.id == achievement.id;

                Widget buildCard() {
                  final isUnlocked = unlockedIds.contains(achievement.id);

                  final progressPercent = _calculateProgressPercent(achievement, child, tasks, journals);
                  final progressText = _getProgressText(achievement, child, tasks, journals);

                  return Card(
                    elevation: 3,
                    margin: const EdgeInsets.symmetric(vertical: 8),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          Image.asset(
                            achievement.iconAsset,
                            width: 60,
                            height: 60,
                            color: isUnlocked ? null : Colors.grey,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  achievement.title,
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: isUnlocked ? Colors.black : Colors.grey,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  achievement.description,
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: isUnlocked ? Colors.black : Colors.grey,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(6),
                                  child: LinearProgressIndicator(
                                    value: progressPercent,
                                    minHeight: 10,
                                    backgroundColor: Colors.grey.shade300,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                        isUnlocked ? Colors.green : Colors.blue),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  progressText,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: isUnlocked ? Colors.green : Colors.grey,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Icon(
                            isUnlocked ? Icons.check_circle : Icons.lock,
                            color: isUnlocked ? Colors.green : Colors.grey,
                            size: 28,
                          ),
                        ],
                      ),
                    ),
                  );
                }

    // Glow animation
                      if (isJustUnlocked) {
                  return TweenAnimationBuilder<double>(
                    duration: const Duration(seconds: 2),
                    curve: Curves.easeInOut,
                    tween: Tween(begin: 0.0, end: 20.0),
                    onEnd: () => context.read<UnlockNotifier>().clearCurrent(),
                    builder: (context, glow, childWidget) {
                      return Container(
                        decoration: BoxDecoration(
                          boxShadow: [
                            BoxShadow(
                              color: Colors.yellow.withOpacity(0.6),
                              blurRadius: glow,
                              spreadRadius: glow / 2,
                            ),
                          ],
                        ),
                        child: Builder(
                          builder: (_) => buildCard(),
                        ),
                      );
                    },
                  );
                } else {
                  return buildCard();
                      }
                    },
                  );
                },
              );
            },
          );
        },
      ),
    );
  }

  double _calculateProgressPercent(AchievementDefinition achievement, ChildUser child,
      List<TaskModel> tasks, List<JournalEntry> journals) {
    final level = (child.xp ~/ 100) + 1;
    final happyCount = journals.where((j) => j.mood.toLowerCase() == 'happy').length;
    final completedHardTasks =
        tasks.where((t) => t.isDone && t.difficulty.toLowerCase() == 'hard').length;

    switch (achievement.type) {
      case AchievementType.xp:
        return (child.xp / achievement.threshold).clamp(0.0, 1.0);
      case AchievementType.level:
        return (level / achievement.threshold).clamp(0.0, 1.0);
      case AchievementType.happy:
        return (happyCount / achievement.threshold).clamp(0.0, 1.0);
      case AchievementType.taskHard:
        return (completedHardTasks / achievement.threshold).clamp(0.0, 1.0);
    }
  }

  String _getProgressText(
    AchievementDefinition achievement,
    ChildUser child,
    List<TaskModel> tasks,
    List<JournalEntry> journals,
) {
  final level = (child.xp ~/ 100) + 1;
  final happyCount = journals.where((j) => j.mood.trim().toLowerCase() == 'happy').length;
  final completedHardTasks =
      tasks.where((t) => t.isDone && t.difficulty.toLowerCase() == 'hard').length;

  switch (achievement.type) {
    case AchievementType.xp:
      return '${min(child.xp, achievement.threshold)} / ${achievement.threshold} XP';
    case AchievementType.level:
      return 'Level ${min(level, achievement.threshold)} / ${achievement.threshold}';
    case AchievementType.happy:
      return '${min(happyCount, achievement.threshold)} / ${achievement.threshold} days';
    case AchievementType.taskHard:
      return '${min(completedHardTasks, achievement.threshold)} / ${achievement.threshold} hard tasks';
  }
}
}
