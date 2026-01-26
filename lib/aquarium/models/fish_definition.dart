import 'package:flutter/foundation.dart';

@immutable
class FishDefinition {
  final String id;
  final String name;

  /// Progression
  final int world;        // 1 = Aquarium, 2 = Pond
  final int unlockLevel;  // Level when fish appears

  /// Rendering
  final String normalAsset;     // GIF
  final String neglectedAsset;  // PNG
  final int layer;              // Parallax depth (0 = back)

  final String description;

  const FishDefinition({
    required this.id,
    required this.name,
    required this.world,
    required this.unlockLevel,
    required this.normalAsset,
    required this.neglectedAsset,
    required this.layer,
    this.description = '',
  });
}
