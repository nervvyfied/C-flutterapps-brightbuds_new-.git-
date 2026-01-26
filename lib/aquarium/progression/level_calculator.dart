class LevelCalculator {
  final int xpPerLevel;

  LevelCalculator({this.xpPerLevel = 100});

  int calculateLevel(int totalXp) =>
      (totalXp / xpPerLevel).floor() + 1;

  int xpForNextLevel(int totalXp) {
    final level = calculateLevel(totalXp);
    return level * xpPerLevel - totalXp;
  }

  int xpFromTask(String difficulty) {
    switch (difficulty) {
      case 'easy':
        return 5;
      case 'medium':
        return 10;
      case 'hard':
        return 20;
      default:
        return 5;
    }
  }

  /// NEW — total XP required to reach a given level
  int xpForLevel(int level) {
    return (level - 1) * xpPerLevel;
  }
}

