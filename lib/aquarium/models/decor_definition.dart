class DecorDefinition {
  final String id;
  final String name;
  final int world;
  final int unlockLevel;
  final String assetPath;
  final int layer;

  /// 0..1 relative position
  final double anchorX;
  final double anchorY;
  final double widthFactor;

  final String description;

  const DecorDefinition({
    required this.id,
    required this.name,
    required this.world,
    required this.unlockLevel,
    required this.assetPath,
    required this.layer,
    required this.anchorX,
    required this.anchorY,
    required this.widthFactor,
    required this.description,
  });
}
