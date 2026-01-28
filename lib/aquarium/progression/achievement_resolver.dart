import 'package:brightbuds_new/aquarium/models/achievement_definition.dart';
import 'package:brightbuds_new/data/models/child_model.dart';
import 'package:brightbuds_new/data/models/journal_model.dart';
import 'package:brightbuds_new/data/models/task_model.dart';

class AchievementResolver {
  final ChildUser child;
  final List<TaskModel> tasks;
  final List<JournalEntry> journals;

  AchievementResolver({required this.child, required this.tasks, required this.journals});

  List<AchievementDefinition> get unlockedAchievements {
    final List<AchievementDefinition> newAchievements = [];

    for (var achievement in AchievementsCatalog.all) {
      if (child.unlockedAchievements.contains(achievement.id)) continue;

      switch (achievement.type) {
        case AchievementType.xp:
          if (child.xp >= achievement.threshold) newAchievements.add(achievement);
          break;
        case AchievementType.level:
          if ((child.xp ~/ 100) >= achievement.threshold) newAchievements.add(achievement);
          break;
        case AchievementType.happy:
          final happyCount = journals.where((j) => j.mood.trim().toLowerCase() == 'happy').length;
          if (happyCount >= achievement.threshold) newAchievements.add(achievement);
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
