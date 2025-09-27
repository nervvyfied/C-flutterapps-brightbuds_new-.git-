import 'package:flutter/foundation.dart';

@immutable
class OwnedFish {
  final String fishDefinitionId; // links to FishDefinition
  final bool isUnlocked;         // true if child has unlocked this fish
  final bool isActive;           // true if currently displayed in aquarium
  final DateTime? acquiredAt;    // timestamp when first unlocked

  const OwnedFish({
    required this.fishDefinitionId,
    this.isUnlocked = false,
    this.isActive = false,
    this.acquiredAt,
  });

  // Factory constructor from Firestore/Hive map
  factory OwnedFish.fromMap(Map<String, dynamic> map) {
    return OwnedFish(
      fishDefinitionId: map['fishDefinitionId'] ?? '',
      isUnlocked: map['isUnlocked'] ?? false,
      isActive: map['isActive'] ?? false,
      acquiredAt: map['acquiredAt'] != null
          ? DateTime.tryParse(map['acquiredAt'])
          : null,
    );
  }

  // Convert to Map for Firestore/Hive
  Map<String, dynamic> toMap() {
    return {
      'fishDefinitionId': fishDefinitionId,
      'isUnlocked': isUnlocked,
      'isActive': isActive,
      'acquiredAt': acquiredAt?.toIso8601String(),
    };
  }

  // Copy with method for immutability
  OwnedFish copyWith({
    String? fishDefinitionId,
    bool? isUnlocked,
    bool? isActive,
    DateTime? acquiredAt,
  }) {
    return OwnedFish(
      fishDefinitionId: fishDefinitionId ?? this.fishDefinitionId,
      isUnlocked: isUnlocked ?? this.isUnlocked,
      isActive: isActive ?? this.isActive,
      acquiredAt: acquiredAt ?? this.acquiredAt,
    );
  }
}
