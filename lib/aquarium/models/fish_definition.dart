// ignore: unused_import
import 'package:flutter/material.dart';

enum FishType { unlockable, purchasable }

class FishDefinition {
  final String id;                  // unique fish ID
  final String name;
  final FishType type;              // unlockable or purchasable
  final String normalAsset;         // normal animation
  final String neglectedAsset;      // neglected animation
  final String storeIconAsset;      // static icon for shop/inventory
  final String unlockConditionId;   // only for unlockable
  final int price;                  // only for purchasable
  final String description;

  const FishDefinition({
    required this.id,
    required this.name,
    required this.type,
    required this.normalAsset,
    required this.neglectedAsset,
    required this.storeIconAsset,
    this.unlockConditionId = '',
    this.price = 0,
    this.description = '',
  });

  factory FishDefinition.fromMap(Map<String, dynamic> map) {
    return FishDefinition(
      id: map['id'] ?? '',
      name: map['name'] ?? '',
      type: map['type'] == 'purchasable' 
          ? FishType.purchasable 
          : FishType.unlockable,
      normalAsset: map['normalAsset'] ?? '',
      neglectedAsset: map['neglectedAsset'] ?? '',
      storeIconAsset: map['storeIconAsset'] ?? '',
      unlockConditionId: map['unlockConditionId'] ?? '',
      price: map['price'] ?? 0,
      description: map['description'] ?? '',
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'type': type == FishType.purchasable ? 'purchasable' : 'unlockable',
        'normalAsset': normalAsset,
        'neglectedAsset': neglectedAsset,
        'storeIconAsset': storeIconAsset,
        'unlockConditionId': unlockConditionId,
        'price': price,
        'description': description,
      };
}
