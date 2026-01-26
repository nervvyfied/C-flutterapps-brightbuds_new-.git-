import 'package:brightbuds_new/aquarium/models/achievement_definition.dart';
import 'package:brightbuds_new/data/models/child_model.dart';
import 'package:brightbuds_new/data/models/task_model.dart';

class AchievementResolver {
  final ChildUser child;
  final List<TaskModel> tasks;

  AchievementResolver({required this.child, required this.tasks});

  List<AchievementDefinition> get unlockedAchievements {
    final List<AchievementDefinition> newAchievements = [];

    for (var achievement in AchievementsCatalog.all) {
      if (child.unlockedAchievements.contains(achievement.id)) continue;

      switch (achievement.type) {
        case AchievementType.xp:
          if (child.xp >= achievement.threshold) newAchievements.add(achievement);
          break;
        case AchievementType.level:
          if (child.level >= achievement.threshold) newAchievements.add(achievement);
          break;
        case AchievementType.happy:
          if (child.streak >= achievement.threshold) newAchievements.add(achievement);
          break;
        case AchievementType.taskHard:
          final completed = tasks.where((t) => t.isDone && t.difficulty.toLowerCase() == 'hard').length;
          if (completed >= achievement.threshold) newAchievements.add(achievement);
          break;
      }
    }

    return newAchievements;
  }
}
