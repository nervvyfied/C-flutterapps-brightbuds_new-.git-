import 'package:flutter/material.dart';

enum AchievementType {
  xp,          // XP milestone
  level,       // Level reached
  happy,      // Task streak
  taskHard // Task-specific milestones
}

class AchievementDefinition {
  final String id;
  final String title;
  final String description;
  final AchievementType type;
  final int threshold; // XP, level, streak, or task count
  final String iconAsset;

  const AchievementDefinition({
    required this.id,
    required this.title,
    required this.description,
    required this.type,
    required this.threshold,
    required this.iconAsset,
  });
}

// Example Achievements
class AchievementsCatalog {
  static const all = [
    AchievementDefinition(
      id: 'xp_100',
      title: 'Rising Star',
      description: 'Earn 100 XP',
      type: AchievementType.xp,
      threshold: 100,
      iconAsset: 'assets/badge.png',
    ),
    AchievementDefinition(
      id: 'level_5',
      title: 'Level Up!',
      description: 'Reach Level 5',
      type: AchievementType.level,
      threshold: 5,
      iconAsset: 'assets/badge.png',
    ),
    AchievementDefinition(
      id: 'happy_10',
      title: 'Happy Camper',
      description: 'Make 10 happy journal entries',
      type: AchievementType.happy,
      threshold: 10,
      iconAsset: 'assets/badge.png',
    ),
    AchievementDefinition(
      id: 'complete_10_hard',
      title: 'Hard Worker',
      description: 'Complete 10 hard tasks',
      type: AchievementType.taskHard,
      threshold: 10,
      iconAsset: 'assets/badge.png',
    ),
  ];
}
