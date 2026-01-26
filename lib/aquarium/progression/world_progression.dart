class WorldProgression {
  final int worldId;
  final String name;
  final int startLevel;
  final int endLevel;

  const WorldProgression({
    required this.worldId,
    required this.name,
    required this.startLevel,
    required this.endLevel,
  });
}

class Worlds {
  static final List<WorldProgression> all = [
    WorldProgression(worldId: 1, name: 'Aquarium', startLevel: 1, endLevel: 12),
    WorldProgression(worldId: 2, name: 'Pond', startLevel: 13, endLevel: 24),
  ];

  static WorldProgression getWorldForLevel(int level) {
    return all.firstWhere(
      (w) => level >= w.startLevel && level <= w.endLevel,
      orElse: () => all.last,
    );
  }
}
