import 'package:flutter/foundation.dart';

@immutable
class DecorDefinition {
  final String id;       // unique decor ID
  final String name;     // e.g., "Rock", "Seaweed"
  final String assetPath;
  final int price;       // purchase cost
  final String description;
  final bool isPlaced;

  const DecorDefinition({
    required this.id,
    required this.name,
    required this.assetPath,
    required this.price,
    this.description = '',
    this.isPlaced = false,
  });

  factory DecorDefinition.fromMap(Map<String, dynamic> map) {
    return DecorDefinition(
      id: map['id'] ?? '',
      name: map['name'] ?? '',
      assetPath: map['assetPath'] ?? '',
      price: map['price'] ?? 0,
      description: map['description'] ?? '',
      isPlaced: map['isPlaced'] ?? false,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'assetPath': assetPath,
      'price': price,
      'description': description,
      'isPlaced': isPlaced,
    };
  }
}
