// ignore_for_file: file_names

import 'package:hive/hive.dart';

part 'ownedFish_model.g.dart';

@HiveType(typeId: 7)
class OwnedFish {
  @HiveField(0)
  final String id;        // unique instance ID

  @HiveField(1)
  final String fishId;    // links to FishDefinition

  @HiveField(2)
  final bool isUnlocked;  // true if unlockable fish has been unlocked

  @HiveField(3)
  final bool isPurchased; // true if bought from shop

  @HiveField(4)
  final bool isActive;    // true if currently active in aquarium

  @HiveField(5)
  final bool isNeglected; // true if neglected (switch animation in UI)

  @HiveField(6)
  bool isSelected;

  OwnedFish({
    required this.id,
    required this.fishId,
    this.isUnlocked = false,
    this.isPurchased = false,
    this.isActive = false,
    this.isNeglected = false,
    this.isSelected = false,
  });

  OwnedFish copyWith({
    String? id,
    String? fishId,
    bool? isUnlocked,
    bool? isPurchased,
    bool? isActive,
    bool? isNeglected,
    bool? isSelected,
  }) {
    return OwnedFish(
      id: id ?? this.id,
      fishId: fishId ?? this.fishId,
      isUnlocked: isUnlocked ?? this.isUnlocked,
      isPurchased: isPurchased ?? this.isPurchased,
      isActive: isActive ?? this.isActive,
      isNeglected: isNeglected ?? this.isNeglected,
      isSelected: isSelected ?? this.isSelected,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'fishId': fishId,
        'isUnlocked': isUnlocked,
        'isPurchased': isPurchased,
        'isActive': isActive,
        'isNeglected': isNeglected,
        'isSelected': isSelected,
      };

  factory OwnedFish.fromMap(Map<String, dynamic> map) => OwnedFish(
        id: map['id'],
        fishId: map['fishId'],
        isUnlocked: map['isUnlocked'] ?? false,
        isPurchased: map['isPurchased'] ?? false,
        isActive: map['isActive'] ?? false,
        isNeglected: map['isNeglected'] ?? false,
        isSelected: map['isSelected'] ?? false,
      );
}
