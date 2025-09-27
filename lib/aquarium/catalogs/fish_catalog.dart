import '../models/fish_definition.dart'; // adjust path as needed

// Hardcoded Fish Definitions for MVP
const List<FishDefinition> fishCatalog = [
  FishDefinition(
    id: "fish1",
    name: "Blue Fish",
    assetPath: "assets/fishes/fish1.png",
    unlockConditionId: "first_task",
    description: "Your very first fish! A simple blue fish to start your journey.",
  ),
  FishDefinition(
    id: "fish2",
    name: "Green Fish",
    assetPath: "assets/fishes/fish2.png",
    unlockConditionId: "daily_starter",
    description: "Keep it up! You’re on a 3-day streak!",
  ),
  FishDefinition(
    id: "fish3",
    name: "Red Fish",
    assetPath: "assets/fishes/fish3.png",
    unlockConditionId: "streak_builder",
    description: "7-day streak achieved! Look at this bright red reward.",
  ),
  FishDefinition(
    id: "fish4",
    name: "Pink Fish",
    assetPath: "assets/fishes/fish4.png",
    unlockConditionId: "consistency_master",
    description: "14-day streak! Your consistency shines.",
  ),
  FishDefinition(
    id: "fish5",
    name: "Orange Fish / Goldfish",
    assetPath: "assets/fishes/fish5.png",
    unlockConditionId: "task_collector",
    description: "Completed 25 tasks! Goldfish say congrats!",
  ),
  FishDefinition(
    id: "fish6",
    name: "Pufferfish",
    assetPath: "assets/fishes/fish6.png",
    unlockConditionId: "task_expert",
    description: "50 tasks completed! Puff up with pride.",
  ),
  FishDefinition(
    id: "fish7",
    name: "Clownfish",
    assetPath: "assets/fishes/fish7.png",
    unlockConditionId: "mood_tracker",
    description: "Logged moods for 5 days! Bright and cheerful!",
  ),
  FishDefinition(
    id: "fish8",
    name: "Green Fish w/ Red Line & Cream Belly",
    assetPath: "assets/fishes/fish8.png",
    unlockConditionId: "mood_explorer",
    description: "Explored 3 different moods! Colorful variety!",
  ),
  FishDefinition(
    id: "fish9",
    name: "Angelfish",
    assetPath: "assets/fishes/fish9.png",
    unlockConditionId: "big_helper",
    description: "Completed all tasks in a week! You’re an angel helper!",
  ),
  FishDefinition(
    id: "fish10",
    name: "Dory",
    assetPath: "assets/fishes/fish10.png",
    unlockConditionId: "focus_star",
    description: "Finished 5 focus sessions! Keep your eyes on the prize.",
  ),
  FishDefinition(
    id: "fish11",
    name: "Turtle",
    assetPath: "assets/fishes/fish11.png",
    unlockConditionId: "aquarium_designer",
    description: "Placed decoration 5 times! Steady caretaker vibes.",
  ),
  FishDefinition(
    id: "fish12",
    name: "Red Seahorse",
    assetPath: "assets/fishes/fish12.png",
    unlockConditionId: "going_strong",
    description: "Completed 10 hard tasks! Strong and resilient like a seahorse.",
  ),
];
