import 'package:flutter/foundation.dart';

@immutable
class FishDefinition {
  final String id;                // unique fish ID
  final String name;              // e.g., "Clownfish"
  final String assetPath;         // sprite or animation asset path
  final String unlockConditionId; // milestone key, e.g., "first_task"
  final String description;       // optional flavor text

  const FishDefinition({
    required this.id,
    required this.name,
    required this.assetPath,
    required this.unlockConditionId,
    this.description = '',
  });

  factory FishDefinition.fromMap(Map<String, dynamic> map) {
    return FishDefinition(
      id: map['id'] ?? '',
      name: map['name'] ?? '',
      assetPath: map['assetPath'] ?? '',
      unlockConditionId: map['unlockConditionId'] ?? '',
      description: map['description'] ?? '',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'assetPath': assetPath,
      'unlockConditionId': unlockConditionId,
      'description': description,
    };
  }
}
