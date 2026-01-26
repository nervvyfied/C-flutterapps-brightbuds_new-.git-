import 'package:brightbuds_new/aquarium/manager/achievement_manager.dart';
import 'package:brightbuds_new/aquarium/progression/level_calculator.dart';
import 'package:brightbuds_new/aquarium/progression/unlock_resolver.dart';
import 'package:brightbuds_new/aquarium/progression/world_progression.dart';
import 'package:brightbuds_new/data/models/child_model.dart';
import 'package:flutter/foundation.dart';
import '../models/fish_definition.dart';
import '../models/decor_definition.dart';

/// Snapshot of a child's progression state
class ProgressionState {
  final int xp;
  final int level;
  final WorldProgression world;
  final List<FishDefinition> unlockedFish;
  final List<DecorDefinition> unlockedDecor;

  ProgressionState({
    required this.xp,
    required this.level,
    required this.world,
    required this.unlockedFish,
    required this.unlockedDecor,
  });

  ProgressionState copyWith({
    int? xp,
    int? level,
    WorldProgression? world,
    List<FishDefinition>? unlockedFish,
    List<DecorDefinition>? unlockedDecor,
  }) {
    return ProgressionState(
      xp: xp ?? this.xp,
      level: level ?? this.level,
      world: world ?? this.world,
      unlockedFish: unlockedFish ?? this.unlockedFish,
      unlockedDecor: unlockedDecor ?? this.unlockedDecor,
    );
  }
}

/// Provider that computes level, world, and unlocks from XP
class ProgressionProvider extends ChangeNotifier {
  final LevelCalculator _levelCalculator;
  ChildUser _child;

  VoidCallback? onLevelUp;
  int _lastLevel = 1;

  ProgressionState _state;
  ProgressionState get state => _state;
  final AchievementManager? achievementManager;

  ProgressionProvider({
    required ChildUser child,
    LevelCalculator? levelCalculator,
    this.achievementManager,
  })  : _child = child,
        _levelCalculator = levelCalculator ?? LevelCalculator(),
        _state = ProgressionState(
          xp: child.xp,
          level: 1,
          world: Worlds.getWorldForLevel(1),
          unlockedFish: [],
          unlockedDecor: [],
        ) {
    _recalculateProgression();
  }

  /// 🔁 Called when SelectedChild changes
  void setChild(ChildUser child) {
    _child = child;
    _recalculateProgression();
  }

  /// 🔔 Called ONLY when XP changes
  void updateXP(int newXP) {
    if (_child.xp == newXP) return;
    _child = _child.copyWith(xp: newXP);
    _recalculateProgression();
  }

  void _recalculateProgression() {
  final newLevel = _levelCalculator.calculateLevel(_child.xp);
  final world = Worlds.getWorldForLevel(newLevel);

  _lastLevel = newLevel;

  final unlockResolver = UnlockResolver(
    currentLevel: newLevel,
    currentWorld: world.worldId,
  );

  _state = ProgressionState(
    xp: _child.xp,
    level: newLevel,
    world: world,
    unlockedFish: unlockResolver.unlockedFish,
    unlockedDecor: unlockResolver.unlockedDecor,
  );

  final leveledUp = newLevel > _lastLevel;
_lastLevel = newLevel;

if (leveledUp) {
  onLevelUp?.call();
}

  _lastLevel = newLevel;
  notifyListeners();

  achievementManager?.checkAchievements();
}


}

