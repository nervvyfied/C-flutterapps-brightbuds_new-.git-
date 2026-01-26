import '../models/decor_definition.dart';
import 'package:flutter/material.dart';

class DecorCatalog {
  static final List<DecorDefinition> all = [

    // ----- World 1: Aquarium -----

    DecorDefinition(
      id: 'decor2',
      name: 'Purple Seaweed',
      world: 1,
      unlockLevel: 2,
      assetPath: 'assets/decorations/decor2.png',
      layer: 1,
      anchorX: 0.12,
      anchorY: 0.80,
      widthFactor: 0.12,
      description: 'Swaying blue seaweed.',
    ),

    DecorDefinition(
      id: 'decor3',
      name: 'Seaweed',
      world: 1,
      unlockLevel: 4,
      assetPath: 'assets/decorations/decor3.png',
      layer: 0,
      anchorX: 0.50,
      anchorY: 0.60,
      widthFactor: 0.15,
      description: 'Simple seaweed.',
    ),

    DecorDefinition(
      id: 'decor5',
      name: 'Rock 1',
      world: 1,
      unlockLevel: 6,
      assetPath: 'assets/decorations/decor5.png',
      layer: 0,
      anchorX: 0.25,
      anchorY: 0.66,
      widthFactor: 0.15,
      description: 'Round rock.',
    ),

    DecorDefinition(
      id: 'decor7',
      name: 'Pink Seaweed',
      world: 1,
      unlockLevel: 8,
      assetPath: 'assets/decorations/decor7.png',
      layer: 1,
      anchorX: 0.78,
      anchorY: 0.56,
      widthFactor: 0.10,
      description: 'Pink seaweed.',
    ),

    DecorDefinition(
      id: 'decor10',
      name: 'Orange Coral',
      world: 1,
      unlockLevel: 10,
      assetPath: 'assets/decorations/decor4.png',
      layer: 1,
      anchorX: 0.20,
      anchorY: 0.62,
      widthFactor: 0.12,
      description: 'Bright coral.',
    ),

    DecorDefinition(
      id: 'decor12',
      name: 'Sandcastle',
      world: 1,
      unlockLevel: 12,
      assetPath: 'assets/decorations/decor12.png',
      layer: 1,
      anchorX: 0.60,
      anchorY: 0.66,
      widthFactor: 0.15,
      description: 'A tiny sandcastle.',
    ),

    // ----- World 2: Pond -----

    DecorDefinition(
      id: 'decor3_pond',
      name: 'Seaweed',
      world: 2,
      unlockLevel: 14,
      assetPath: 'assets/decorations/decor3.png',
      layer: 1,
      anchorX: 0.15,
      anchorY: 0.60,
      widthFactor: 0.10,
      description: 'Seaweed for the pond.',
    ),

    DecorDefinition(
      id: 'decor6',
      name: 'Rock 2',
      world: 2,
      unlockLevel: 16,
      assetPath: 'assets/decorations/decor6.png',
      layer: 0,
      anchorX: 0.30,
      anchorY: 0.68,
      widthFactor: 0.14,
      description: 'Smooth rock.',
    ),

    DecorDefinition(
      id: 'decor8',
      name: 'Pink Coral',
      world: 2,
      unlockLevel: 18,
      assetPath: 'assets/decorations/decor8.png',
      layer: 1,
      anchorX: 0.62,
      anchorY: 0.62,
      widthFactor: 0.11,
      description: 'Delicate coral.',
    ),

    DecorDefinition(
      id: 'decor9',
      name: 'Crystal Coral',
      world: 2,
      unlockLevel: 20,
      assetPath: 'assets/decorations/decor9.png',
      layer: 1,
      anchorX: 0.35,
      anchorY: 0.60,
      widthFactor: 0.12,
      description: 'Shimmery coral.',
    ),

    DecorDefinition(
      id: 'decor10_pond',
      name: 'Yellow Coral',
      world: 2,
      unlockLevel: 22,
      assetPath: 'assets/decorations/decor10.png',
      layer: 1,
      anchorX: 0.52,
      anchorY: 0.62,
      widthFactor: 0.12,
      description: 'Sunny coral.',
    ),

    DecorDefinition(
      id: 'decor11',
      name: 'Treasure Chest',
      world: 2,
      unlockLevel: 24,
      assetPath: 'assets/decorations/decor11.png',
      layer: 0,
      anchorX: 0.50,
      anchorY: 0.68,
      widthFactor: 0.15,
      description: 'A chest!',
    ),
  ];
  static DecorDefinition byId(String id) {
    return all.firstWhere((d) => d.id == id, orElse: () {
      throw Exception('Decor with id $id not found');
    });
  }

  static List<DecorDefinition> byWorld(int world) =>
      all.where((d) => d.world == world).toList();

  static List<DecorDefinition> byLevel(int level) =>
      all.where((d) => d.unlockLevel <= level).toList();
}


  

