// ignore_for_file: deprecated_member_use
import 'package:brightbuds_new/aquarium/manager/unlockManager.dart';
import 'package:brightbuds_new/aquarium/notifiers/unlockNotifier.dart';
import 'package:brightbuds_new/data/models/child_model.dart';
import 'package:brightbuds_new/data/models/task_model.dart';
import 'package:brightbuds_new/data/providers/selected_child_provider.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/achievement_definition.dart';

class AchievementPage extends StatefulWidget {
  final ChildUser child;
  final List<TaskModel> tasks;

  const AchievementPage({
    super.key,
    required this.child,
    required this.tasks,
  });

  @override
  State<AchievementPage> createState() => _AchievementPageState();
}

class _AchievementPageState extends State<AchievementPage> {
  late UnlockManager unlockManager;

  @override
  void initState() {
    super.initState();
    final unlockNotifier = context.read<UnlockNotifier>();
    final childProvider = context.read<SelectedChildProvider>();
    unlockManager = UnlockManager(
      childProvider: childProvider, // Not needed if we only want visual unlocks
      unlockNotifier: unlockNotifier,
    );

    // Check achievement unlocks based on current child and tasks
    unlockManager.checkAchievementUnlocks(widget.tasks, widget.child);
  }

  ChildUser get child => widget.child;

  List<TaskModel> get tasks => widget.tasks;

  @override
  Widget build(BuildContext context) {
    final allAchievements = AchievementsCatalog.all;
    final unlockNotifier = context.watch<UnlockNotifier>();

    // 🔹 Compute unlocked IDs dynamically
    final unlockedIds = <String>{};
    for (var achievement in allAchievements) {
      switch (achievement.type) {
        case AchievementType.xp:
          if (child.xp >= achievement.threshold) unlockedIds.add(achievement.id);
          break;
        case AchievementType.level:
          if (child.level >= achievement.threshold) unlockedIds.add(achievement.id);
          break;
        case AchievementType.happy:
          if (child.streak >= achievement.threshold) unlockedIds.add(achievement.id);
          break;
        case AchievementType.taskHard:
          final completed = tasks
              .where((t) => t.isDone && t.difficulty.toLowerCase() == 'hard')
              .length;
          if (completed >= achievement.threshold) unlockedIds.add(achievement.id);
          break;
      }
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Milestones & Achievements')),
      body: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: allAchievements.length,
        itemBuilder: (context, index) {
          final achievement = allAchievements[index];
          final isUnlocked = unlockedIds.contains(achievement.id);
          final isJustUnlocked = unlockNotifier.current?.id == achievement.id;

          double progressPercent = _calculateProgressPercent(achievement);
          String progressText = _getProgressText(achievement, progressPercent);

          Widget card = Card(
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

          // Add glow animation if just unlocked
          if (isJustUnlocked) {
            return TweenAnimationBuilder<double>(
              duration: const Duration(seconds: 2),
              curve: Curves.easeInOut,
              tween: Tween(begin: 0.0, end: 20.0),
              onEnd: () {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  context.read<UnlockNotifier>().clearCurrent();
                });
              },
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
                  child: childWidget,
                );
              },
              child: card,
            );
          } else {
            return card;
          }
        },
      ),
    );
  }

  double _calculateProgressPercent(AchievementDefinition achievement) {
    switch (achievement.type) {
      case AchievementType.xp:
        return (child.xp / achievement.threshold).clamp(0.0, 1.0);
      case AchievementType.level:
        return (child.level / achievement.threshold).clamp(0.0, 1.0);
      case AchievementType.happy:
        return (child.streak / achievement.threshold).clamp(0.0, 1.0);
      case AchievementType.taskHard:
        final completed = tasks
            .where((t) => t.isDone && t.difficulty.toLowerCase() == 'hard')
            .length;
        return (completed / achievement.threshold).clamp(0.0, 1.0);
    }
  }

  String _getProgressText(AchievementDefinition achievement, double progress) {
    switch (achievement.type) {
      case AchievementType.xp:
        return '${child.xp} / ${achievement.threshold} XP';
      case AchievementType.level:
        return 'Level ${child.level} / ${achievement.threshold}';
      case AchievementType.happy:
        return '${child.streak} / ${achievement.threshold} days';
      case AchievementType.taskHard:
        final completed = tasks
            .where((t) => t.isDone && t.difficulty.toLowerCase() == 'hard')
            .length;
        return '$completed / ${achievement.threshold} hard tasks';
    }
  }
}
